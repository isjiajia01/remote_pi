import { randomUUID } from "node:crypto";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { boundedPreview, type PushEvent, type PushTarget } from "./protocol/push.js";

export function notificationSession(ctx: ExtensionContext): string | undefined {
  try {
    if (process.env.PI_SUBAGENT_CHILD === "1" || !["tui", "rpc"].includes(ctx.mode)) return;
    const header = ctx.sessionManager.getHeader();
    if (!header || header.parentSession) return;
    return ctx.sessionManager.getSessionId() || undefined;
  } catch { return; } // Unreadable ancestry never authorizes a notification.
}

/** One candidate per stable session; no transcript, reasoning or tool arguments retained. */
export function registerNotifications(pi: ExtensionAPI, target: () => PushTarget | undefined,
  send: (event: PushEvent) => Promise<unknown>, promptDelayMs = 750): void {
  const runs = new Map<string, { id: string; preview?: string; failed: boolean }>();
  const prompts = new Map<string, { count: number; timer?: ReturnType<typeof setTimeout> }>();
  const pending = new Set<Promise<unknown>>();
  const dispatch = (event: PushEvent) => {
    const destination = target();
    const captured = { ...event, target: destination };
    if (!destination && captured.kind === "session_finished") delete captured.preview;
    const job = Promise.resolve().then(() => send(captured)).catch(() => {});
    pending.add(job);
    void job.finally(() => pending.delete(job));
  };
  const clear = () => {
    runs.clear();
    for (const prompt of prompts.values()) clearTimeout(prompt.timer);
    prompts.clear();
  };
  pi.on("session_start", clear);
  pi.on("agent_start", (_event, ctx) => {
    const id = notificationSession(ctx);
    if (id) runs.set(id, { id: randomUUID(), failed: false });
  });
  pi.on("message_end", (event, ctx) => {
    const id = notificationSession(ctx);
    const run = id ? runs.get(id) : undefined;
    const message = event.message;
    if (!run || message.role !== "assistant") return;
    run.failed = message.stopReason === "error" || message.stopReason === "aborted";
    let text = "";
    for (const block of message.content) {
      if (block.type !== "text") continue;
      text = boundedPreview(text + block.text.slice(0, 2048));
      if (Array.from(text).length >= 240) break;
    }
    run.preview = text.trim() || undefined;
  });
  pi.on("agent_settled", (event, ctx) => {
    const id = notificationSession(ctx);
    const run = id ? runs.get(id) : undefined;
    if (!id || !run) return;
    runs.delete(id); // Consume before any asynchronous work.
    dispatch({ kind: "session_finished", event_id: run.id, session_id: id,
      ...(run.failed || event.aborted ? { failed: true } : { preview: run.preview }) });
  });
  pi.on("ui_prompt_start", (_event, ctx) => {
    const id = notificationSession(ctx);
    if (!id) return;
    const existing = prompts.get(id);
    if (existing) { existing.count++; return; }
    const prompt = { count: 1, timer: setTimeout(() => {
      dispatch({ kind: "ui_prompt", event_id: randomUUID(), session_id: id });
    }, promptDelayMs) };
    prompts.set(id, prompt);
  });
  pi.on("ui_prompt_end", (_event, ctx) => {
    const id = notificationSession(ctx);
    const prompt = id ? prompts.get(id) : undefined;
    if (id && prompt && --prompt.count <= 0) { clearTimeout(prompt.timer); prompts.delete(id); }
  });
  pi.on("session_shutdown", async () => {
    clear();
    let timer: ReturnType<typeof setTimeout> | undefined;
    await Promise.race([Promise.allSettled([...pending]), new Promise<void>((resolve) => { timer = setTimeout(resolve, 1500); })]);
    clearTimeout(timer);
  });
}
