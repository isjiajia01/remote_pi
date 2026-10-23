# Perch

A focused phone companion for the [Pi coding agent](https://github.com/earendil-works/pi): pair your phone, see whether Pi is online and working, see its model, and follow or send chat messages in real time.

This repository ships **both the Flutter app and the minimal remote-pi extension**. It is a fork of [Jacob Moura's Remote Pi](https://github.com/jacobaraujo7/remote_pi); upstream source and copyright notices are preserved.

## Download

Get the combined source + extension bundle from [GitHub Releases](https://github.com/isjiajia01/remote_pi/releases). Perch release tags use `perch-v*`. The `perch/minimal` branch contains this edition; the fork's existing `main` branch is retained.

The bundle includes app source, relay source for self-hosting, and a built Node extension with a lockfile. It contains no signing credentials or device pairing data. The iOS app must be built and signed with your own Apple development identity; no generally installable IPA is supplied.

## Run the extension

Install Node.js 20+ and Pi first. In the extracted bundle:

```sh
cd pi-extension
npm install --omit=dev --ignore-scripts
pi -e "$PWD/dist/index.js"
```

If you build from Git instead, run `pnpm install --frozen-lockfile` then `pnpm build` inside `pi-extension/`, and load the resulting `dist/index.js` as above. Use the combined release's built extension for the simplest installation. Native keyring support depends on your platform; see the fallback behavior in [PROTOCOL.md](PROTOCOL.md).

In Pi, run `/remote-pi`, then `/remote-pi pair`. In the phone app, select the same relay and scan or paste the one-time pairing code. No daemon or global Pi configuration change is required.

## Build the phone app

Validated with Flutter 3.47.7 and Node.js 26.4.0. iOS requires macOS and Xcode.

```sh
cd app
flutter pub get
flutter analyze
flutter test --concurrency=1
flutter build ios --release --no-codesign
```

Set your own development team and unique bundle identifier in Xcode before installing on a device. Build a signed release locally to launch from the home screen; an iOS debug build requires Flutter/Xcode launch tooling.

## Minimal behavior

- Agents dashboard: presence, working/idle, model and thinking level.
- Pairing, chat history, streaming replies and sending messages.
- Agents and Settings navigation; necessary pairing, relay and appearance settings.
- Subtle press animation and haptics for deliberate actions, inspired by [Pow](https://github.com/EmergeTools/Pow); implemented with Flutter APIs without adding Pow as a dependency.

By default, the extension exposes no `agent_send`, `agent_request` or `list_peers` tools, does not attach a cross-PC message bridge, drops incoming agent messages before model delivery, and disables management commands/API, supervisor/cron, approvals and APNs. The app does not construct their services or show their entry points. Local broker naming/lifecycle infrastructure and shared identity/membership validation remain for compatibility.

Original full-feature source is retained. Full mode is explicit: `PERCH_FULL_FEATURES=1` for the extension process, or `--dart-define=PERCH_FULL_FEATURES=true` for an app build. Full mode has additional configuration and is outside this minimal release's device acceptance scope. Do not run the old full and minimal extensions in the same Pi process.

## Create sessions from the phone

The optional minimal `perch-sessiond` service supports browsing locally authorized
folders and creating independent Pi conversations, including multiple sessions
in the same folder and creation when no Pi session is online. It reuses pairing
and the relay without enabling full mode. See
[mobile session setup and protocol](pi-extension/docs/mobile-sessions.md).
The service is opt-in and must be deployed separately; it does not create desktop
terminal tabs or install itself automatically.

## Relay and security

Use a relay reachable by both devices; see [relay/README.md](relay/README.md) for self-hosting. TLS protects transport. **Messages are not end-to-end encrypted; the relay operator can read them.** Pairing and stored identity use the inherited authentication protocol. A sleeping/offline Mac cannot serve chat. Background push is disabled in this edition.

## Validation

See [docs/RELEASE-perch-v0.1.0.md](docs/RELEASE-perch-v0.1.0.md) for checks, device acceptance and limits. Android artifacts and App Store distribution are not part of this release.

## License

[MIT](LICENSE), retaining Jacob Moura's original copyright. Perch contributions are also MIT; see [NOTICE.md](NOTICE.md). Third-party libraries, fonts and other assets retain their respective licenses. The original monorepo's other packages remain in the Git history and source tree; this release focuses on `app/`, `pi-extension/` and `relay/`.
