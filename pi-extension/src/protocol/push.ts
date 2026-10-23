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
export type PushTarget = { machine_id: string; room_id: string };
export type PushEvent = { event_id: string; session_id: string; target?: PushTarget } & (
  | { kind: "approval_request"; tool_call_id: string }
  | { kind: "session_finished"; preview?: string; failed?: boolean }
  | { kind: "ui_prompt" }
);
export function validPushToken(token: unknown): token is string {
  return typeof token === "string" && /^[a-fA-F0-9]{64,512}$/.test(token) && token.length % 2 === 0;
}
export function validPushEnvironment(value: unknown): value is PushEnvironment {
  return value === "sandbox" || value === "production";
}
export function boundedPreview(text: string): string {
  let result = "", bytes = 0, count = 0;
  for (const point of text) {
    const size = Buffer.byteLength(point, "utf8");
    if (++count > 240 || bytes + size > 1024) break;
    result += point; bytes += size;
  }
  return result;
}
/** Construct fields explicitly: even accidental extra properties never reach APNs. */
export function pushPayload(event: PushEvent, includePreview = true): object {
  const preview = event.kind === "session_finished" && !event.failed && includePreview && event.preview
    ? boundedPreview(event.preview).trim() : "";
  const alert = event.kind === "session_finished"
    ? event.failed ? "本次运行已结束，请打开查看" : preview || "本次回复已结束，点开查看"
    : "需要你操作，点开 Perch 查看";
  const target = event.target;
  const payload = { aps: { alert, sound: "default" }, kind: event.kind, event_id: event.event_id, session_id: event.session_id,
    ...(event.kind === "approval_request" ? { tool_call_id: event.tool_call_id } : {}),
    ...(target && /^[A-Za-z0-9+/_=-]{43,88}$/.test(target.machine_id) && target.room_id.length > 0 && target.room_id.length <= 256 && target.room_id !== "perch-control"
      ? { machine_id: target.machine_id, room_id: target.room_id } : {}) };
  if (Buffer.byteLength(JSON.stringify(payload), "utf8") > 4096) throw new Error("APNs payload exceeds limit");
  return payload;
}
