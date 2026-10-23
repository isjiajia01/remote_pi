import { afterEach, beforeEach, expect, test, vi } from "vitest";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { notificationSession, registerNotifications } from "./notifications.js";
import { boundedPreview, pushPayload, type PushEvent } from "./protocol/push.js";

beforeEach(() => vi.stubEnv("PI_SUBAGENT_CHILD", "0"));
afterEach(() => { vi.unstubAllEnvs(); vi.useRealTimers(); });
function harness(mode = "rpc", header: unknown = {}) {
  const handlers = new Map<string, Function>();
  const pi = { on: (name: string, fn: Function) => handlers.set(name, fn) } as unknown as ExtensionAPI;
  const ctx = { mode, sessionManager: { getHeader: () => header, getSessionId: () => "stable-session" } } as unknown as ExtensionContext;
  const sent: PushEvent[] = [];
  registerNotifications(pi, () => ({ machine_id: "a".repeat(44), room_id: "session-mobile" }), async event => { sent.push(event); });
  const emit = async (name: string, event: unknown = {}) => { await handlers.get(name)?.(event, ctx); };
  const text = (value: string, stopReason = "stop") => emit("message_end", { message: { role: "assistant", content: [{ type: "thinking", thinking: "secret" }, { type: "text", text: value }], stopReason } });
  return { emit, text, sent, ctx };
}
test("settled consumes final continuation once; independent short turns notify", async () => {
  const h = harness();
  await h.emit("agent_start"); await h.text("commentary"); await h.emit("agent_end");
  expect(h.sent).toEqual([]);
  await h.emit("agent_start"); await h.text("final"); await h.emit("agent_settled"); await h.emit("agent_settled");
  expect(h.sent).toHaveLength(1); expect(h.sent[0]).toMatchObject({ preview: "final", session_id: "stable-session", target: { room_id: "session-mobile" } });
  await h.emit("agent_start"); await h.text("next"); await h.emit("agent_settled");
  expect(h.sent).toHaveLength(2);
});
test("empty, error, aborted and replaced sessions never reuse commentary", async () => {
  const h = harness();
  for (const reason of ["stop", "error", "aborted"]) {
    await h.emit("agent_start"); await h.text("earlier"); await h.text("", reason); await h.emit("agent_settled");
    expect(h.sent.at(-1)).not.toHaveProperty("preview", "earlier");
    expect(JSON.stringify(pushPayload(h.sent.at(-1)!))).not.toContain("earlier");
  }
  await h.emit("agent_start"); await h.text("old"); await h.emit("session_start"); await h.emit("agent_settled");
  expect(h.sent).toHaveLength(3);
  await h.emit("agent_start"); await h.text("aborted text"); await h.emit("agent_settled", { aborted: true });
  expect(pushPayload(h.sent.at(-1)!)).toHaveProperty("aps.alert", "本次运行已结束，请打开查看");
});
test("main TUI and independent mobile RPC qualify; ancestry/print/read failure fail closed", () => {
  expect(notificationSession(harness("rpc").ctx)).toBe("stable-session");
  expect(notificationSession(harness("tui").ctx)).toBe("stable-session");
  for (const mode of ["print", "json"]) expect(notificationSession(harness(mode).ctx)).toBeUndefined();
  expect(notificationSession(harness("rpc", { parentSession: "parent" }).ctx)).toBeUndefined();
  expect(notificationSession(harness("rpc", null).ctx)).toBeUndefined();
  const h = harness(); h.ctx.sessionManager.getHeader = () => { throw Error(); };
  expect(notificationSession(h.ctx)).toBeUndefined();
  vi.stubEnv("PI_SUBAGENT_CHILD", "1");
  expect(notificationSession(harness().ctx)).toBeUndefined();
});
test("prompt debounce suppresses quick resolution and overlapping prompts; shutdown flushes captured notice", async () => {
  vi.useFakeTimers(); const h = harness();
  await h.emit("ui_prompt_start"); await h.emit("ui_prompt_end"); await vi.advanceTimersByTimeAsync(800); expect(h.sent).toEqual([]);
  await h.emit("ui_prompt_start"); await h.emit("ui_prompt_start"); await vi.advanceTimersByTimeAsync(800);
  expect(h.sent).toHaveLength(1); expect(pushPayload(h.sent[0])).toHaveProperty("aps.alert", "需要你操作，点开 Perch 查看");
  await h.emit("ui_prompt_end"); await h.emit("ui_prompt_end");
  await h.emit("agent_start"); await h.text("captured"); await h.emit("agent_settled"); await h.emit("session_shutdown");
  expect(h.sent.at(-1)).toHaveProperty("preview", "captured");
  expect(vi.getTimerCount()).toBe(0);
});
test("Unicode previews bounded; disabled preview and explicit payload exclude private blocks", () => {
  const preview = boundedPreview("你好👩🏽‍💻".repeat(1000));
  expect(Array.from(preview).length).toBeLessThanOrEqual(240); expect(Buffer.byteLength(preview)).toBeLessThanOrEqual(1024);
  const event: PushEvent = { kind: "session_finished", event_id: "e", session_id: "s", preview };
  expect(Buffer.byteLength(JSON.stringify(pushPayload(event)))).toBeLessThanOrEqual(4096);
  expect(pushPayload(event, false)).toHaveProperty("aps.alert", "本次回复已结束，点开查看");
  expect(() => pushPayload({ ...event, event_id: "x".repeat(4096) })).toThrow("exceeds limit");
});
