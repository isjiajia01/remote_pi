import { createHash, createPrivateKey, randomUUID, sign, type KeyObject } from "node:crypto";
import { chmodSync, mkdirSync, readFileSync, readdirSync, renameSync, unlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, join } from "node:path";
import { connect } from "node:http2";
import { perchError, type PerchServerMessage } from "./protocol/perch.js";
import { pushPayload, validPushEnvironment, validPushToken,
  type PushClientMessage, type PushEnvironment, type PushEvent, type PushResult } from "./protocol/push.js";

export type PushConfig = { enabled: false } | {
  enabled: true; key_path: string; key_id: string; team_id: string;
  topic: "dev.zhangjiajia.perch"; environment: PushEnvironment;
};
function remoteDir(): string { return join(process.env.REMOTE_PI_HOME ?? homedir(), ".pi", "remote"); }
export function pushConfigPath(): string {
  return process.env.PERCH_PUSH_CONFIG_PATH ?? join(remoteDir(), "perch-push.json");
}
export function pushTokenDir(): string {
  return process.env.PERCH_PUSH_TOKEN_DIR ?? join(remoteDir(), "perch-push-tokens");
}

/** No key access or network unless locally opted in. Invalid configuration disables push. */
export function loadPushConfig(path = pushConfigPath()): PushConfig {
  try {
    const value = JSON.parse(readFileSync(path, "utf8")) as Record<string, unknown>;
    if (!value || value.enabled !== true ||
        Object.keys(value).some((key) => !["enabled", "key_path", "key_id", "team_id", "topic", "environment"].includes(key)) ||
        typeof value.key_path !== "string" || !isAbsolute(value.key_path) ||
        typeof value.key_id !== "string" || !/^[A-Z0-9]{10}$/.test(value.key_id) ||
        typeof value.team_id !== "string" || !/^[A-Z0-9]{10}$/.test(value.team_id) ||
        value.topic !== "dev.zhangjiajia.perch" || !validPushEnvironment(value.environment)) return { enabled: false };
    return value as Extract<PushConfig, { enabled: true }>;
  } catch { return { enabled: false }; }
}

type Device = { owner: string; token: string; environment: PushEnvironment; registration: string };
/** Separate atomic files avoid lost updates between extension processes sharing this directory. */
export class PushTokenRegistry {
  constructor(private readonly dir = pushTokenDir()) {}
  private path(device: Pick<Device, "owner" | "token" | "environment">): string {
    const hash = createHash("sha256").update(JSON.stringify([device.owner, device.environment, device.token])).digest("hex");
    return join(this.dir, `${hash}.json`);
  }
  register(owner: string, token: string, environment: PushEnvironment): void {
    if (!owner || !validPushToken(token) || !validPushEnvironment(environment)) throw new Error("Invalid push registration");
    const device: Device = { owner, token: token.toLowerCase(), environment, registration: randomUUID() };
    mkdirSync(this.dir, { recursive: true, mode: 0o700 });
    chmodSync(this.dir, 0o700);
    const target = this.path(device);
    const temp = `${target}.${randomUUID()}.tmp`;
    try {
      writeFileSync(temp, JSON.stringify(device), { mode: 0o600, flag: "wx" });
      renameSync(temp, target);
    } finally { try { unlinkSync(temp); } catch { /* already renamed */ } }
  }
  unregister(owner: string, token: string, environment: PushEnvironment): void {
    try { unlinkSync(this.path({ owner, token: token.toLowerCase(), environment })); }
    catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
  }
  devices(owner: string, environment: PushEnvironment): Device[] {
    let files: string[];
    try { files = readdirSync(this.dir); }
    catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return []; throw error; }
    const devices: Device[] = [];
    for (const file of files) {
      if (!/^[a-f0-9]{64}\.json$/.test(file)) continue;
      try {
        const device = JSON.parse(readFileSync(join(this.dir, file), "utf8")) as Device;
        if (device.owner === owner && device.environment === environment && validPushToken(device.token) &&
            typeof device.registration === "string" && this.path(device) === join(this.dir, file)) devices.push(device);
      } catch { /* a corrupt record never authorizes delivery */ }
    }
    return devices;
  }
  removeInvalid(device: Device): void {
    try {
      const current = JSON.parse(readFileSync(this.path(device), "utf8")) as Device;
      // An in-flight rejection must not delete a fresh registration.
      if (current.registration === device.registration) this.unregister(device.owner, device.token, device.environment);
    } catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
  }
}

export class ApnsProviderToken {
  private cached: { value: string; issued: number } | undefined;
  private key: KeyObject | undefined;
  constructor(private readonly config: Extract<PushConfig, { enabled: true }>, private readonly now = Date.now) {}
  get(): string {
    const issued = Math.floor(this.now() / 1000);
    if (this.cached && issued >= this.cached.issued && issued - this.cached.issued < 50 * 60) return this.cached.value;
    this.key ??= createPrivateKey(readFileSync(this.config.key_path));
    if (this.key.asymmetricKeyType !== "ec" || this.key.asymmetricKeyDetails?.namedCurve !== "prime256v1") {
      throw new Error("APNs requires an ES256 key");
    }
    const header = Buffer.from(JSON.stringify({ alg: "ES256", kid: this.config.key_id })).toString("base64url");
    const claims = Buffer.from(JSON.stringify({ iss: this.config.team_id, iat: issued })).toString("base64url");
    const unsigned = `${header}.${claims}`;
    const signature = sign("sha256", Buffer.from(unsigned), { key: this.key, dsaEncoding: "ieee-p1363" }).toString("base64url");
    const value = `${unsigned}.${signature}`;
    this.cached = { value, issued };
    return value;
  }
  invalidate(): void { this.cached = undefined; }
}

type ApnsResponse = { status: number; reason?: string };
/** endpoint is injectable only in code, never by remote registration or config. */
export class ApnsSender {
  private readonly provider: ApnsProviderToken;
  constructor(private readonly config: Extract<PushConfig, { enabled: true }>,
    private readonly endpoint = config.environment === "sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com",
    now = Date.now, private readonly timeoutMs = 5000) {
    this.provider = new ApnsProviderToken(config, now);
  }
  async send(token: string, event: PushEvent): Promise<ApnsResponse> {
    if (!validPushToken(token)) throw new Error("Invalid APNs device token");
    const response = await this.request(token, event);
    if (response.status === 403 && response.reason === "ExpiredProviderToken") {
      this.provider.invalidate();
      return this.request(token, event);
    }
    return response;
  }
  private request(token: string, event: PushEvent): Promise<ApnsResponse> {
    const authorization = `bearer ${this.provider.get()}`;
    const collapseId = createHash("sha256").update(JSON.stringify([event.kind, event.event_id])).digest("hex");
    return new Promise((resolve, reject) => {
      const session = connect(this.endpoint);
      const finish = (error?: Error, response?: ApnsResponse) => {
        clearTimeout(timer);
        session.destroy();
        if (error) reject(error); else resolve(response!);
      };
      const timer = setTimeout(() => finish(new Error("APNs request timed out")), this.timeoutMs);
      session.on("error", () => finish(new Error("APNs connection failed")));
      const request = session.request({ ":method": "POST", ":path": `/3/device/${token}`,
        authorization, "apns-topic": this.config.topic, "apns-push-type": "alert", "apns-priority": "10",
        "apns-collapse-id": collapseId, "content-type": "application/json" });
      let status = 0;
      let body = "";
      request.on("response", (headers) => { status = Number(headers[":status"]); });
      request.setEncoding("utf8");
      request.on("data", (chunk: string) => {
        body += chunk;
        if (body.length > 8192) finish(new Error("APNs response exceeds limit"));
      });
      request.on("error", () => finish(new Error("APNs stream failed")));
      request.on("end", () => {
        let reason: string | undefined;
        try { const parsed = JSON.parse(body) as { reason?: unknown }; if (typeof parsed.reason === "string") reason = parsed.reason; } catch { /* empty success */ }
        finish(undefined, { status, reason });
      });
      request.on("close", () => { if (!request.readableEnded) finish(new Error("APNs stream closed")); });
      request.end(JSON.stringify(pushPayload(event)));
    });
  }
}

export class PerchPush {
  private readonly seen = new Set<string>();
  private readonly sender: ApnsSender | undefined;
  constructor(private readonly config: PushConfig, private readonly registry: PushTokenRegistry,
    private readonly paired: (owner: string) => Promise<boolean>, sender?: ApnsSender) {
    this.sender = config.enabled ? sender ?? new ApnsSender(config) : undefined;
  }
  async handle(owner: string, msg: PushClientMessage, authenticated: () => Promise<boolean>): Promise<PushResult | PerchServerMessage> {
    const id = typeof msg.id === "string" ? msg.id : "";
    try {
      if (!await authenticated() || !await this.paired(owner) || msg.owner !== owner) return perchError(id, "unauthorized", "Sender is not a paired Owner");
      if (msg.version !== 1) return perchError(id, "unsupported", "Unsupported push version");
      if (!id || id.length > 256 || !validPushToken(msg.token) || !validPushEnvironment(msg.environment) ||
          !["perch_push_register", "perch_push_unregister"].includes(msg.type) ||
          Object.keys(msg).some((key) => !["type", "id", "version", "owner", "token", "environment"].includes(key))) {
        return perchError(id, "invalid_argument", "Invalid push registration");
      }
      if (msg.type === "perch_push_register" && !this.config.enabled) return perchError(id, "forbidden", "Push is disabled locally");
      // Recheck after asynchronous authorization and commit without an intervening await.
      if (!await this.paired(owner) || !await authenticated()) return perchError(id, "unauthorized", "Sender is not a paired Owner");
      if (msg.type === "perch_push_register") this.registry.register(owner, msg.token, msg.environment);
      else this.registry.unregister(owner, msg.token, msg.environment);
      return { type: "perch_push_result", id, version: 1, registered: msg.type === "perch_push_register" };
    } catch { return perchError(id, "internal", "Push registration failed"); }
  }
  async notify(owner: string, event: PushEvent): Promise<void> {
    if (!this.config.enabled || !this.sender) return;
    const key = JSON.stringify([owner, event.kind, event.event_id]);
    if (this.seen.has(key)) return;
    this.seen.add(key); // Includes in-flight sends; network failure never delays tool execution.
    if (this.seen.size > 4096) this.seen.delete(this.seen.values().next().value!);
    try {
      for (const device of this.registry.devices(owner, this.config.environment)) {
        if (!await this.paired(owner)) return;
        try {
          const result = await this.sender.send(device.token, event);
          if (result.status === 410 || result.reason === "BadDeviceToken") this.registry.removeInvalid(device);
        } catch { /* best effort; never log tokens, payloads or key material */ }
      }
    } catch { /* local registry unavailable */ }
  }
}
