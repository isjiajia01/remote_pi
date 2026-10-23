/**
 * Coalesces streamed text deltas into fewer wire frames.
 *
 * - The first delta after idle is sent immediately (no added latency).
 * - Later deltas inside `windowMs` are appended and flushed together
 *   (fixed window, armed once - not a debounce, so continuous streams still
 *   flush every window).
 * - A turn change or reaching `maxBytes` flushes right away.
 * - `flush()` MUST be called before any non-chunk frame so ordering holds.
 */
export class ChunkCoalescer {
  private pendingTurn: string | null = null;
  private pending = "";
  private timer: ReturnType<typeof setTimeout> | null = null;
  private lastSentAt = -Infinity;

  constructor(
    private readonly emit: (turnId: string, delta: string) => void,
    private readonly windowMs = 16,
    private readonly maxBytes = 8 * 1024,
    private readonly now: () => number = () => Date.now(),
  ) {}

  push(turnId: string, delta: string): void {
    if (delta === "") return;
    if (this.pendingTurn !== null && this.pendingTurn !== turnId) this.flush();
    if (this.pendingTurn === null && this.now() - this.lastSentAt >= this.windowMs) {
      // Idle -> leading edge: send now, then open a window for followers.
      this.lastSentAt = this.now();
      this.emit(turnId, delta);
      this.pendingTurn = turnId;
      this.armTimer();
      return;
    }
    this.pendingTurn = turnId;
    this.pending += delta;
    if (Buffer.byteLength(this.pending) >= this.maxBytes) {
      this.flush();
      return;
    }
    this.armTimer();
  }

  private armTimer(): void {
    if (this.timer) return;
    this.timer = setTimeout(() => {
      this.timer = null;
      this.flushPending();
      this.pendingTurn = null;
    }, this.windowMs);
    this.timer.unref?.();
  }

  private flushPending(): void {
    if (this.pending !== "" && this.pendingTurn !== null) {
      const turn = this.pendingTurn;
      const text = this.pending;
      this.pending = "";
      this.lastSentAt = this.now();
      this.emit(turn, text);
    }
  }

  /** Emit anything buffered now and close the window. */
  flush(): void {
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = null;
    }
    this.flushPending();
    this.pendingTurn = null;
  }

  /** Drop buffered text without emitting (e.g. all owners detached). */
  reset(): void {
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = null;
    }
    this.pending = "";
    this.pendingTurn = null;
  }
}
