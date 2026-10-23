# Perch redesign implementation — 2026-10-23

Design reference: DESIGN-redesign.md. This implementation is integrated into the Perch default branch, perch/minimal; the published v0.1.0 tag and release assets remain unchanged.

Implemented:
- Minimal shell has no bottom tab bar; Agents exposes a 44pt Settings gear, Settings supports back navigation.
- Dashboard defaults to machine grouping, puts machine name/summary inside rounded cards, hides filters for <=5 agents, removes grouping menu and uppercase section titles. Rows show path, model, Think, idle/working state, preview and a vertical status rail.
- Status shapes distinguish stale (half-filled), offline (ring), checking (blue ring) and working pulse. Working text uses #9A5500 in light mode.
- Settings machine details action sheet exposes rename/remove; remove retains separate confirmation explaining that Mac content is not deleted. Duplicate machine names suppressed.
- Relay selection separates own/community, explains TLS/non-E2E trust boundary, adds paste, switch confirmation, checking/result feedback and rollback to saved URL. Successful check returns after 700ms. Real reachability results are used, never prototype's staged failures.
- Welcome goes directly to pairing, with optional relay change and trust copy.
- Chat model/Thinking share one entry and picker; path is selectable/copyable in Session info. Stop acknowledgement appears after an explicit cancel request returns and working ends. Offline composer is explicitly read-only.
- Original bird/perch icon installed in all iOS slots and Android adaptive foreground/monochrome resources; original SVG/1024 source in branding/perch. iOS images have no alpha.

Verification:
- flutter analyze: no issues.
- Final serial full test run: 680 passed, 1 skipped, 1 failed: existing no-echo timeout cancellation timing case. Focused rerun of that case passed; do not describe full suite as all-green.
- Updated related home/settings/chat/status tests passed in focused runs.
- Final iOS release build and device install/launch passed. Device follow-up confirmed the laptop emoji, dashboard and complete streaming output in dark mode. Dynamic type, full visual parity and physical haptics remain unverified.
- Logs remain local under /tmp/perch-e2e/redesign-*.log. No extension/relay configuration changed.

Remaining fidelity gaps:
- Model context strip includes a local elapsed timer; it starts when the mounted page observes working, not an authoritative server task duration.
- Stop acknowledgement is page-local, not a durable transcript item.
- Machine rail is dashed when offline/stale.
- Pairing includes explicit Open agents success and retains nickname editing afterward. Welcome uses the new icon.
- Follow-up focused checks after these additions: 83 tests passed, flutter analyze clean. The preceding full-suite timing failure is still recorded above.
- Wide/iPad behavior retained; Android assets generated but Android build/runtime not verified.
