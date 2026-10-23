#!/usr/bin/env node
/**
 * `pi-supervisord` — long-running daemon supervisor.
 *
 * Entry point of the `pi-supervisord` binary (plan/26 W2). Run by
 * systemd/launchd in production, or directly during dev:
 *
 *   pnpm build
 *   node dist/bin/supervisord.js
 *
 * Once running, it:
 *   - Reads `~/.pi/remote/daemons.json`
 *   - Spawns `pi --mode rpc -e <remote-pi/dist/index.js>` per entry
 *   - Listens on `~/.pi/remote/supervisor.sock` for CLI control requests
 *   - Restarts crashed children with exponential backoff
 *
 * Exits cleanly on SIGTERM/SIGINT (used by `remote-pi uninstall`).
 */
import { fullFeatures } from "../features.js";
import { loadSessionControlConfig } from "../daemon/session_control.js";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { homedir } from "node:os";
import { PerchControl, loadPerchControlConfig } from "../daemon/perch_control.js";
import { createPerchControlRelay, type PerchControlRelay } from "../daemon/perch_control_relay.js";
import { getOrCreateEd25519Keypair, listPeers } from "../pairing/storage.js";
import { canonicalizeEd25519PublicKey } from "../mesh/encoding.js";
import { resolveRelayUrl, toWebSocketUrl } from "../config.js";
import { Supervisor, SupervisorAlreadyRunningError } from "../daemon/supervisor.js";

const HELP_TEXT = `pi-supervisord — Remote Pi daemon supervisor

Usage: pi-supervisord

Runs the long-lived supervisor: reads ~/.pi/remote/daemons.json, spawns one
\`pi --mode rpc\` child per entry, and listens on ~/.pi/remote/supervisor.sock
for control requests from the \`remote-pi\` CLI.

This binary takes NO arguments — it is normally launched by systemd/launchd
(via \`remote-pi install\`), not by hand. Manage the fleet with:
  remote-pi daemon start | stop | restart | status
  remote-pi daemons

Options:
  -h, --help      Show this help and exit
  -v, --version   Print version and exit
`;

async function main(): Promise<void> {
  // Guard: any stray argument used to fall through and start a FULL
  // supervisor (a `pi-supervisord --help` once ran for days). Handle the
  // conventional flags explicitly and reject unknown args instead of
  // silently spawning the daemon fleet.
  const args = process.argv.slice(2);
  if (args.includes("-h") || args.includes("--help")) {
    process.stdout.write(HELP_TEXT);
    return;
  }
  if (args.includes("-v") || args.includes("--version")) {
    process.stdout.write("pi-supervisord (remote-pi)\n");
    return;
  }
  if (args.length > 0) {
    process.stderr.write(
      `pi-supervisord: unexpected argument(s): ${args.join(" ")}\n` +
      "This binary takes no arguments. Run `pi-supervisord --help`.\n",
    );
    process.exit(2);
  }

  // The supervisor needs to point each spawned Pi at the extension
  // entry it's bundled with. We're at `dist/bin/supervisord.js` after
  // build; the extension is the sibling `dist/index.js`.
  const here = fileURLToPath(import.meta.url);
  const distRoot = dirname(dirname(here));  // dist/bin → dist
  const extensionPath = join(distRoot, "index.js");

  if (!fullFeatures()) {
    process.stderr.write("Supervisor unavailable in Perch minimal mode\n");
    process.exitCode = 1;
    return;
  }
  const root = join(process.env["REMOTE_PI_HOME"] || homedir(), ".pi", "remote");
  if (loadPerchControlConfig(join(root, "perch-control.json")).enabled &&
      loadSessionControlConfig(join(root, "perch-sessions.json"))) {
    throw new Error("Both control endpoints use perch-control; disable one before starting the supervisor");
  }
  const supervisor = new Supervisor({ extensionPath });
  await supervisor.start();
  process.stderr.write(
    `[pi-supervisord] up — UDS: ~/.pi/remote/supervisor.sock, extension: ${extensionPath}\n`,
  );

  // Explicit local opt-in only. This endpoint belongs to the supervisor,
  // so stopping the last child never removes remote recovery access.
  const controlRoot = join(process.env["REMOTE_PI_HOME"] || homedir(), ".pi", "remote");
  const configPath = join(controlRoot, "perch-control.json");
  let controlRelay: PerchControlRelay | undefined;
  if (loadPerchControlConfig(configPath).enabled) {
    try {
      const control = new PerchControl({ configPath, journalPath: join(controlRoot, "perch-control-journal.json"),
        isPaired: async (owner) => (await listPeers()).some((peer) => {
          try { return canonicalizeEd25519PublicKey(peer.remote_epk) === owner; } catch { return false; }
        }) });
      const keypair = await getOrCreateEd25519Keypair();
      controlRelay = createPerchControlRelay(control, toWebSocketUrl(resolveRelayUrl().url), keypair);
      controlRelay.start();
    } catch {
      process.stderr.write("[pi-supervisord] Perch control unavailable; check local identity/config/journal\n");
    }
  }

  const shutdown = async (signal: string) => {
    process.stderr.write(`[pi-supervisord] received ${signal}, shutting down\n`);
    controlRelay?.stop();
    await supervisor.stop();
    process.exit(0);
  };
  process.on("SIGTERM", () => void shutdown("SIGTERM"));
  process.on("SIGINT", () => void shutdown("SIGINT"));
}

main().catch((err) => {
  // "Already running" is a normal, expected condition (systemd/launchd may
  // race a manual start, or the user double-launches) — not a crash. Report
  // it calmly and exit 0 so service managers don't flag a failure loop.
  if (err instanceof SupervisorAlreadyRunningError) {
    process.stderr.write(`[pi-supervisord] ${err.message}\n`);
    process.exit(0);
  }
  process.stderr.write(`[pi-supervisord] fatal: ${String(err)}\n`);
  process.exit(1);
});
