import type { PeerInfo } from "../session/broker.js";

export const PERCH_LIMITS = {
  retention: 512,
  max_events: 128,
  max_wait_ms: 25_000,
  max_subscribers: 8,
} as const;
export const PERCH_METHODS = ["agents.list", "agents.events"] as const;
export type PerchErrorCode = "unauthorized" | "forbidden" | "unsupported" |
  "invalid_argument" | "offline" | "timeout" | "internal";
export type PerchClientMessage =
  | { type: "perch_capabilities_get"; id: string }
  | { type: "perch_request"; id: string; version: number; method: string; params: Record<string, unknown> };
export type PerchEvent = {
  cursor: number;
  ts: number;
} & (
  | { type: "peer_joined" | "peer_left"; agent: PeerInfo }
  | { type: "routed"; id: string; re: string | null; from: string;
      to: string | string[]; delivered: string[]; ack_status: "received" | "denied" | "none";
      via: "uds" | "relay" }
);
export type PerchSnapshot = {
  scope: "local_broker"; epoch: string; revision: number; cursor: number; agents: PeerInfo[];
};
export type PerchEvents = {
  scope: "local_broker"; epoch: string; cursor: number; events: PerchEvent[]; resync_required: boolean;
};
export type PerchServerMessage =
  | { type: "perch_capabilities_result"; id: string; version: 1;
      methods: typeof PERCH_METHODS; scope: "local_broker";
      ack_semantics: "delivery_only"; limits: typeof PERCH_LIMITS }
  | { type: "perch_result"; id: string; version: 1; method: string; result: PerchSnapshot | PerchEvents }
  | { type: "perch_error"; id: string; version: 1; error: { code: PerchErrorCode; message: string } };

export function perchError(id: string, code: PerchErrorCode, message: string): PerchServerMessage {
  return { type: "perch_error", id, version: 1, error: { code, message } };
}

export function perchCapabilities(id: string): PerchServerMessage {
  return { type: "perch_capabilities_result", id, version: 1, methods: PERCH_METHODS,
    scope: "local_broker", ack_semantics: "delivery_only", limits: PERCH_LIMITS };
}

export type PerchRead =
  | { method: "agents.list" }
  | { method: "agents.events"; epoch?: string; cursor?: number; limit: number; wait_ms: number };

/** Validate at both the mobile boundary and the broker; only these read operations exist. */
export function validatePerchRequest(msg: PerchClientMessage): PerchRead | PerchServerMessage {
  if (msg.type !== "perch_request" || msg.version !== 1) {
    return perchError(msg.id, "unsupported", "Unsupported Perch version");
  }
  if (!PERCH_METHODS.includes(msg.method as typeof PERCH_METHODS[number])) {
    return perchError(msg.id, "unsupported", "Unsupported Perch method");
  }
  const p = msg.params;
  const invalid = () => perchError(msg.id, "invalid_argument", "Invalid method params");
  if (!p || typeof p !== "object" || Array.isArray(p)) return invalid();
  if (msg.method === "agents.list") {
    return Object.keys(p).length === 0 ? { method: "agents.list" } : invalid();
  }
  if (Object.keys(p).some((k) => !["epoch", "cursor", "limit", "wait_ms"].includes(k))) return invalid();
  if ((p.epoch === undefined) !== (p.cursor === undefined)) return invalid();
  if (p.epoch !== undefined && (typeof p.epoch !== "string" || !p.epoch || p.epoch.length > 128)) return invalid();
  if (p.cursor !== undefined && (!Number.isSafeInteger(p.cursor) || (p.cursor as number) < 0)) return invalid();
  const limit = p.limit === undefined ? PERCH_LIMITS.max_events : p.limit;
  const wait = p.wait_ms === undefined ? 0 : p.wait_ms;
  if (!Number.isInteger(limit) || (limit as number) < 1 || (limit as number) > PERCH_LIMITS.max_events ||
      !Number.isInteger(wait) || (wait as number) < 0 || (wait as number) > PERCH_LIMITS.max_wait_ms) return invalid();
  return { method: "agents.events", epoch: p.epoch as string | undefined,
    cursor: p.cursor as number | undefined, limit: limit as number, wait_ms: wait as number };
}

/** Authentication is injected from the existing relay channel + paired-Owner checks. */
export async function handlePerchMessage(
  msg: PerchClientMessage,
  authorized: () => Promise<boolean>,
  request: ((msg: PerchClientMessage, timeoutMs: number) => Promise<PerchServerMessage>) | null,
): Promise<PerchServerMessage> {
  const id = typeof msg.id === "string" ? msg.id : "";
  try {
    if (!await authorized()) return perchError(id, "unauthorized", "Sender is not a paired Owner");
    if (!id || id.length > 256) return perchError(id, "invalid_argument", "Invalid request id");
    if (msg.type === "perch_capabilities_get") return perchCapabilities(id);
    const read = validatePerchRequest(msg);
    if ("type" in read) return read;
    if (!request) return perchError(id, "offline", "Local broker unavailable");
    const result = await request(msg, (read.method === "agents.events" ? read.wait_ms : 0) + 2_000);
    // Revocation/disconnect during a long poll must not disclose its result.
    if (!await authorized()) return perchError(id, "unauthorized", "Sender is not a paired Owner");
    return result;
  } catch (error) {
    const detail = error instanceof Error ? error.message : "";
    return perchError(id, /timed out|timeout/i.test(detail) ? "timeout" :
      /not connected|closed|offline/i.test(detail) ? "offline" : "internal", "Perch read failed");
  }
}
