import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { EventEmitter } from "node:events";
import { mkdtempSync, mkdirSync, readFileSync, realpathSync, renameSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { SessionControl, loadSessionControlConfig, type SessionChild, type SessionControlOptions } from "./session_control.js";
import type { RpcChildOptions } from "./rpc_child.js";
import type { PerchServerMessage } from "../protocol/perch.js";

const owner = Buffer.alloc(32, 1).toString("base64");
const other = Buffer.alloc(32, 2).toString("base64");
class FakeChild extends EventEmitter implements SessionChild {
  state: "starting" | "running" | "stopped" | "crashed" = "stopped";
  spawn() { this.state = "running"; }
  async stop() { this.state = "stopped"; this.emit("exit", { isCrash: false }); }
}
function data(message: PerchServerMessage): any {
  expect(message.type).toBe("perch_result");
  return message.type === "perch_result" && "data" in message.result ? message.result.data : undefined;
}
function error(message: PerchServerMessage): string | undefined {
  return message.type === "perch_error" ? message.error.code : undefined;
}
let tmp: string;
let options: SessionControlOptions;
let control: SessionControl;
let launches: RpcChildOptions[];
let children: FakeChild[];
const request = (method: string, params: Record<string, unknown>, id = crypto.randomUUID(), who = owner) =>
  control.handle(who, { type: "perch_request", version: 1, id, method, params });
const negotiate = (who = owner) => control.handle(who, { type: "perch_capabilities_get", id: "cap" });
const create = (id = crypto.randomUUID(), relative_path = "项目 空格") => request("sessions.create", { root_id: "life", relative_path }, id);
beforeEach(async () => {
  tmp = mkdtempSync(join(tmpdir(), "perch-sessions-"));
  mkdirSync(join(tmp, "Life-OS", "项目 空格"), { recursive: true });
  mkdirSync(join(tmp, "outside"));
  const configPath = join(tmp, "config.json");
  writeFileSync(configPath, JSON.stringify({ enabled: true, roots: [{ id: "life", name: "Life OS", path: join(tmp, "Life-OS") }],
    owners: { [owner]: { root_ids: ["life"] }, [other]: { root_ids: [] } } }));
  launches = []; children = [];
  options = { configPath, journalPath: join(tmp, "journal.json"), sessionsPath: join(tmp, "sessions"),
    extensionPath: "/test/extension.js", isPaired: async (o) => [owner, other].includes(o),
    createChild: (opts) => { launches.push(opts); const child = new FakeChild(); children.push(child); return child; } };
  control = new SessionControl(options);
  await negotiate();
});
afterEach(async () => { await control.close(); rmSync(tmp, { recursive: true, force: true }); });

describe("minimal independent session control", () => {
  test("zero children can negotiate, browse roots and list Unicode directories", async () => {
    expect(launches).toHaveLength(0);
    const cap = await negotiate();
    expect(cap).toMatchObject({ scope: "supervisor", methods: expect.arrayContaining(["sessions.create", "directories.list"]) });
    expect(data(await request("directories.roots", {}))).toEqual({ roots: [{ id: "life", name: "Life OS" }] });
    expect(data(await request("directories.list", { root_id: "life", relative_path: "" }))).toMatchObject({
      directories: [{ name: "项目 空格", relative_path: "项目 空格" }], next_offset: null,
    });
    expect(launches).toHaveLength(0);
  });
  test("same cwd creates distinct fresh sessions, storage and rooms", async () => {
    const first = data(await create());
    const second = data(await create());
    expect(first.state).toBe("starting");
    expect(first.session_id).not.toBe(second.session_id);
    expect(first.room_id).not.toBe(second.room_id);
    expect(first.room_id).toBe(`session-${first.session_id}`);
    expect(launches).toHaveLength(2);
    expect(launches[0]).toMatchObject({ freshSession: true, cwd: realpathSync(join(tmp, "Life-OS", "项目 空格")), env: { PERCH_FULL_FEATURES: "0", PERCH_SESSION_ID: first.session_id } });
    expect(launches[0]!.sessionDir).not.toBe(launches[1]!.sessionDir);
    expect(data(await request("sessions.get", { session_id: first.session_id })).state).toBe("running");
  });
  test("same request id deduplicates concurrent calls, reconnect and restart; conflicts rejected", async () => {
    const results = await Promise.all([create("same"), create("same")]);
    expect(data(results[0]!).session_id).toBe(data(results[1]!).session_id);
    expect(launches).toHaveLength(1);
    control.disconnect();
    expect(error(await create("same"))).toBe("unsupported");
    await negotiate();
    expect(data(await create("same")).session_id).toBe(data(results[0]!).session_id);
    expect(error(await create("same", ""))).toBe("conflict");
    await control.close();
    control = new SessionControl(options);
    await negotiate();
    expect(data(await create("same")).state).toBe("stopped");
    expect(launches).toHaveLength(1);
  });
  test("retry recovers the same result even if its directory was moved after creation", async () => {
    const first = data(await create("moved"));
    renameSync(join(tmp, "Life-OS", "项目 空格"), join(tmp, "Life-OS", "renamed"));
    expect(data(await create("moved")).session_id).toBe(first.session_id);
    expect(launches).toHaveLength(1);
  });
  test("uncertain launch survives service crash without automatic respawn", async () => {
    const first = data(await create("uncertain"));
    const replacement = new SessionControl(options);
    await replacement.handle(owner, { type: "perch_capabilities_get", id: "cap" });
    const reply = await replacement.handle(owner, { type: "perch_request", version: 1, id: "uncertain", method: "sessions.create", params: { root_id: "life", relative_path: "项目 空格" } });
    expect(data(reply)).toMatchObject({ session_id: first.session_id, state: "interrupted" });
    expect(launches).toHaveLength(1);
    await replacement.close();
  });
  test("rejects unpaired owners, absent grants and unnegotiated calls", async () => {
    expect(error(await negotiate("intruder"))).toBe("unauthorized");
    await negotiate(other);
    expect(data(await request("directories.roots", {}, "roots", other))).toEqual({ roots: [] });
    expect(error(await request("sessions.create", { root_id: "life", relative_path: "" }, "x", other))).toBe("forbidden");
    const session = data(await create());
    expect(error(await request("sessions.get", { session_id: session.session_id }, "get", other))).toBe("forbidden");
  });
  test("rejects traversal, absolute and symlink escapes for both browse/create", async () => {
    symlinkSync(join(tmp, "outside"), join(tmp, "Life-OS", "escape"));
    for (const relative_path of ["../outside", "/tmp", "a/../../outside", "a\\..\\outside", "C:/outside", "escape"]) {
      for (const method of ["directories.list", "sessions.create"]) {
        expect(["forbidden", "invalid_argument"]).toContain(error(await request(method, { root_id: "life", relative_path })));
      }
    }
    expect(data(await request("directories.list", { root_id: "life", relative_path: "" })).directories).toHaveLength(1);
    expect(launches).toHaveLength(0);
  });
  test("directory pages are bounded and cursors validated", async () => {
    for (let i = 0; i < 105; i++) mkdirSync(join(tmp, "Life-OS", `d${i.toString().padStart(3, "0")}`));
    const page = data(await request("directories.list", { root_id: "life", relative_path: "" }));
    expect(page.directories).toHaveLength(100);
    expect(page.next_offset).toBe(100);
    expect(data(await request("directories.list", { root_id: "life", relative_path: "", offset: 100 })).directories).toHaveLength(6);
    expect(error(await request("directories.list", { root_id: "life", relative_path: "", offset: -1 }))).toBe("invalid_argument");
  });
  test("records synchronous and asynchronous spawn failure without duplicate retry", async () => {
    options.createChild = () => { throw new Error("ENOENT"); };
    const first = data(await create("fail"));
    expect(first.state).toBe("failed");
    expect(data(await create("fail")).session_id).toBe(first.session_id);
    options.createChild = () => { const c = new FakeChild(); children.push(c); return c; };
    const second = data(await create("async-fail"));
    children[0]!.emit("exit", { isCrash: true });
    expect(data(await request("sessions.get", { session_id: second.session_id })).state).toBe("failed");
    expect(data(await create("async-fail")).state).toBe("failed");
  });
  test("stop is idempotent and revoked local grants are checked on replay", async () => {
    const first = data(await create("stop"));
    expect(data(await request("sessions.stop", { session_id: first.session_id })).state).toBe("stopped");
    expect(data(await request("sessions.stop", { session_id: first.session_id })).state).toBe("stopped");
    const config = JSON.parse(readFileSync(options.configPath, "utf8"));
    config.owners[owner].root_ids = [];
    writeFileSync(options.configPath, JSON.stringify(config));
    expect(error(await create("stop"))).toBe("forbidden");
  });
  test("invalid config and corrupt journal fail closed", () => {
    writeFileSync(options.configPath, JSON.stringify({ enabled: true, roots: [], owners: {} }));
    expect(loadSessionControlConfig(options.configPath)).toBeUndefined();
    writeFileSync(options.journalPath, JSON.stringify({ version: 1, entries: { bad: {} } }));
    expect(() => new SessionControl(options)).toThrow("Invalid session journal");
  });
});
