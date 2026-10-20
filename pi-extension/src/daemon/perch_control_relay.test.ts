import { EventEmitter } from "node:events";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { PerchControl } from "./perch_control.js";
import { PerchControlRelay } from "./perch_control_relay.js";
import { PERCH_CONTROL_ROOM } from "./perch_control_protocol.js";

const owner = Buffer.alloc(32, 1).toString("base64");
const unknown = Buffer.alloc(32, 2).toString("base64");
class FakeRelay extends EventEmitter {
  sent: { peer: string; body: Record<string, unknown> }[] = [];
  connect = vi.fn(async (_options: unknown) => {});
  close = vi.fn(() => { this.emit("close"); });
  send(line: string) {
    const envelope = JSON.parse(line);
    this.sent.push({ peer: envelope.peer, body: JSON.parse(Buffer.from(envelope.ct, "base64").toString()) });
  }
  inbound(peer: string, body: unknown) {
    this.emit("message", JSON.stringify({ peer, ct: Buffer.from(JSON.stringify(body)).toString("base64") }));
  }
}
let root: string;
let endpoint: PerchControlRelay;
let transports: FakeRelay[];
let ipc: ReturnType<typeof vi.fn>;
const cap = { type: "perch_capabilities_get", id: "cap" };
const start = { type: "perch_request", id: "start", version: 1, method: "daemon.start", params: { id: "1234abcd" } };
async function drain() { for (let i = 0; i < 40; i++) await Promise.resolve(); }
beforeEach(() => {
  vi.useFakeTimers();
  root = mkdtempSync(join(tmpdir(), "perch-relay-"));
  const configPath = join(root, "config.json");
  writeFileSync(configPath, JSON.stringify({ enabled: true, owners: { [owner]: {
    operations: ["daemon.start"], daemon_ids: ["1234abcd"],
  } } }));
  ipc = vi.fn(async (req) => req.op === "list" ? { daemons: [] } : req.op === "cron_list" ? { jobs: [] } : { started: true });
  const control = new PerchControl({ configPath, journalPath: join(root, "journal.json"),
    isPaired: async (peer) => peer === owner, ipc });
  transports = [];
  endpoint = new PerchControlRelay(control, () => { const transport = new FakeRelay(); transports.push(transport); return transport; });
});
afterEach(() => { endpoint.stop(); vi.useRealTimers(); rmSync(root, { recursive: true, force: true }); });

test("reserved room authenticates sender envelope, ignores claimed inner owner and unrelated messages", async () => {
  endpoint.start(); await drain();
  const relay = transports[0];
  expect(relay.connect).toHaveBeenCalledWith({ roomId: PERCH_CONTROL_ROOM, roomMeta: { name: "Perch Control", cwd: "" } });
  relay.inbound(unknown, { ...cap, owner }); await drain();
  expect(relay.sent[0]).toMatchObject({ peer: unknown, body: { type: "perch_error", error: { code: "unauthorized" } } });
  relay.inbound(owner, cap); await drain();
  relay.inbound(owner, start); await drain();
  expect(relay.sent.at(-1)).toMatchObject({ peer: owner, body: { type: "perch_result", id: "start" } });
  expect(ipc.mock.calls.filter(([req]) => req.op === "start")).toHaveLength(1);
  relay.inbound(owner, { type: "prompt", text: "never forward" });
  relay.emit("message", "malformed");
  await drain();
  expect(relay.sent).toHaveLength(3);
});

test("reconnect negotiates anew and stopping endpoint cancels reconnect", async () => {
  endpoint.start(); await drain();
  transports[0].inbound(owner, cap); await drain();
  transports[0].emit("close");
  await vi.advanceTimersByTimeAsync(2000); await drain();
  expect(transports).toHaveLength(2);
  transports[1].inbound(owner, start); await drain();
  expect(transports[1].sent.at(-1)).toMatchObject({ body: { error: { code: "unsupported" } } });
  expect(ipc).not.toHaveBeenCalled();
  transports[1].inbound(owner, cap); await drain();
  transports[1].inbound(owner, start); await drain();
  expect(ipc.mock.calls.filter(([req]) => req.op === "start")).toHaveLength(1);
  endpoint.stop();
  transports[1].inbound(owner, { ...start, id: "after-stop" });
  await vi.advanceTimersByTimeAsync(10_000); await drain();
  expect(transports).toHaveLength(2);
  expect(ipc.mock.calls.filter(([req]) => req.op === "start")).toHaveLength(1);
});

test("connect has a deadline and retries without leaked control authority", async () => {
  const stalled = new FakeRelay();
  stalled.connect = vi.fn(() => new Promise<void>(() => {}));
  endpoint = new PerchControlRelay({ disconnect: vi.fn() } as unknown as PerchControl, () => stalled);
  endpoint.start();
  await vi.advanceTimersByTimeAsync(12_000);
  expect(stalled.close).toHaveBeenCalledTimes(1);
  endpoint.stop();
  await vi.advanceTimersByTimeAsync(5000);
  expect(stalled.connect).toHaveBeenCalledTimes(1);
});
