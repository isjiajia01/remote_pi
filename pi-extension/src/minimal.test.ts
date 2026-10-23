import { afterEach, expect, test, vi } from "vitest";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import extension, { _routeClientMessageFrom, _deliverMeshMessageToAgentForTest } from "./index.js";
import { extraCommand, fullFeatures } from "./features.js";

afterEach(() => vi.unstubAllEnvs());
test("minimal registers pairing and chat lifecycle without management or messaging", () => {
  vi.stubEnv("PERCH_FULL_FEATURES", "0");
  const commands: string[] = [], hooks: string[] = [], tools: string[] = [];
  const pi = {
    on: (name: string) => hooks.push(name),
    registerCommand: (name: string) => commands.push(name),
    registerTool: (tool: { name: string }) => tools.push(tool.name),
    registerMessageRenderer: () => {},
    registerFlag: () => {},
    events: undefined,
    sendMessage: vi.fn(),
  } as unknown as ExtensionAPI;
  extension(pi);
  expect(fullFeatures()).toBe(false);
  expect(commands).toContain("remote-pi pair");
  expect(commands).toHaveLength(11);
  expect(commands).not.toContain("remote-pi push-test");
  expect(hooks).toContain("agent_settled");
  expect(commands.some(c => extraCommand(c.replace(/^remote-pi ?/, "")))).toBe(false);
  expect(tools).toEqual([]);
  expect(hooks).not.toContain("tool_call");
  expect(hooks).not.toContain("resources_discover");
  expect(hooks).toEqual(expect.arrayContaining(["model_select", "turn_start", "turn_end"]));
  const send = vi.fn();
  _routeClientMessageFrom({ send } as never, { type: "perch_capabilities_get", id: "disabled" } as never, {} as never);
  expect(send).toHaveBeenCalledWith(expect.objectContaining({ type: "perch_error", error: expect.objectContaining({ code: "unsupported" }) }));
  for (const type of ["perch_push_register", "perch_push_unregister"]) {
    send.mockClear();
    _routeClientMessageFrom({ send } as never, { type, id: "push" } as never, {} as never);
    expect(send).toHaveBeenCalledWith(expect.objectContaining({ type: "perch_error", error: expect.objectContaining({ code: "unauthorized" }) }));
  }
  for (const type of ["perch_request", "perch_tool_approval_decision"]) {
    send.mockClear();
    _routeClientMessageFrom({ send } as never, { type, id: "management" } as never, {} as never);
    expect(send).toHaveBeenCalledWith(expect.objectContaining({ error: expect.objectContaining({ code: "unsupported" }) }));
  }
  _deliverMeshMessageToAgentForTest({ from: "another-agent", to: "test", id: "message", re: null, body: "must not run" });
  expect(pi.sendMessage).not.toHaveBeenCalled();
});
