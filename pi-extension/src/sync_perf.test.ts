import { expect, test } from "vitest";
import {
  _routeClientMessageFrom,
  _setMessageBufferForTest,
  _setSessionStartedAtForTest,
  _mapAgentMessagesToEvents,
} from "./index.js";

function fixture(n: number): unknown[] {
  const out: unknown[] = [];
  for (let i = 0; i < n; i++) {
    out.push({ role: "user", content: `question ${i}`, timestamp: i * 3 });
    out.push({
      role: "assistant",
      timestamp: i * 3 + 1,
      content: [
        { type: "text", text: `answer ${i} ` + "x".repeat(200) },
        { type: "toolCall", id: `t${i}`, name: "bash", arguments: { cmd: "ls" } },
      ],
    });
    out.push({ role: "toolResult", toolCallId: `t${i}`, content: "ok ".repeat(50), timestamp: i * 3 + 2 });
  }
  return out;
}

test("BENCH session_sync repeated on large history", () => {
  const msgs = fixture(3500); // 10 500 SDK messages
  _setMessageBufferForTest(msgs);
  _setSessionStartedAtForTest(1);
  const sent: { type: string; events?: unknown[]; truncated?: boolean }[] = [];
  const sender = { send: (m: { type: string }) => sent.push(m as never) };
  const t0 = performance.now();
  const rounds = 50;
  for (let i = 0; i < rounds; i++) {
    _routeClientMessageFrom(sender as never, { type: "session_sync", id: `s${i}`, limit: 30 } as never, {} as never);
  }
  const total = performance.now() - t0;
  const hist = sent.filter((m) => m.type === "session_history");
  console.log(`BENCH sync rounds=${rounds} messages=${msgs.length} totalMs=${total.toFixed(1)} perSyncMs=${(total / rounds).toFixed(2)}`);
  expect(hist).toHaveLength(rounds);
  expect(hist[0]!.events).toHaveLength(30);
  // Output must equal a fresh full mapping's tail (correctness invariant).
  const full = _mapAgentMessagesToEvents(msgs as never);
  expect(hist[rounds - 1]!.events).toEqual(full.slice(-30));
  expect(hist[0]!.truncated).toBe(true);
});

test("session_sync stays correct after appends", () => {
  const msgs = fixture(10);
  _setMessageBufferForTest(msgs);
  _setSessionStartedAtForTest(1);
  const sent: { type: string; events?: unknown[] }[] = [];
  const sender = { send: (m: { type: string }) => sent.push(m as never) };
  const sync = (id: string) =>
    _routeClientMessageFrom(sender as never, { type: "session_sync", id, limit: 30 } as never, {} as never);
  sync("a");
  // Append through the same array the module holds (live path uses push).
  (_setMessageBufferForTest as unknown as (m: unknown[]) => void)(msgs);
  msgs.push({ role: "user", content: "late", timestamp: 999 });
  msgs.push({ role: "assistant", timestamp: 1000, content: [{ type: "text", text: "reply" }] });
  sync("b");
  const hist = sent.filter((m) => m.type === "session_history");
  const full = _mapAgentMessagesToEvents(msgs as never);
  expect(hist[1]!.events).toEqual(full.slice(-30));
});
