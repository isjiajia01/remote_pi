# Phase 6: minimal phone companion

Implemented and accepted on a physical iPhone on 2026-10-23. See [release verification](RELEASE-perch-v0.1.0.md) for final results and limits. Local raw logs and device identifiers are intentionally excluded from the public repository.

## Scope

Pairing, presence, working/idle, model and real-time chat. Keep the upstream source available; disable optional behavior at registration and request boundaries. No dependency additions, existing-source deletion or identity migration.

## Extension boundaries

- `src/features.ts`: minimal by default; explicit `PERCH_FULL_FEATURES=1` restores the retained full implementation.
- `src/index.ts`: do not register agent_send/list_peers/agent_request, deploy/discover the agent-network skill, register daemon/cron/install commands, attach the cross-PC bridge or register tool approval hooks. Reject Perch management requests. Drop incoming agent messages before model delivery. Skip push initialization and delivery.
- `src/session/broker.ts`: do not construct PerchBrokerReads or record management events in minimal mode; return unsupported for management reads.
- `src/bin/supervisord.ts`: refuse startup in minimal mode before constructing the supervisor; no cron engine or control relay starts.
- Preserve local broker join/naming locks, pairing/storage, identity normalization, Owner validation and self-revocation. They share infrastructure with the main room lifecycle and cannot be removed by deleting mesh/ wholesale.
- Preserve RelayClient, room metadata, working/model updates, session synchronization and streaming. A shared full broker on the machine does not grant this minimal session messaging tools or model delivery of agent envelopes.

## App boundaries

- `lib/config/features.dart`: compile-time full-mode opt-in.
- `lib/config/dependencies.dart` and `lib/main.dart`: do not construct management, approval or push services in minimal mode; do not request notification registration.
- Navigation: Agents / Settings. Timeline is hidden, and old Timeline/Control routes redirect home. Settings keeps pairing, relay and appearance, without Control.
- Chat receives no approval client. Ordinary tool output and extension questions remain supported.
- Dashboard continues using room presence/metadata; it does not require agents.list/events.

## Feedback

Inspired by EmergeTools/Pow's documented selection/impact and push-down concepts, implemented with Flutter APIs. Buttons press to 0.97 scale; reduced-motion mode disables scaling. Selection changes use selectionClick; send/stop/buttons use lightImpact; pairing success/failure transitions use mediumImpact and retain visible status. No per-token or automatic working-state haptics. Feedback is foreground-only and rate-limited to 100ms. Success/failure do not use distinct native notification patterns.

## Acceptance

Physical-device pairing/authenticated reconnect, online/model dashboard, user-sent messages, incremental replies, working→idle, two-tab navigation and absence of Control accepted. Offline transition and real-device haptic feel remain unverified. Automated test results are in the release note. No global extension configuration, relay service or existing device pairing was manually modified.
