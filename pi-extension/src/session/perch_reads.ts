import { randomUUID } from "node:crypto";
import {
  PERCH_LIMITS, perchError, validatePerchRequest,
  type PerchClientMessage, type PerchEvent, type PerchEvents, type PerchServerMessage,
} from "../protocol/perch.js";
import type { PeerInfo } from "./broker.js";

type EventInput = PerchEvent extends infer E ? E extends PerchEvent ? Omit<E, "cursor" | "ts"> : never : never;

/** In-memory broker lifetime: failover/restart gets a new epoch and requires a snapshot. */
export class PerchBrokerReads {
  readonly epoch = randomUUID();
  private cursor = 0;
  private revision = 0;
  private readonly events: PerchEvent[] = [];
  private readonly subscribers = new Set<() => void>();
  private closed = false;

  constructor(private readonly inventory: () => PeerInfo[]) {}

  record(event: EventInput): void {
    if (this.closed) return;
    if (event.type !== "routed") this.revision++;
    this.events.push({ ...event, ts: Date.now(), cursor: ++this.cursor } as PerchEvent);
    if (this.events.length > PERCH_LIMITS.retention) this.events.shift();
    for (const wake of [...this.subscribers]) wake();
  }

  close(): void {
    this.closed = true;
    for (const wake of [...this.subscribers]) wake();
  }

  async read(msg: PerchClientMessage, signal?: AbortSignal): Promise<PerchServerMessage> {
    const read = validatePerchRequest(msg);
    if ("type" in read) return read;
    const offline = () => perchError(msg.id, "offline", "Local broker unavailable");
    if (this.closed || signal?.aborted) return offline();
    if (read.method === "agents.list") {
      return { type: "perch_result", id: msg.id, version: 1, method: read.method,
        result: { scope: "local_broker", epoch: this.epoch, revision: this.revision,
          cursor: this.cursor, agents: this.inventory() } };
    }
    const replay = (): PerchEvents => {
      const earliest = this.events[0]?.cursor ?? this.cursor + 1;
      const gap = read.epoch !== this.epoch || read.cursor === undefined ||
        read.cursor < earliest - 1 || read.cursor > this.cursor;
      const events = gap ? [] : this.events.filter((e) => e.cursor > read.cursor!).slice(0, read.limit);
      return { scope: "local_broker", epoch: this.epoch,
        cursor: events.at(-1)?.cursor ?? (gap ? this.cursor : read.cursor!),
        events, resync_required: gap };
    };
    const result = replay();
    if (!result.resync_required && result.events.length === 0 && read.wait_ms > 0) {
      if (this.subscribers.size >= PERCH_LIMITS.max_subscribers) {
        return perchError(msg.id, "forbidden", "Broker subscriber limit reached");
      }
      await new Promise<void>((resolve) => {
        const wake = () => {
          clearTimeout(timer);
          this.subscribers.delete(wake);
          signal?.removeEventListener("abort", wake);
          resolve();
        };
        const timer = setTimeout(wake, read.wait_ms);
        this.subscribers.add(wake);
        signal?.addEventListener("abort", wake, { once: true });
      });
    }
    if (this.closed || signal?.aborted) return offline();
    return { type: "perch_result", id: msg.id, version: 1, method: read.method, result: replay() };
  }
}
