import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { expect, test } from "vitest";
import { SessionPeer } from "./peer.js";
import { ipcAddress } from "./ipc.js";
import type { PerchSnapshot, PerchEvents } from "../protocol/perch.js";

/** Real isolated UDS broker, including follower routing and existing legacy inventory. */
test("Perch reads share one broker across leader/follower, preserve id/re and exclude sibling rosters", async () => {
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
    const snapshotReply = await read(follower, "snapshot-1", "agents.list");
    expect(snapshotReply.re).toMatch(/^[0-9a-f-]{36}$/);
    expect(snapshotReply.body).toMatchObject({ type: "perch_result", id: "snapshot-1", version: 1 });
    const snapshot = (snapshotReply.body as { result: PerchSnapshot }).result;
    expect(snapshot.revision).toBe(2);
    expect(snapshot.agents.map((p) => p.address)).toEqual(["/work/perch@planner", "/work/perch@coder"]);
    const before = await read(leader, "snapshot-2", "agents.list");
    expect((before.body as { result: PerchSnapshot }).result).toEqual(snapshot);
    const originalReplyId = "0199a000-0000-7000-8000-000000000000";
    const ack = await follower.sendWithAck(leader.address(), { secret: "not included in audit" }, originalReplyId);
    expect(ack.status).toBe("received");
    const params = { epoch: snapshot.epoch, cursor: snapshot.cursor };
    const eventsReply = await read(follower, "events-1", "agents.events", params);
    const events = (eventsReply.body as { result: PerchEvents }).result;
    expect(events.events).toHaveLength(1);
    expect(events.events[0]).toMatchObject({ type: "routed", id: ack.id, re: originalReplyId,
      from: follower.address(), to: leader.address(), delivered: [leader.address()], ack_status: "received", via: "uds" });
    expect(JSON.stringify(events)).not.toContain("secret");
    const duplicate = await read(leader, "events-replay", "agents.events", params);
    expect((duplicate.body as { result: PerchEvents }).result).toEqual(events);
    const waiting = read(leader, "leave-events", "agents.events", { epoch: snapshot.epoch, cursor: events.cursor, wait_ms: 1000 });
    await follower.leave();
    expect((await waiting).body).toMatchObject({ result: { events: [{ type: "peer_left", agent: { name: "coder" } }] } });
    expect((await read(leader, "snapshot-3", "agents.list")).body).toMatchObject({ result: { revision: 3, agents: [{ name: "planner" }] } });
  } finally {
    await follower.leave();
    await leader.leave();
    rmSync(dir, { recursive: true, force: true });
  }
});
