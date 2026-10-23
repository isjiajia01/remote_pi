import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { ChunkCoalescer } from "./chunk_coalescer.js";

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

function make(window = 16, max = 8192) {
  const frames: { turn: string; delta: string }[] = [];
  const c = new ChunkCoalescer((turn, delta) => frames.push({ turn, delta }), window, max, () => Date.now());
  return { c, frames };
}

test("first delta is immediate; followers coalesce into one frame per window", () => {
  const { c, frames } = make();
  c.push("t", "a");
  expect(frames).toEqual([{ turn: "t", delta: "a" }]);
  c.push("t", "b");
  c.push("t", "c");
  expect(frames).toHaveLength(1);
  vi.advanceTimersByTime(16);
  expect(frames[1]).toEqual({ turn: "t", delta: "bc" });
});

test("continuous stream still flushes every window (no starvation)", () => {
  const { c, frames } = make();
  for (let i = 0; i < 200; i++) {
    c.push("t", `x${i} `);
    vi.advanceTimersByTime(1);
  }
  vi.advanceTimersByTime(20);
  const text = frames.map((f) => f.delta).join("");
  expect(text).toBe(Array.from({ length: 200 }, (_, i) => `x${i} `).join(""));
  expect(frames.length).toBeLessThan(40);
  expect(frames.length).toBeGreaterThan(8);
  console.log(`BENCH ext chunks=200 @1ms frames=${frames.length}`);
});

test("flush() before another frame preserves order; turn change flushes", () => {
  const { c, frames } = make();
  c.push("t1", "a");
  c.push("t1", "b");
  c.flush();
  expect(frames.map((f) => f.delta)).toEqual(["a", "b"]);
  c.push("t1", "c");
  c.push("t1", "d");
  c.push("t2", "e");
  vi.advanceTimersByTime(16);
  // c+d were coalesced; the turn change flushed them BEFORE t2's text.
  expect(frames.map((f) => `${f.turn}:${f.delta}`)).toEqual(["t1:a", "t1:b", "t1:cd", "t2:e"]);
});

test("size cap flushes immediately; reset drops pending; idle gap restores leading edge", () => {
  const { c, frames } = make(16, 10);
  c.push("t", "a");
  c.push("t", "0123456789ABC");
  expect(frames.at(-1)!.delta).toBe("0123456789ABC");
  c.push("t", "pending");
  c.reset();
  vi.advanceTimersByTime(50);
  expect(frames.some((f) => f.delta === "pending")).toBe(false);
  c.push("t", "again");
  expect(frames.at(-1)!.delta).toBe("again");
});
