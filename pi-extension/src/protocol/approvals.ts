/** Versioned opt-in approval messages; identity always comes from the relay channel. */
export interface ApprovalRequest {
  type: "perch_tool_approval_request";
  id: string;
  version: 1;
  owner: string;
  session_id: string;
  tool_call_id: string;
  tool: string;
  args: Record<string, unknown>;
  args_digest: string;
  expires_at: number;
}
export interface ApprovalDecision {
  type: "perch_tool_approval_decision";
  id: string;
  version: 1;
  owner: string;
  session_id: string;
  tool_call_id: string;
  args_digest: string;
  decision: "allow" | "deny";
}
