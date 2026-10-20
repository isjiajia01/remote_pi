import { readFileSync } from "node:fs";
import { describe, expect, test, vi } from "vitest";
import { decodeServer, encodeClient } from "./codec.js";
import { handlePerchMessage, perchCapabilities, validatePerchRequest,
  PERCH_LIMITS, type PerchClientMessage, type PerchServerMessage } from "./perch.js";
import { PerchBrokerReads } from "../session/perch_reads.js";

function fixture(name: string) {
  return JSON.parse(readFileSync(new URL(`../../../.orchestration/contracts/perch-v1/${name}.json`, import.meta.url), "utf8"));
}
function request(method = "agents.list", params: Record<string, unknown> = {}): PerchClientMessage {
  return { type: "perch_request", id: "read-1", version: 1, method, params };
}
const authorized = async () => true;
const wireError = (code: string) => ({ type: "perch_error", version: 1, error: { code } });

describe("Perch golden wire fixtures", () => {
  test.each(["capabilities", "agents-list", "agents-events", "replay-gap"])("%s encodes/decodes", (name) => {
    const f = fixture(name);
    expect(JSON.parse(encodeClient(f.request))).toEqual(f.request);
    expect(decodeServer(JSON.stringify(f.response))).toEqual(f.response);
    if (name !== "capabilities") expect(validatePerchRequest(f.request)).not.toHaveProperty("type");
  });
  test("capabilities are explicit, versioned and delivery-only", async () => {
    const f = fixture("capabilities");
    expect(perchCapabilities(f.request.id)).toEqual(f.response);
    expect(await handlePerchMessage(f.request, authorized, null)).toEqual(f.response);
  });
  test("all defined errors decode", () => {
    const errors = fixture("errors");
    expect(errors.map((e: PerchServerMessage) => decodeServer(JSON.stringify(e)))).toEqual(errors);
    expect(errors.map((e: { error: { code: string } }) => e.error.code)).toEqual([
      "unauthorized", "forbidden", "unsupported", "invalid_argument", "offline", "timeout", "internal",
    ]);
  });
  test("snapshot and routed replay match golden responses exactly", async () => {
    const f = fixture("agents-list");
    const broker = new PerchBrokerReads(() => f.response.result.agents);
    // Stable test epoch/timestamps; production epochs are generated per broker lifetime.
    Object.defineProperty(broker, "epoch", { value: "broker-epoch-1" });
    broker.record({ type: "peer_joined", agent: f.response.result.agents[0] });
    expect(await broker.read(f.request)).toEqual(f.response);
    const events = fixture("agents-events");
    const { cursor: _, ts, ...event } = events.response.result.events[0];
    const clock = vi.spyOn(Date, "now").mockReturnValue(ts);
    broker.record(event);
    clock.mockRestore();
    expect(await broker.read(events.request)).toEqual(events.response);
    // Replaying an unchanged cursor returns the exact same audit identity, id and re.
    expect(await broker.read(events.request)).toEqual(events.response);
    broker.close();
  });
});

describe("Perch bounded broker replay", () => {
  test("expired cursor forces snapshot resync and matches gap fixture", async () => {
    const broker = new PerchBrokerReads(() => []);
    Object.defineProperty(broker, "epoch", { value: "broker-epoch-1" });
    for (let i = 0; i <= PERCH_LIMITS.retention; i++) {
      broker.record({ type: "peer_joined", agent: { cwd: "", name: "a", address: "a" } });
    }
    const f = fixture("replay-gap");
    expect(await broker.read(f.request)).toEqual(f.response);
    const snapshot = await broker.read(request());
    expect(snapshot).toMatchObject({ result: { revision: 513, cursor: 513 } });
    expect(await broker.read(request("agents.events", { epoch: broker.epoch, cursor: 513 })))
      .toMatchObject({ result: { events: [], resync_required: false, cursor: 513 } });
    broker.close();
  });
  test.each([{}, { epoch: "previous", cursor: 0 }])("missing/foreign epoch resyncs", async (params) => {
    const broker = new PerchBrokerReads(() => []);
    expect(await broker.read(request("agents.events", params)))
      .toMatchObject({ result: { resync_required: true } });
    expect(await broker.read(request("agents.events", { epoch: broker.epoch, cursor: 1 })))
      .toMatchObject({ result: { resync_required: true } });
    broker.close();
  });
  test("pagination retains cursor order and reconnect replays consistently", async () => {
    const broker = new PerchBrokerReads(() => []);
    for (let i = 0; i < 3; i++) broker.record({ type: "peer_left", agent: { cwd: "", name: "a", address: "a" } });
    const page = await broker.read(request("agents.events", { epoch: broker.epoch, cursor: 0, limit: 2 }));
    expect(page).toMatchObject({ result: { cursor: 2, events: [{ cursor: 1 }, { cursor: 2 }] } });
    expect(await broker.read(request("agents.events", { epoch: broker.epoch, cursor: 2, limit: 2 })))
      .toMatchObject({ result: { cursor: 3, events: [{ cursor: 3 }] } });
    broker.close();
  });
  test("long polls wake, time out successfully, enforce limits and release on abort", async () => {
    const broker = new PerchBrokerReads(() => []);
    const poll = () => request("agents.events", { epoch: broker.epoch, cursor: 0, wait_ms: 1000 });
    const controller = new AbortController();
    const pending = Array.from({ length: 8 }, () => broker.read(poll(), controller.signal));
    expect(await broker.read(poll())).toMatchObject(wireError("forbidden"));
    controller.abort();
    for (const result of await Promise.all(pending)) expect(result).toMatchObject(wireError("offline"));
    const wake = broker.read(poll());
    broker.record({ type: "peer_joined", agent: { cwd: "", name: "a", address: "a" } });
    expect(await wake).toMatchObject({ result: { events: [{ cursor: 1 }] } });
    expect(await broker.read(request("agents.events", { epoch: broker.epoch, cursor: 1, wait_ms: 1 })))
      .toMatchObject({ result: { cursor: 1, events: [], resync_required: false } });
    const closing = broker.read(request("agents.events", { epoch: broker.epoch, cursor: 1, wait_ms: 1000 }));
    broker.close();
    expect(await closing).toMatchObject(wireError("offline"));
  });
});

describe("Perch boundary", () => {
  test("rejects unpaired sender before touching broker", async () => {
    const backend = vi.fn();
    expect(await handlePerchMessage(request(), async () => false, backend)).toMatchObject(wireError("unauthorized"));
    expect(backend).not.toHaveBeenCalled();
  });
  test("rechecks revocation after a read", async () => {
    let allowed = true;
    const backend = async () => { allowed = false; return fixture("agents-list").response; };
    expect(await handlePerchMessage(request(), async () => allowed, backend)).toMatchObject(wireError("unauthorized"));
  });
  test.each([
    { ...request(), version: 2 }, request("daemon.stop"), request("shell.exec"),
  ])("unsupported operation/version has no backend effects", async (msg) => {
    const backend = vi.fn();
    expect(await handlePerchMessage(msg, authorized, backend)).toMatchObject(wireError("unsupported"));
    expect(backend).not.toHaveBeenCalled();
  });
  test.each([
    request("agents.list", { path: "/tmp" }), request("agents.events", { cursor: 0 }),
    request("agents.events", { epoch: "x", cursor: -1 }), request("agents.events", { limit: 129 }),
    request("agents.events", { wait_ms: 25001 }), request("agents.events", { command: "ls" }),
    request("agents.events", { limit: null }), request("agents.events", { wait_ms: null }),
    { ...request(), params: null }, { ...request(), id: "" },
  ])("invalid input has no backend effects", async (msg) => {
    const backend = vi.fn();
    expect(await handlePerchMessage(msg as PerchClientMessage, authorized, backend)).toMatchObject(wireError("invalid_argument"));
    expect(backend).not.toHaveBeenCalled();
  });
  test("offline, timeout and internal failures stay correlated", async () => {
    expect(await handlePerchMessage(request(), authorized, null)).toMatchObject({ ...wireError("offline"), id: "read-1" });
    for (const [message, code] of [["request timed out", "timeout"], ["socket closed", "offline"], ["unexpected", "internal"]]) {
      expect(await handlePerchMessage(request(), authorized, async () => { throw new Error(message); }))
        .toMatchObject({ ...wireError(code), id: "read-1" });
    }
  });
});
