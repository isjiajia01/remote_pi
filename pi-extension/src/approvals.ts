import { createHash, randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { ToolCallEvent, ToolCallEventResult } from "@earendil-works/pi-coding-agent";
import type { ApprovalDecision, ApprovalRequest } from "./protocol/approvals.js";

export interface ApprovalConfig { enabled: boolean; tools: string[]; timeout_ms: number }
const DEFAULT_TIMEOUT_MS = 60_000;

/** Absent is opt-out; an existing invalid policy must never silently disable protection. */
export function loadApprovalConfig(cwd: string): ApprovalConfig {
  let raw: string;
  try { raw = readFileSync(join(cwd, ".pi", "remote-pi", "perch-approvals.json"), "utf8"); }
  catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return { enabled: false, tools: [], timeout_ms: DEFAULT_TIMEOUT_MS };
    throw new Error("Cannot read tool approval policy");
  }
  const value = JSON.parse(raw) as Record<string, unknown>;
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      Object.keys(value).some((key) => !["enabled", "tools", "timeout_ms"].includes(key)) ||
      typeof value.enabled !== "boolean" || !Array.isArray(value.tools) ||
      value.tools.some((tool) => typeof tool !== "string" || !tool.trim() || tool.length > 128) ||
      (value.timeout_ms !== undefined && (!Number.isInteger(value.timeout_ms) ||
        (value.timeout_ms as number) < 1 || (value.timeout_ms as number) > 300_000))) {
    throw new Error("Invalid tool approval policy");
  }
  return { enabled: value.enabled, tools: value.tools as string[], timeout_ms: (value.timeout_ms as number | undefined) ?? DEFAULT_TIMEOUT_MS };
}

/** Canonical JSON: sorted object keys, array order preserved, no non-JSON values. */
export function argumentDigest(input: unknown): string {
  function canonical(value: unknown): string {
    if (value === null || typeof value === "string" || typeof value === "boolean") return JSON.stringify(value);
    if (typeof value === "number" && Number.isFinite(value)) return JSON.stringify(value);
    if (Array.isArray(value)) return `[${Array.from(value, canonical).join(",")}]`;
    if (value && typeof value === "object" && Object.getPrototypeOf(value) === Object.prototype) {
      return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical((value as Record<string, unknown>)[key])}`).join(",")}}`;
    }
    throw new Error("Tool arguments must be JSON");
  }
  return createHash("sha256").update(canonical(input)).digest("hex");
}

function freezeArguments(value: unknown): void {
  if (!value || typeof value !== "object") return;
  for (const child of Object.values(value)) freezeArguments(child);
  Object.freeze(value);
}

type Pending = {
  request: Omit<ApprovalRequest, "owner">;
  owners: Set<string>;
  allowedBy?: string;
  timer: ReturnType<typeof setTimeout>;
  resolve: (allow: boolean) => void;
  detachAbort?: () => void;
};

/** One process/session's ephemeral challenges. No legacy approve_tool can release a wait. */
export class ToolApprovals {
  private readonly pending = new Map<string, Pending>();
  private session = randomUUID();
  private cancellation = 0;
  constructor(private readonly transport: {
    owners: () => string[];
    authorized: (owner: string) => Promise<boolean>;
    send: (owner: string, request: ApprovalRequest) => void;
  }) {}

  cancelAll(): void {
    this.cancellation += 1;
    for (const entry of this.pending.values()) this.finish(entry, false);
  }

  resetSession(): void { this.cancelAll(); this.session = randomUUID(); }

  cancelOwner(owner: string): void {
    this.cancellation += 1;
    for (const entry of this.pending.values()) {
      if (entry.owners.has(owner)) this.finish(entry, false);
    }
  }

  private async authorizedBeforeExpiry(owner: string, expiresAt: number): Promise<boolean> {
    const remaining = expiresAt - Date.now();
    if (remaining <= 0) return false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      return await Promise.race([
        this.transport.authorized(owner),
        new Promise<boolean>((resolve) => { timer = setTimeout(() => resolve(false), remaining); }),
      ]);
    } finally { clearTimeout(timer); }
  }

  private finish(entry: Pending, allow: boolean): void {
    if (this.pending.get(entry.request.id) !== entry) return;
    this.pending.delete(entry.request.id);
    clearTimeout(entry.timer);
    entry.detachAbort?.();
    entry.resolve(allow);
  }

  async decide(owner: string, decision: ApprovalDecision): Promise<void> {
    const entry = this.pending.get(decision.id);
    if (!entry || !entry.owners.has(owner)) return;
    let authorized = false;
    try { authorized = await this.transport.authorized(owner); } catch { /* deny */ }
    if (this.pending.get(decision.id) !== entry) return;
    const r = entry.request;
    const allow = authorized && decision.type === "perch_tool_approval_decision" && decision.version === 1 &&
      decision.owner === owner && decision.session_id === r.session_id &&
      decision.tool_call_id === r.tool_call_id && decision.args_digest === r.args_digest &&
      Date.now() < r.expires_at && decision.decision === "allow";
    if (allow) entry.allowedBy = owner;
    this.finish(entry, allow);
  }

  async gate(event: ToolCallEvent, config: ApprovalConfig, signal?: AbortSignal): Promise<ToolCallEventResult | undefined> {
    if (!config.enabled || !config.tools.includes(event.toolName)) return;
    const deny = (): ToolCallEventResult => ({ block: true, reason: "Perch tool approval denied, expired, cancelled, or arguments changed" });
    if (signal?.aborted || this.pending.size >= 32) return deny();
    const input = event.input;
    const session = this.session;
    const cancellation = this.cancellation;
    let digest: string;
    try { digest = argumentDigest(input); } catch { return deny(); }
    let resolve!: (allow: boolean) => void;
    const wait = new Promise<boolean>((done) => { resolve = done; });
    const entry: Pending = {
      request: { type: "perch_tool_approval_request", id: randomUUID(), version: 1,
        session_id: session, tool_call_id: event.toolCallId, tool: event.toolName,
        args: JSON.parse(JSON.stringify(input)) as Record<string, unknown>, args_digest: digest,
        expires_at: Date.now() + config.timeout_ms },
      owners: new Set(), resolve,
      timer: setTimeout(() => this.finish(entry, false), config.timeout_ms),
    };
    this.pending.set(entry.request.id, entry);
    if (signal) {
      const abort = () => this.finish(entry, false);
      signal.addEventListener("abort", abort, { once: true });
      entry.detachAbort = () => signal.removeEventListener("abort", abort);
    }
    // Publish only to currently authenticated, still-paired Owners. The timer also
    // covers slow pairing reads, and cancellation wins over in-flight publication.
    void (async () => {
      try {
        for (const owner of this.transport.owners()) {
          if (!await this.transport.authorized(owner)) continue;
          if (this.pending.get(entry.request.id) !== entry) return;
          entry.owners.add(owner);
          this.transport.send(owner, { ...entry.request, owner });
        }
        if (entry.owners.size === 0) this.finish(entry, false);
      } catch { this.finish(entry, false); }
    })();
    if (!await wait || !entry.allowedBy || session !== this.session || Date.now() >= entry.request.expires_at) return deny();
    try {
      if (!await this.authorizedBeforeExpiry(entry.allowedBy, entry.request.expires_at) || signal?.aborted ||
          session !== this.session || cancellation !== this.cancellation ||
          Date.now() >= entry.request.expires_at || event.input !== input ||
          event.toolName !== entry.request.tool || event.toolCallId !== entry.request.tool_call_id ||
          argumentDigest(input) !== digest) return deny();
      // SDK passes this same validated argument object to execute after ALL handlers.
      // Freeze it recursively: a later handler cannot change the approved execution.
      freezeArguments(input);
      Object.freeze(event);
      if (argumentDigest(input) !== digest) return deny();
      return undefined;
    } catch { return deny(); }
  }
}
