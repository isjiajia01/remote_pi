# Perch v0.1.0

First public minimal Perch edition. Includes the Flutter phone app source and its minimal remote-pi Pi extension in one release bundle. Source is MIT; original upstream attribution is retained.

## Included

- One-time phone pairing and authenticated reconnect.
- Online presence, working/idle, model and thinking metadata.
- Chat history, sending messages and streaming replies.
- Agents / Settings navigation and action-driven haptics with reduced-motion-aware button feedback.
- Minimal-by-default extension: messaging tools, cross-PC messaging bridge, management API, daemon/cron, approvals and APNs disabled. Original source remains available.

## Verification

- Extension typecheck/build pass; full compatibility suite: 888 passed, 3 skipped. Minimal policy test covers no messaging tools/approval hooks, management rejection and no incoming agent-message delivery to the model.
- Flutter analyze: no issues. Minimal suite before feedback changes: 679 passed, 1 full-mode test skipped; that full navigation test passed separately.
- Feedback changes: 28 related UI tests plus 23 pairing UI tests plus one reduced-motion/button test passed; full-mode-only navigation test skipped in minimal builds.
- iPhone release build/install/launch passed. User accepted pairing/reconnect, dashboard presence/model, streaming reply, working→idle, two-tab navigation and absence of Control.
- Real-device haptic feel is not yet user-verified. Offline transitions, Android runtime and APNs were not verified. APNs is disabled.
- Some asynchronous tests initially failed under load; focused reruns and the final serial app run passed. This release does not claim the timing-sensitive tests are repaired.

## Bundle usage

The tarball contains app/, pi-extension/, relay/, shared protocol fixtures and license/build documentation. pi-extension/dist is prebuilt; install its production dependencies using the included package-lock.json, then run `pi -e /absolute/path/to/pi-extension/dist/index.js`. Do not load the full and minimal extensions together.

No IPA/APK is supplied. Sign the iOS app with your own Apple identity; the developer's device-only signing build is not a public installer. No keys, tokens, production configuration or paired-device records are included. Verify the tarball using SHA256SUMS.

The GitHub-generated source archive contains the retained monorepo source. The separately attached combined tarball adds the built extension and a production dependency lockfile.
