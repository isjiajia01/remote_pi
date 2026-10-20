import { validateSchedule } from "./cron_registry.js";
import type { ControlRequest } from "./control_protocol.js";

export const PERCH_CONTROL_ROOM = "perch-control";
export const PERCH_CONTROL_METHODS = [
  "daemon.list", "daemon.start", "daemon.stop", "daemon.restart",
  "cron.list", "cron.add", "cron.set_enabled", "cron.remove", "cron.run", "cron.log",
] as const;
export type PerchControlMethod = typeof PERCH_CONTROL_METHODS[number];
export const PERCH_CONTROL_LIMITS = { max_prompt_chars: 8192, max_log_entries: 100 } as const;
export type ControlOperation = { request: ControlRequest; mutation: boolean; daemonId?: string; jobId?: string };
const daemonId = (v: unknown): v is string => typeof v === "string" && /^[a-f0-9]{8}$/.test(v);
const jobId = (v: unknown): v is string => typeof v === "string" && /^j_[a-f0-9]{1,64}$/.test(v);
export { daemonId as validDaemonId };

/** Remote params are copied field by field; local IPC's shell/path-capable operations are never exposed. */
export function controlOperation(method: string, params: unknown): ControlOperation | undefined {
  if (!params || typeof params !== "object" || Array.isArray(params)) return;
  const p = params as Record<string, unknown>;
  const only = (...keys: string[]) => Object.keys(p).every((k) => keys.includes(k));
  switch (method) {
    case "daemon.list": return only() ? { request: { op: "list" }, mutation: false } : undefined;
    case "cron.list": return only() ? { request: { op: "cron_list" }, mutation: false } : undefined;
    case "daemon.start": case "daemon.stop": case "daemon.restart": {
      if (!only("id") || !daemonId(p.id)) return;
      return { request: { op: method.slice(7) as "start" | "stop" | "restart", id: p.id },
        mutation: true, daemonId: p.id };
    }
    case "cron.add": {
      if (!only("daemon_id", "schedule", "prompt", "tz", "skip_if_busy", "wake", "catchup") ||
          !daemonId(p.daemon_id) || typeof p.schedule !== "string" || p.schedule.length > 256 ||
          typeof p.prompt !== "string" || !p.prompt.trim() || p.prompt.length > PERCH_CONTROL_LIMITS.max_prompt_chars ||
          (p.tz !== undefined && (typeof p.tz !== "string" || p.tz.length > 128)) ||
          [p.skip_if_busy, p.wake, p.catchup].some((v) => v !== undefined && typeof v !== "boolean")) return;
      if (!validateSchedule(p.schedule, p.tz as string | undefined).ok) return;
      const request: Extract<ControlRequest, { op: "cron_add" }> = {
        op: "cron_add", daemon_id: p.daemon_id, schedule: p.schedule, prompt: p.prompt,
      };
      if (p.tz !== undefined) request.tz = p.tz as string;
      for (const key of ["skip_if_busy", "wake", "catchup"] as const) {
        if (p[key] !== undefined) request[key] = p[key] as boolean;
      }
      return { request, mutation: true, daemonId: p.daemon_id };
    }
    case "cron.set_enabled":
      if (!only("job_id", "enabled") || !jobId(p.job_id) || typeof p.enabled !== "boolean") return;
      return { request: { op: "cron_enable", job_id: p.job_id, enabled: p.enabled }, mutation: true, jobId: p.job_id };
    case "cron.remove": case "cron.run":
      if (!only("job_id") || !jobId(p.job_id)) return;
      return { request: { op: method === "cron.remove" ? "cron_remove" : "cron_run", job_id: p.job_id },
        mutation: true, jobId: p.job_id };
    case "cron.log":
      // A job is mandatory: global logs would disclose other daemons' prompts.
      if (!only("job_id", "tail") || !jobId(p.job_id) ||
          (p.tail !== undefined && (!Number.isInteger(p.tail) || (p.tail as number) < 1 ||
            (p.tail as number) > PERCH_CONTROL_LIMITS.max_log_entries))) return;
      return { request: { op: "cron_log", job_id: p.job_id, tail: (p.tail as number | undefined) ?? 100 },
        mutation: false, jobId: p.job_id };
    default: return;
  }
}
