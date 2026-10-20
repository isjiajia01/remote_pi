import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, test, vi } from "vitest";
import { createExtensionRuntime, ExtensionRunner, SessionManager,
  type Extension, type ToolCallEvent, type ToolCallEventResult } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { argumentDigest, loadApprovalConfig, ToolApprovals, type ApprovalConfig } from "./approvals.js";
import type { ApprovalDecision, ApprovalRequest } from "./protocol/approvals.js";
import { decodeServer, encodeClient } from "./protocol/codec.js";

// Resolve the SDK's installed agent-core, without adding a direct dependency.
const agentCoreUrl = new URL("../../pi-agent-core/dist/index.js", import.meta.resolve("@earendil-works/pi-coding-agent"));
const { runAgentLoop } = await import(agentCoreUrl.href);
const config: ApprovalConfig = { enabled: true, tools: ["danger"], timeout_ms: 1000 };
const owner = "paired-owner";
function event(id = "call-1"): ToolCallEvent {
  return { type: "tool_call", toolName: "danger", toolCallId: id, input: { nested: { value: 1 } } };
}
function decision(r: ApprovalRequest, patch: Partial<ApprovalDecision> = {}): ApprovalDecision {
  return { type: "perch_tool_approval_decision", id: r.id, version: 1, owner: r.owner,
    session_id: r.session_id, tool_call_id: r.tool_call_id, args_digest: r.args_digest, decision: "allow", ...patch };
}
function harness() {
  const requests: ApprovalRequest[] = [];
  const paired = new Set([owner, "second-owner"]);
  const gate = new ToolApprovals({ owners: () => [owner], authorized: async (key) => paired.has(key),
    send: (_key, request) => requests.push(request) });
  return { gate, requests, paired };
}
async function published(h: ReturnType<typeof harness>, count = 1) {
  await vi.waitFor(() => expect(h.requests).toHaveLength(count), { interval: 1 });
  return h.requests[count - 1]!;
}
function runner(hook: (event: ToolCallEvent) => Promise<ToolCallEventResult | undefined>, later?: (event: ToolCallEvent) => void) {
  const extension = (handler: unknown): Extension => ({ path: "test-only", resolvedPath: "test-only",
    handlers: new Map([["tool_call", [handler]]]), tools: new Map(), commands: new Map(),
    shortcuts: new Map(), flags: new Map(), messageRenderers: new Map() }) as Extension;
  return new ExtensionRunner([extension(hook), ...(later ? [extension(later)] : [])],
    createExtensionRuntime(), "/isolated", SessionManager.inMemory(), {} as never);
}

// Real agent-core execution loop + real SDK handler runner; the provider stream
// is an in-memory assistant response and no shell, relay, or real tool is used.
async function execute(r: ExtensionRunner, count: () => void, id = "call-1", nested?: () => Promise<unknown>) {
  const message = { role: "assistant", content: [{ type: "toolCall", id, name: "danger", arguments: { nested: { value: 1 } } }],
    stopReason: "toolUse", timestamp: 1, api: "test", provider: "test", model: "test", usage: {} };
  return runAgentLoop([{ role: "user", content: "test", timestamp: 1 }],
    { systemPrompt: "", messages: [], tools: [{ name: "danger", description: "counter",
      parameters: Type.Object({ nested: Type.Object({ value: Type.Number() }) }),
      execute: async () => { count(); await nested?.(); return { content: [{ type: "text", text: "ok" }], details: {} }; } }] },
    { model: { provider: "test" }, convertToLlm: (messages: unknown[]) => messages, shouldStopAfterTurn: async () => true,
      beforeToolCall: async ({ toolCall, args }: { toolCall: { id: string; name: string }; args: Record<string, unknown> }) =>
        r.emitToolCall({ type: "tool_call", toolName: toolCall.name, toolCallId: toolCall.id, input: args }) },
    () => {}, undefined, () => ({ async *[Symbol.asyncIterator]() { yield { type: "done" }; }, result: async () => message }));
}

afterEach(() => vi.useRealTimers());
describe("local approval policy", () => {
  test("missing defaults OFF; explicit tool names and timeout; malformed policies fail closed", () => {
    const cwd = mkdtempSync(join(tmpdir(), "perch-approval-"));
    try {
      expect(loadApprovalConfig(cwd).enabled).toBe(false);
      mkdirSync(join(cwd, ".pi", "remote-pi"), { recursive: true });
      const path = join(cwd, ".pi", "remote-pi", "perch-approvals.json");
      writeFileSync(path, JSON.stringify({ enabled: true, tools: ["danger"] }));
      expect(loadApprovalConfig(cwd)).toEqual({ enabled: true, tools: ["danger"], timeout_ms: 60_000 });
      for (const invalid of ["{", "null", '{"enabled":true,"tools":"danger"}', '{"enabled":true,"tools":[],"timeout_ms":0}',
        '{"enabled":true,"tools":[],"extra":true}']) {
        writeFileSync(path, invalid);
        expect(() => loadApprovalConfig(cwd)).toThrow();
      }
    } finally { rmSync(cwd, { recursive: true, force: true }); }
  });
  test("digest is canonical and rejects non-JSON arguments", () => {
    expect(argumentDigest({ b: 2, a: [1] })).toBe(argumentDigest({ a: [1], b: 2 }));
    expect(argumentDigest({ a: [1, 2] })).not.toBe(argumentDigest({ a: [2, 1] }));
    expect(() => argumentDigest({ a: undefined })).toThrow();
    expect(() => argumentDigest(new Array(1))).toThrow();
  });
});

describe("server tool approvals", () => {
  test("OFF or unlisted tools execute without a request", async () => {
    const h = harness();
    for (const policy of [{ ...config, enabled: false }, { ...config, tools: ["other"] }]) {
      let count = 0;
      await execute(runner((e) => h.gate.gate(e, policy)), () => count++);
      expect(count).toBe(1);
    }
    expect(h.requests).toEqual([]);
  });
  test("real SDK/agent-core execution counter stays zero until valid allow", async () => {
    const h = harness(); let count = 0;
    const run = execute(runner((e) => h.gate.gate(e, config)), () => count++);
    const request = await published(h);
    expect(count).toBe(0);
    await h.gate.decide(owner, decision(request));
    await run;
    expect(count).toBe(1);
    await h.gate.decide(owner, decision(request));
    expect(count).toBe(1);
  });
  test("nested real agent-core calls each wait for their own single-use approval", async () => {
    const h = harness(); let parent = 0; let child = 0;
    const r = runner((e) => h.gate.gate(e, config));
    const run = execute(r, () => parent++, "parent", () => execute(r, () => child++, "child"));
    const first = await published(h);
    expect([parent, child]).toEqual([0, 0]);
    await h.gate.decide(owner, decision(first));
    const second = await published(h, 2);
    expect([parent, child]).toEqual([1, 0]);
    await h.gate.decide(owner, decision(first));
    expect(child).toBe(0);
    await h.gate.decide(owner, decision(second));
    await run;
    expect([parent, child]).toEqual([1, 1]);
  });
  test.each([
    ["wrong digest", { args_digest: "wrong" }], ["wrong session", { session_id: "wrong" }],
    ["wrong call", { tool_call_id: "wrong" }], ["wrong Owner claim", { owner: "second-owner" }],
    ["wrong version", { version: 2 }], ["explicit deny", { decision: "deny" }],
    ["malformed choice", { decision: "yes" }],
  ])("%s consumes the challenge and execution stays zero", async (_name, patch) => {
    const h = harness(); let count = 0;
    const run = execute(runner((e) => h.gate.gate(e, config)), () => count++);
    const request = await published(h);
    await h.gate.decide(owner, decision(request, patch as Partial<ApprovalDecision>));
    await h.gate.decide(owner, decision(request));
    await run;
    expect(count).toBe(0);
  });
  test("another paired Owner cannot decide a challenge addressed to someone else", async () => {
    const h = harness(); let count = 0;
    const run = execute(runner((e) => h.gate.gate(e, config)), () => count++);
    const request = await published(h);
    await h.gate.decide("second-owner", decision(request));
    expect(count).toBe(0);
    await h.gate.decide(owner, decision(request));
    await run;
    expect(count).toBe(1);
  });
  test("revoked Owner decision denies, even if allow is replayed", async () => {
    const h = harness(); let count = 0;
    const run = execute(runner((e) => h.gate.gate(e, config)), () => count++);
    const request = await published(h);
    h.paired.delete(owner);
    await h.gate.decide(owner, decision(request));
    h.paired.add(owner);
    await h.gate.decide(owner, decision(request));
    await run;
    expect(count).toBe(0);
  });
  test("expiry defaults to deny and late/replayed allow cannot execute", async () => {
    const h = harness(); let count = 0;
    const run = execute(runner((e) => h.gate.gate(e, { ...config, timeout_ms: 30 })), () => count++);
    const request = await published(h);
    await run;
    await h.gate.decide(owner, decision(request));
    expect(count).toBe(0);
  });
  test.each(["cancelAll", "resetSession", "cancelOwner"] as const)("%s cancels before release", async (method) => {
    const h = harness(); let count = 0;
    const run = execute(runner((e) => h.gate.gate(e, config)), () => count++);
    const request = await published(h);
    h.gate[method](owner);
    await h.gate.decide(owner, decision(request));
    await run;
    expect(count).toBe(0);
  });
  test("argument mutation during approval is detected before release", async () => {
    const h = harness(); const e = event();
    const pending = h.gate.gate(e, config);
    const request = await published(h);
    (e.input.nested as { value: number }).value = 2;
    await h.gate.decide(owner, decision(request));
    expect(await pending).toHaveProperty("block", true);
  });
  test.each(["nested input", "replace input"])("later handler mutating %s fails closed in real SDK runner", async (mutation) => {
    const h = harness(); let count = 0;
    const r = runner((e) => h.gate.gate(e, config), (e) => {
      if (mutation === "nested input") (e.input.nested as { value: number }).value = 2;
      else e.input = { nested: { value: 2 } };
    });
    const run = execute(r, () => count++);
    const request = await published(h);
    await h.gate.decide(owner, decision(request));
    const results = await run;
    expect(count).toBe(0);
    expect(results.some((m: { role: string; isError?: boolean }) => m.role === "toolResult" && m.isError)).toBe(true);
  });
  test("revocation/cancellation racing final authorization still denies", async () => {
    const h = harness(); const e = event();
    const run = h.gate.gate(e, config);
    const request = await published(h);
    const allow = h.gate.decide(owner, decision(request));
    await allow;
    h.gate.cancelAll();
    expect(await run).toHaveProperty("block", true);
  });
  test("every connected paired Owner receives a bound request; first decision wins", async () => {
    const requests: ApprovalRequest[] = [];
    const gate = new ToolApprovals({ owners: () => [owner, "second-owner"], authorized: async () => true,
      send: (_owner, request) => requests.push(request) });
    const pending = gate.gate(event(), config);
    await vi.waitFor(() => expect(requests).toHaveLength(2), { interval: 1 });
    expect(requests[0]!.id).toBe(requests[1]!.id);
    expect(requests.map((r) => r.owner)).toEqual([owner, "second-owner"]);
    await gate.decide("second-owner", decision(requests[1]!));
    await gate.decide(owner, decision(requests[0]!, { decision: "deny" }));
    expect(await pending).toBeUndefined();
  });
  test("expired by wall clock denies even before timeout callback runs", async () => {
    const h = harness(); let count = 0;
    const run = execute(runner((e) => h.gate.gate(e, config)), () => count++);
    const request = await published(h);
    const clock = vi.spyOn(Date, "now").mockReturnValue(request.expires_at);
    try {
      await h.gate.decide(owner, decision(request));
      await run;
      expect(count).toBe(0);
    } finally { clock.mockRestore(); }
  });
  test("final pairing lookup cannot extend execution past the approval deadline", async () => {
    const requests: ApprovalRequest[] = [];
    let checks = 0;
    const gate = new ToolApprovals({ owners: () => [owner],
      authorized: () => ++checks < 3 ? Promise.resolve(true) : new Promise(() => {}),
      send: (_owner, request) => requests.push(request) });
    const pending = gate.gate(event(), { ...config, timeout_ms: 30 });
    await vi.waitFor(() => expect(requests).toHaveLength(1), { interval: 1 });
    await gate.decide(owner, decision(requests[0]!));
    expect(await pending).toHaveProperty("block", true);
  });
  test("SDK abort signal cancels a wait and denies a late allow", async () => {
    const h = harness(); const controller = new AbortController();
    const pending = h.gate.gate(event(), config, controller.signal);
    const request = await published(h);
    controller.abort();
    await h.gate.decide(owner, decision(request));
    expect(await pending).toHaveProperty("block", true);
    expect(await h.gate.gate(event(), config, controller.signal)).toHaveProperty("block", true);
  });
  test("no paired recipients denies immediately without emitting arguments", async () => {
    const h = harness(); h.paired.clear();
    expect(await h.gate.gate(event(), config)).toHaveProperty("block", true);
    expect(h.requests).toEqual([]);
  });
});

describe("Perch approval golden wire fixture", () => {
  test("request/decision codecs and canonical argument digest", () => {
    const f = JSON.parse(readFileSync(new URL("../../.orchestration/contracts/perch-v1/tool-approval.json", import.meta.url), "utf8"));
    expect(decodeServer(JSON.stringify(f.request))).toEqual(f.request);
    expect(JSON.parse(encodeClient(f.decision))).toEqual(f.decision);
    expect(argumentDigest(f.request.args)).toBe(f.request.args_digest);
  });
});
