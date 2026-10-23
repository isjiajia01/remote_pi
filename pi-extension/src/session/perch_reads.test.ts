import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { expect, test } from "vitest";
import { SessionPeer } from "./peer.js";
import { ipcAddress } from "./ipc.js";

/** Real isolated UDS broker, including follower routing and existing legacy inventory. */
test("Perch reads are unsupported in minimal mode, keep id/re, and legacy peer inventory still works", async () => {
  const dir = mkdtempSync(join(tmpdir(), "perch-reads-"));
  const sockPath = ipcAddress(`perch-${dir.split("/").at(-1)}`, join(dir, "broker.sock"));
  const leader = new SessionPeer({ sockPath, name: "planner", cwd: "/work/perch" });
  const follower = new SessionPeer({ sockPath, name: "coder", cwd: "/work/perch" });
  const read = (peer: SessionPeer, id: string, method: string, params = {}) =>
    peer.request("broker", { type: "perch_request", id, version: 1, method, params }, 2000);
  try {
    await leader.start();
    await follower.start();
    leader.localBroker()!.setRemoteRouter({
      tryRouteOutbound: () => false,
      listRemotePeers: () => ["sibling:other"],
      listRemotePeerInfos: () => [{ pc: "sibling", cwd: "", name: "other", address: "sibling:other" }],
    });
    const legacy = await follower.request("broker", { type: "list_peers" }, 2000);
    expect(legacy.body).toMatchObject({ peers: ["/work/perch@planner", "/work/perch@coder", "sibling:other"] });
    // Perch minimal edition: management reads are disabled at the broker.
    const reply = await read(follower, "snapshot-1", "agents.list");
    expect(reply.re).toMatch(/^[0-9a-f-]{36}$/);
    expect(reply.body).toMatchObject({ type: "perch_error", id: "snapshot-1", version: 1,
      error: { code: "unsupported" } });
  } finally {
    await follower.leave();
    await leader.leave();
    rmSync(dir, { recursive: true, force: true });
  }
});
