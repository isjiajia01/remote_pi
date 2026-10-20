import type { Ed25519Keypair } from "../pairing/crypto.js";
import { RelayClient } from "../transport/relay_client.js";
import { canonicalizeEd25519PublicKey } from "../mesh/encoding.js";
import { perchError, type PerchClientMessage } from "../protocol/perch.js";
import { PerchControl } from "./perch_control.js";
import { PERCH_CONTROL_ROOM } from "./perch_control_protocol.js";

export interface ControlRelayTransport {
  connect(options: { roomId: string; roomMeta: { name: string; cwd: string } }): Promise<void>;
  on(event: "message", listener: (line: string) => void): unknown;
  on(event: "close", listener: () => void): unknown;
  on(event: "error", listener: (error: Error) => void): unknown;
  send(line: string): void;
  close(): void;
}

/** Persistent authenticated machine endpoint, independent of all RPC children.
 * `peer` is supplied by the authenticated relay, never by the decoded inner payload.
 * Pairing and local grants are rechecked by PerchControl on every queued request.
 */
export class PerchControlRelay {
  private stopped = true;
  private generation = 0;
  private transport: ControlRelayTransport | null = null;
  private retry: ReturnType<typeof setTimeout> | undefined;
  private inFlight = 0;

  constructor(private readonly control: PerchControl,
    private readonly createTransport: () => ControlRelayTransport) {}

  start(): void {
    if (!this.stopped) return;
    this.stopped = false;
    void this.connect();
  }

  stop(): void {
    this.stopped = true;
    this.generation++;
    clearTimeout(this.retry);
    this.control.disconnect();
    this.transport?.close();
    this.transport = null;
  }

  private schedule(): void {
    if (this.stopped || this.retry) return;
    this.retry = setTimeout(() => { this.retry = undefined; void this.connect(); }, 2000);
  }

  private async connect(): Promise<void> {
    const generation = ++this.generation;
    const relay = this.createTransport();
    this.transport = relay;
    relay.on("error", () => {});
    relay.on("close", () => {
      if (generation !== this.generation) return;
      this.generation++;
      this.transport = null;
      this.control.disconnect();
      this.schedule();
    });
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      await Promise.race([
        relay.connect({ roomId: PERCH_CONTROL_ROOM, roomMeta: { name: "Perch Control", cwd: "" } }),
        new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new Error("Control relay connect timeout")), 12_000); }),
      ]);
      if (this.stopped || generation !== this.generation) { relay.close(); return; }
      relay.on("message", (line) => {
        if (this.stopped || generation !== this.generation || line.length > 64 * 1024 || this.inFlight >= 32) return;
        let peer: string;
        let msg: PerchClientMessage;
        try {
          const envelope = JSON.parse(line) as { peer?: unknown; ct?: unknown };
          if (typeof envelope.peer !== "string" || typeof envelope.ct !== "string") return;
          peer = canonicalizeEd25519PublicKey(envelope.peer);
          const inner: unknown = JSON.parse(Buffer.from(envelope.ct, "base64").toString("utf8"));
          if (!inner || typeof inner !== "object" || !("type" in inner) ||
              (inner.type !== "perch_request" && inner.type !== "perch_capabilities_get")) return;
          msg = inner as PerchClientMessage;
        } catch { return; }
        this.inFlight++;
        void this.control.handle(peer, msg).then((response) => {
          if (!this.stopped && generation === this.generation) {
            const body = JSON.stringify(response);
            const bounded = Buffer.byteLength(body) <= 1024 * 1024 ? body :
              JSON.stringify(perchError(response.id, "internal", "Control response exceeds limit"));
            relay.send(JSON.stringify({ peer, ct: Buffer.from(bounded).toString("base64") }));
          }
        }).catch(() => {}).finally(() => { this.inFlight--; });
      });
    } catch {
      relay.close();
      if (generation === this.generation) this.schedule();
    } finally { clearTimeout(timer); }
  }
}

export function createPerchControlRelay(control: PerchControl, url: string, keypair: Ed25519Keypair): PerchControlRelay {
  return new PerchControlRelay(control, () => new RelayClient(url, keypair));
}
