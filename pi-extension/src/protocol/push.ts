/** Owner claims must match the authenticated paired relay sender. */
export type PushEnvironment = "sandbox" | "production";
export type PushClientMessage = {
  type: "perch_push_register" | "perch_push_unregister";
  id: string;
  version: 1;
  owner: string;
  token: string;
  environment: PushEnvironment;
};
export type PushResult = {
  type: "perch_push_result";
  id: string;
  version: 1;
  registered: boolean;
};
export type PushEvent =
  | { kind: "approval_request"; event_id: string; session_id: string; tool_call_id: string }
  | { kind: "session_finished"; event_id: string; session_id: string };

export function validPushToken(token: unknown): token is string {
  return typeof token === "string" && /^[a-fA-F0-9]{64,512}$/.test(token) && token.length % 2 === 0;
}
export function validPushEnvironment(value: unknown): value is PushEnvironment {
  return value === "sandbox" || value === "production";
}

/** Construct fields explicitly: even accidental extra properties never reach APNs. */
export function pushPayload(event: PushEvent): object {
  return { aps: { alert: "Perch has an update", sound: "default" },
    kind: event.kind, event_id: event.event_id, session_id: event.session_id,
    ...(event.kind === "approval_request" ? { tool_call_id: event.tool_call_id } : {}) };
}
