#!/usr/bin/env node
/** Minimal machine control service. Does not start the full daemon fleet or cron. */
import { closeSync, mkdirSync, openSync, unlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { SessionControl, loadSessionControlConfig } from "../daemon/session_control.js";
import { loadPerchControlConfig } from "../daemon/perch_control.js";
import { createPerchControlRelay } from "../daemon/perch_control_relay.js";
import { getOrCreateEd25519Keypair, listPeers } from "../pairing/storage.js";
import { canonicalizeEd25519PublicKey } from "../mesh/encoding.js";
import { resolveRelayUrl, toWebSocketUrl } from "../config.js";

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  if (args.length === 1 && ["--help", "-h"].includes(args[0]!)) {
    process.stdout.write("perch-sessiond — minimal directory browsing and independent Pi sessions\n" +
      "Usage: perch-sessiond\nRequires ~/.pi/remote/perch-sessions.json with explicit paired Owner root grants.\n" +
      "See pi-extension/docs/mobile-sessions.md. No Pi starts until a mobile create request.\n");
    return;
  }
  if (args.length) throw new Error("Unknown arguments; use --help");
  const root = join(homedir(), ".pi", "remote");
  const configPath = join(root, "perch-sessions.json");
  if (!loadSessionControlConfig(configPath)) throw new Error("Session control disabled or invalid perch-sessions.json");
  if (loadPerchControlConfig(join(root, "perch-control.json")).enabled) {
    throw new Error("Disable the full supervisor's perch-control endpoint before using perch-sessiond (same room)");
  }
  mkdirSync(root, { recursive: true, mode: 0o700 });
  // Exclusive, fail-closed lock: never guess whether an old PID is safe to take over.
  // After a hard crash the operator must verify no service/children remain first.
  const lockPath = join(root, "perch-sessiond.lock");
  const lock = openSync(lockPath, "wx", 0o600);
  writeFileSync(lock, `${process.pid}\n`);
  closeSync(lock);
  let control: SessionControl | undefined;
  let relay: ReturnType<typeof createPerchControlRelay> | undefined;
  let shuttingDown = false;
  const shutdown = async () => {
    if (shuttingDown) return;
    shuttingDown = true;
    relay?.stop();
    await control?.close();
    unlinkSync(lockPath);
  };
  try {
    const keypair = await getOrCreateEd25519Keypair();
    control = new SessionControl({ configPath, journalPath: join(root, "perch-sessions-journal.json"),
      sessionsPath: join(root, "mobile-sessions"),
      extensionPath: join(dirname(dirname(fileURLToPath(import.meta.url))), "index.js"),
      piBin: process.env["PERCH_PI_BIN"],
      isPaired: async (owner) => (await listPeers()).some((peer) => {
        try { return canonicalizeEd25519PublicKey(peer.remote_epk) === owner; } catch { return false; }
      }) });
    relay = createPerchControlRelay(control, toWebSocketUrl(resolveRelayUrl().url), keypair);
    relay.start();
    process.stderr.write("[perch-sessiond] control started; waiting for relay and mobile requests (no sessions spawned)\n");
    process.on("SIGTERM", () => void shutdown().then(() => process.exit(0)));
    process.on("SIGINT", () => void shutdown().then(() => process.exit(0)));
  } catch (error) {
    await shutdown();
    throw error;
  }
}
main().catch((error) => {
  process.stderr.write(`[perch-sessiond] ${String(error)}\n`);
  process.exitCode = 1;
});
