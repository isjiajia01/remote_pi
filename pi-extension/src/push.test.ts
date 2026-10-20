import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { generateKeyPairSync, verify } from "node:crypto";
import { chmodSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { createServer, type IncomingHttpHeaders } from "node:http2";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { ApnsProviderToken, ApnsSender, loadPushConfig, PerchPush, PushTokenRegistry, type PushConfig } from "./push.js";
import { pushPayload, type PushClientMessage, type PushEvent } from "./protocol/push.js";
import { decodeServer, encodeClient } from "./protocol/codec.js";

const fixture = JSON.parse(readFileSync(new URL("../../.orchestration/contracts/perch-v1/push.json", import.meta.url), "utf8"));
const token = "a".repeat(64);
const owner = "paired-owner";
let dir: string;
let config: Extract<PushConfig, { enabled: true }>;
let registry: PushTokenRegistry;
let publicKey: ReturnType<typeof generateKeyPairSync>["publicKey"];
let server: ReturnType<typeof createServer>;
let endpoint: string;
let received: { headers: IncomingHttpHeaders; body: Record<string, unknown> }[];
let responses: { status: number; reason?: string }[];

beforeEach(async () => {
  dir = mkdtempSync(join(tmpdir(), "perch-push-"));
  const pair = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  publicKey = pair.publicKey;
  const keyPath = join(dir, "throwaway.p8");
  writeFileSync(keyPath, pair.privateKey.export({ format: "pem", type: "pkcs8" }), { mode: 0o600 });
  config = { enabled: true, key_path: keyPath, key_id: "TESTKEY001", team_id: "TESTTEAM01",
    topic: "dev.zhangjiajia.perch", environment: "sandbox" };
  registry = new PushTokenRegistry(join(dir, "tokens"));
  received = [];
  responses = [];
  server = createServer();
  server.on("stream", (stream, headers) => {
    let body = "";
    stream.setEncoding("utf8");
    stream.on("data", (chunk: string) => { body += chunk; });
    stream.on("end", () => {
      received.push({ headers, body: JSON.parse(body) });
      const response = responses.shift() ?? { status: 200 };
      stream.respond({ ":status": response.status });
      stream.end(response.reason ? JSON.stringify({ reason: response.reason }) : "");
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("Missing fake server port");
  endpoint = `http://127.0.0.1:${address.port}`;
});
afterEach(async () => {
  await new Promise<void>((resolve) => server.close(() => resolve()));
  vi.restoreAllMocks();
  rmSync(dir, { recursive: true, force: true });
});
function service(paired = async () => true): PerchPush {
  return new PerchPush(config, registry, paired, new ApnsSender(config, endpoint));
}
function registration(patch: Partial<PushClientMessage> = {}): PushClientMessage {
  return { ...fixture.register.request, ...patch };
}
function claims(jwt: string): Record<string, unknown> { return JSON.parse(Buffer.from(jwt.split(".")[1], "base64url").toString()); }

describe("Perch opt-in APNs", () => {
  test("absent, disabled and malformed configs never enable push; config path is overridable", async () => {
    const path = join(dir, "perch-push.json");
    expect(loadPushConfig(path)).toEqual({ enabled: false });
    for (const value of ["{", "null", JSON.stringify({ enabled: false, key_path: "/does-not-exist" }),
      JSON.stringify({ ...config, environment: "bad" }), JSON.stringify({ ...config, extra: 1 })]) {
      writeFileSync(path, value);
      expect(loadPushConfig(path)).toEqual({ enabled: false });
    }
    writeFileSync(path, JSON.stringify(config));
    expect(loadPushConfig(path)).toEqual(config);
    vi.stubEnv("PERCH_PUSH_CONFIG_PATH", path);
    expect(loadPushConfig()).toEqual(config);
    vi.unstubAllEnvs();
    const off = new PerchPush({ enabled: false }, registry, async () => true);
    expect(await off.handle(owner, registration(), async () => true)).toHaveProperty("error.code", "forbidden");
    await off.notify(owner, fixture.approval.event);
    expect(received).toHaveLength(0);
    expect(readdirSync(dir)).not.toContain("tokens");
  });

  test("ES256 JWT verifies, caches below 50 minutes, refreshes at boundary and clock rollback", () => {
    let now = 1_800_000_000_000;
    const provider = new ApnsProviderToken(config, () => now);
    const first = provider.get();
    const [header, payload, signature] = first.split(".");
    expect(JSON.parse(Buffer.from(header, "base64url").toString())).toEqual({ alg: "ES256", kid: config.key_id });
    expect(claims(first)).toEqual({ iss: config.team_id, iat: now / 1000 });
    expect(Buffer.from(signature, "base64url")).toHaveLength(64);
    expect(verify("sha256", Buffer.from(`${header}.${payload}`), { key: publicKey, dsaEncoding: "ieee-p1363" }, Buffer.from(signature, "base64url"))).toBe(true);
    now += 50 * 60 * 1000 - 1000;
    expect(provider.get()).toBe(first);
    now += 1000;
    const refreshed = provider.get();
    expect(claims(refreshed).iat).toBe(now / 1000);
    expect(refreshed).not.toBe(first);
    now -= 1000;
    expect(claims(provider.get()).iat).toBe(now / 1000);
  });

  test("golden registrations are authorized, persisted 0600, idempotent and isolated by Owner/environment", async () => {
    const push = service();
    for (const f of [fixture.register, fixture.unregister]) {
      expect(JSON.parse(encodeClient(f.request))).toEqual(f.request);
      expect(decodeServer(JSON.stringify(f.response))).toEqual(f.response);
      expect(await push.handle(owner, f.request, async () => true)).toEqual(f.response);
    }
    await push.handle(owner, registration(), async () => true);
    await push.handle(owner, registration({ token: token.toUpperCase() }), async () => true);
    registry.register("other-owner", token, "sandbox");
    registry.register(owner, token, "production");
    expect(new PushTokenRegistry(join(dir, "tokens")).devices(owner, "sandbox")).toHaveLength(1);
    const files = readdirSync(join(dir, "tokens"));
    expect(files).toHaveLength(3);
    for (const file of files) expect(statSync(join(dir, "tokens", file)).mode & 0o777).toBe(0o600);
    expect(statSync(join(dir, "tokens")).mode & 0o777).toBe(0o700);
    chmodSync(join(dir, "tokens", files[0]), 0o644);
    // New atomic registration always replaces with a private file.
    registry.register(owner, token, "sandbox");
    const device = registry.devices(owner, "sandbox")[0];
    registry.register(owner, token, "sandbox");
    registry.removeInvalid(device);
    expect(registry.devices(owner, "sandbox")).toHaveLength(1);
    await push.handle(owner, fixture.unregister.request, async () => true);
    expect(registry.devices(owner, "sandbox")).toHaveLength(0);
    expect(registry.devices("other-owner", "sandbox")).toHaveLength(1);
    expect(registry.devices(owner, "production")).toHaveLength(1);
  });

  test("spoofed, revoked, disconnected and malformed registrations cannot write or unregister", async () => {
    const push = service();
    expect(await push.handle(owner, registration({ owner: "other-owner" }), async () => true)).toHaveProperty("error.code", "unauthorized");
    expect(await push.handle(owner, registration(), async () => false)).toHaveProperty("error.code", "unauthorized");
    expect(await service(async () => false).handle(owner, registration(), async () => true)).toHaveProperty("error.code", "unauthorized");
    for (const patch of [{ token: "../escape" }, { environment: "invalid" }, { id: "" }, { version: 2 }, { extra: "bad" }]) {
      expect(await push.handle(owner, registration(patch as Partial<PushClientMessage>), async () => true)).toHaveProperty("type", "perch_error");
    }
    let calls = 0;
    expect(await push.handle(owner, registration(), async () => ++calls === 1)).toHaveProperty("error.code", "unauthorized");
    expect(registry.devices(owner, "sandbox")).toEqual([]);
    registry.register(owner, token, "sandbox");
    expect(await push.handle("other-owner", fixture.unregister.request, async () => true)).toHaveProperty("error.code", "unauthorized");
    expect(registry.devices(owner, "sandbox")).toHaveLength(1);
  });

  test("HTTP/2 headers, opaque fixture payloads and concurrent per-event dedup", async () => {
    registry.register(owner, token, "sandbox");
    registry.register(owner, "b".repeat(64), "production");
    const push = service();
    const event = { ...fixture.approval.event, args: { secret: "DO NOT SEND" }, text: "private chat" } as PushEvent;
    expect(pushPayload(event)).toEqual(fixture.approval.payload);
    await Promise.all([push.notify(owner, event), push.notify(owner, event)]);
    expect(received).toHaveLength(1);
    const { headers, body } = received[0];
    expect(headers).toMatchObject({ ":method": "POST", ":path": `/3/device/${token}`,
      "apns-topic": config.topic, "apns-push-type": "alert", "apns-priority": "10" });
    expect(headers["apns-collapse-id"]).toMatch(/^[a-f0-9]{64}$/);
    expect(headers.authorization).toMatch(/^bearer /);
    expect(body).toEqual(fixture.approval.payload);
    await push.notify(owner, fixture.finished.event);
    expect(received[1].body).toEqual(fixture.finished.payload);
    expect(received[1].headers.authorization).toBe(headers.authorization);
    expect(received[1].headers["apns-collapse-id"]).not.toBe(headers["apns-collapse-id"]);
    await service(async () => false).notify(owner, fixture.finished.event);
    expect(received).toHaveLength(2);
  });

  test.each([{ status: 410, reason: "Unregistered" }, { status: 400, reason: "BadDeviceToken" }])("removes invalid device on $reason", async (response) => {
    registry.register(owner, token, "sandbox");
    registry.register("other-owner", token, "sandbox");
    responses.push(response);
    await service().notify(owner, fixture.approval.event);
    expect(registry.devices(owner, "sandbox")).toHaveLength(0);
    expect(registry.devices("other-owner", "sandbox")).toHaveLength(1);
  });

  test("connection failures and hung HTTP/2 streams are bounded and retain devices", async () => {
    const hanging = createServer();
    const sessions = new Set<import("node:http2").ServerHttp2Session>();
    hanging.on("session", (session) => { sessions.add(session); session.on("close", () => sessions.delete(session)); });
    await new Promise<void>((resolve) => hanging.listen(0, "127.0.0.1", resolve));
    const address = hanging.address();
    if (!address || typeof address === "string") throw new Error("No hanging port");
    const url = `http://127.0.0.1:${address.port}`;
    try {
      const sender = new ApnsSender(config, url, Date.now, 25);
      await expect(sender.send(token, fixture.finished.event)).rejects.toThrow("timed out");
      registry.register(owner, token, "sandbox");
      await new PerchPush(config, registry, async () => true, sender).notify(owner, fixture.finished.event);
      expect(registry.devices(owner, "sandbox")).toHaveLength(1);
    } finally {
      for (const session of sessions) session.destroy();
      await new Promise<void>((resolve) => hanging.close(() => resolve()));
    }
    await expect(new ApnsSender(config, url).send(token, fixture.finished.event)).rejects.toThrow(/connection failed|stream failed/);
    await expect(new ApnsSender(config, endpoint).send("../invalid", fixture.finished.event)).rejects.toThrow("Invalid APNs device token");
  });

  test("transient errors retain devices, expired provider tokens refresh once", async () => {
    registry.register(owner, token, "sandbox");
    responses.push({ status: 500, reason: "InternalServerError" });
    await service().notify(owner, fixture.finished.event);
    expect(registry.devices(owner, "sandbox")).toHaveLength(1);
    responses.push({ status: 403, reason: "ExpiredProviderToken" });
    await new ApnsSender(config, endpoint).send(token, fixture.approval.event);
    expect(received).toHaveLength(3);
    expect(received[1].headers.authorization).not.toBe(received[2].headers.authorization);
    expect(received[1].headers["apns-collapse-id"]).toBe(received[2].headers["apns-collapse-id"]);
  });
});
