import 'dart:async';

import 'package:app/data/transport/epk_encoding.dart';
import 'package:app/domain/entities/perch_control.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/core/widgets/widgets.dart';
import 'package:app/ui/home/states/home_state.dart';
import 'package:app/ui/home/viewmodels/home_viewmodel.dart';
import 'package:app/ui/home/widgets/widgets.dart';
import 'package:app/ui/update/widgets/update_banner.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Scaffold;
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:app/ui/core/interaction_feedback.dart';
import 'package:provider/provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.pairedPeerEpk,
    this.notificationUnavailable = false,
  });
  final String? pairedPeerEpk;
  final bool notificationUnavailable;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Timer? _highlightTimer;
  String? _highlightedEpk;
  String? _consumedEpk;

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pairedPeerEpk != widget.pairedPeerEpk) {
      _consumedEpk = null;
      _highlightTimer?.cancel();
      _highlightedEpk = null;
    }
  }

  void _highlightNewMachine(HomeState state) {
    final epk = widget.pairedPeerEpk;
    if (epk == null ||
        epk == _consumedEpk ||
        state is! HomeList ||
        !state.peers.any((p) => p.remoteEpk == epk)) {
      return;
    }
    _consumedEpk = epk;
    _highlightedEpk = epk;
    _highlightTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _highlightedEpk = null);
    });
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HomeViewModel>();
    final state = vm.state;
    _highlightNewMachine(state);
    final shell = context.read<ShellLayout>();
    final zero =
        state is HomeNoPeer ||
        state is HomeList && state.items(normalizeEpk: toStandardB64).isEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) shell.setZeroState(zero);
    });
    return Scaffold(
      backgroundColor: context.colors.bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          CupertinoSliverNavigationBar(
            backgroundColor: context.colors.bg,
            border: null,
            largeTitle: Text('Agents', style: context.typo.largeTitle),
            automaticallyImplyLeading: false,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state is HomeList && state.peers.isNotEmpty)
                  CupertinoButton(
                    padding: const EdgeInsets.all(10),
                    minimumSize: const Size(44, 44),
                    onPressed: () {
                      InteractionFeedback.selection();
                      context.push('/new-session');
                    },
                    child: Semantics(
                      label: 'New session',
                      button: true,
                      child: Icon(
                        LucideIcons.plus,
                        size: 22,
                        color: context.colors.ink2,
                      ),
                    ),
                  ),
                CupertinoButton(
                  padding: const EdgeInsets.all(10),
                  minimumSize: const Size(44, 44),
                  onPressed: () {
                    InteractionFeedback.selection();
                    context.push('/settings');
                  },
                  child: Semantics(
                    label: 'Settings',
                    button: true,
                    child: Icon(
                      LucideIcons.settings,
                      size: 22,
                      color: context.colors.ink2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          CupertinoSliverRefreshControl(onRefresh: vm.refresh),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _ConnectionLine(relay: vm.relay),
            ),
          ),
          const SliverToBoxAdapter(child: UpdateBanner()),
          if (widget.notificationUnavailable)
            const SliverToBoxAdapter(
              child: AppBanner(
                message:
                    'This notification’s session is unavailable. Open an agent to reconnect.',
              ),
            ),
          if (state is HomeList && state.relay == HomeRelay.offline)
            SliverToBoxAdapter(
              child: AppBanner(
                message: 'Relay offline — showing last known state',
                actionLabel: 'Retry',
                onAction: vm.retry,
              ),
            ),
          switch (state) {
            HomeLoading() => const SliverToBoxAdapter(child: HomeSkeleton()),
            HomeNoPeer() => const SliverFillRemaining(
              hasScrollBody: false,
              child: HomeNoMachine(),
            ),
            HomeList() => _list(context, vm, state),
          },
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 24),
          ),
        ],
      ),
    );
  }

  /// Expanded disclosures: `sub:<sessionKey>`, `off:<projectKey>`,
  /// `not-running`. All collapsed by default; this app run only.
  final Set<String> _expanded = {};

  bool _isOpen(String key) => _expanded.contains(key);
  void _toggle(String key) => setState(
    () => _expanded.contains(key) ? _expanded.remove(key) : _expanded.add(key),
  );

  Widget _row(
    BuildContext context,
    HomeViewModel vm,
    HomeList state,
    HomeItem item,
  ) => AgentRow(
    key: ValueKey(item.key),
    item: item,
    highlighted:
        item.peer.remoteEpk == _highlightedEpk && _highlightedEpk != null,
    showMachine: state.peers.length > 1,
    showPath: false,
    selected:
        isWideLayout(context) &&
        context.watch<SessionSelection>().matches(
          item.peer.remoteEpk,
          item.room.roomId,
        ),
    staleSince: state.staleSince,
    now: state.now,
    onOpen: () => _open(context, vm, item.peer, item.room),
    onRemove: vm.canRemove(item) ? () => vm.removeOffline([item]) : null,
    onEnd: vm.canEnd(item) ? () => _confirmEnd(context, vm, item) : null,
  );

  List<Widget> _subagents(
    BuildContext context,
    HomeViewModel vm,
    HomeList state,
    String key,
    List<HomeItem> subs, {
    bool unlinked = false,
  }) {
    if (subs.isEmpty) return const [];
    final working = subs
        .where((s) => s.lastKnownStatus == AgentStatus.working)
        .length;
    final label =
        '${plural(subs.length, 'sub-agent')}${working > 0 ? ' · $working working' : ''}${unlinked ? ' · parent not shown' : ''}';
    return [
      DisclosureRow(
        key: ValueKey('disclosure-$key'),
        label: label,
        expanded: _isOpen(key),
        onToggle: () => _toggle(key),
      ),
      if (_isOpen(key))
        for (final sub in subs)
          SubagentRow(
            key: ValueKey(sub.key),
            item: sub,
            now: state.now,
            onOpen: () => _open(context, vm, sub.peer, sub.room),
          ),
    ];
  }

  Widget _card(String key, List<Widget> rows) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
    child: Container(
      key: ValueKey('project-card-$key'),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(children: rows),
      ),
    ),
  );

  /// Hidden until the relay confirmed which rooms are running.
  Widget? _removeButton(
    BuildContext context,
    HomeViewModel vm,
    List<HomeItem> items,
  ) {
    final removable = items.where(vm.canRemove).toList();
    if (removable.isEmpty) return null;
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      minimumSize: const Size(44, 44),
      onPressed: () => _confirmRemove(context, vm, removable),
      child: Text(
        'Remove',
        style: context.typo.footnote.copyWith(color: context.colors.error),
      ),
    );
  }

  Widget _liveCard(
    BuildContext context,
    HomeViewModel vm,
    HomeList state,
    HomeGroup group,
  ) {
    final rows = <Widget>[ProjectHeader(group: group)];
    for (var i = 0; i < group.sessions.length; i++) {
      final session = group.sessions[i];
      if (i > 0) rows.add(const RowDivider());
      rows.add(_row(context, vm, state, session.item));
      rows.addAll(
        _subagents(
          context,
          vm,
          state,
          'sub:${session.item.key}',
          session.subagents,
        ),
      );
    }
    if (group.orphans.isNotEmpty) {
      if (group.sessions.isNotEmpty) rows.add(const RowDivider());
      rows.addAll(
        _subagents(
          context,
          vm,
          state,
          'sub:${group.key}',
          group.orphans,
          unlinked: true,
        ),
      );
    }
    if (group.offline.isNotEmpty) {
      final key = 'off:${group.key}';
      final open = _isOpen(key) || state.filter == HomeFilter.offline;
      rows.add(const RowDivider(indent: 16));
      rows.add(
        DisclosureRow(
          key: ValueKey('disclosure-$key'),
          label: 'Offline · ${group.offline.length}',
          expanded: open,
          onToggle: () => _toggle(key),
          indent: 16,
          trailing: _removeButton(context, vm, group.offline),
        ),
      );
      if (open) {
        for (final item in group.offline) {
          rows.add(_row(context, vm, state, item));
        }
      }
    }
    rows.add(const SizedBox(height: 4));
    return _card(group.key, rows);
  }

  Widget _offlineCard(
    BuildContext context,
    HomeViewModel vm,
    HomeList state,
    HomeGroup group,
  ) => _card(group.key, [
    ProjectHeader(group: group),
    for (final item in group.offline) _row(context, vm, state, item),
    const SizedBox(height: 4),
  ]);

  Widget _list(BuildContext context, HomeViewModel vm, HomeList state) {
    final groups = state.groups(normalizeEpk: toStandardB64);
    final live = groups.where((g) => g.isLive).toList();
    final resting = groups.where((g) => !g.isLive).toList();
    final children = <Widget>[
      for (final group in live) _liveCard(context, vm, state, group),
    ];
    if (resting.isNotEmpty) {
      final open =
          _isOpen('not-running') ||
          live.isEmpty ||
          state.filter == HomeFilter.offline;
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
          child: DisclosureRow(
            key: const ValueKey('disclosure-not-running'),
            label: 'Not running · ${plural(resting.length, 'project')}',
            expanded: open,
            onToggle: () => _toggle('not-running'),
            indent: 20,
            trailing: _removeButton(context, vm, [
              for (final g in resting) ...g.offline,
            ]),
          ),
        ),
      );
      if (open) {
        for (final group in resting) {
          children.add(_offlineCard(context, vm, state, group));
        }
      }
    }
    if (state.filter == HomeFilter.all) {
      for (final peer in state.emptyPeers(normalizeEpk: toStandardB64)) {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: HomeNoAgents(
              machine: machineLabel(peer),
              highlighted:
                  peer.remoteEpk == _highlightedEpk && _highlightedEpk != null,
            ),
          ),
        );
      }
    }
    return SliverMainAxisGroup(
      slivers: [
        if (vm.counts.all > 5)
          SliverToBoxAdapter(
            child: HomeFilterTabs(
              filter: state.filter,
              counts: vm.counts,
              stale: state.relay != HomeRelay.connected,
              onSelected: vm.setFilter,
            ),
          ),
        if (groups.isEmpty && state.filter != HomeFilter.all)
          SliverFillRemaining(
            hasScrollBody: false,
            child: HomeFilterEmptyState(
              filter: state.filter,
              onShowAll: () => vm.setFilter(HomeFilter.all),
            ),
          )
        else
          SliverList.list(children: children),
      ],
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    HomeViewModel vm,
    List<HomeItem> items,
  ) async {
    final ok = await showConfirmSheet(
      context,
      title: items.length == 1
          ? 'Remove 1 offline session?'
          : 'Remove ${items.length} offline sessions?',
      message:
          'They leave this list and come back if they start again. Chat history on this phone is kept.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (ok) await vm.removeOffline(items);
  }

  Future<void> _confirmEnd(
    BuildContext context,
    HomeViewModel vm,
    HomeItem item,
  ) async {
    final ok = await showConfirmSheet(
      context,
      title: 'End this phone session?',
      message:
          'Pi stops in ${projectLabel(item.room)} on ${machineLabel(item.peer)}. A reply in progress is cancelled. The session history stays on the Mac.',
      confirmLabel: 'End session',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await vm.endPhoneSession(item);
    } on ControlFailure catch (e) {
      if (!context.mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialog) => CupertinoAlertDialog(
          title: const Text('Couldn’t end session'),
          content: Text(switch (e.code) {
            'offline' || 'timeout' =>
              'Your Mac or its Perch session service is not reachable. Check that the Mac is awake and try again.',
            'unsupported' =>
              'This Mac’s Perch session service is not running, so phone sessions can’t be ended remotely.',
            'forbidden' || 'unauthorized' =>
              'Only the phone that created this session can end it.',
            'conflict' =>
              'The session service no longer owns this process. End it on the Mac.',
            _ => e.message,
          }),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialog).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  static Future<void> _open(
    BuildContext context,
    HomeViewModel vm,
    PeerRecord peer,
    RoomInfo room,
  ) async {
    // Sets prefs (selectedPeerEpk + room) + switchRoom so a fresh
    // ChatViewModel binds to this session.
    await vm.openSession(peer.remoteEpk, roomId: room.roomId);
    if (!context.mounted) return;
    final title = _titleFor(peer, room);
    // Plan/32g — the device (Mac) name we already know here. The Chat AppBar's
    // line 2 renders this immediately instead of flickering empty/room-title
    // until the PeerRecord loads async.
    final device = _deviceFor(peer);
    // Plan/32g — the live state of this tile (the green dot). Passed so the
    // Chat AppBar's status dot starts correct instead of flashing
    // "reconnecting" before the runtime is read.
    final online = vm.isRoomLive(peer.remoteEpk, room.roomId);
    // Mark the UI selection — drives the tablet detail pane AND the
    // highlighted tile. Set AFTER openSession so the detail's fresh
    // ChatViewModel reads the already-updated prefs.
    context.read<SessionSelection>().select(
      peer.remoteEpk,
      room.roomId,
      title,
      device,
      online,
    );
    // Phone: full-screen chat (root push → native back/swipe). Tablet:
    // the detail pane reacts to the selection above — no nav needed.
    if (!isWideLayout(context)) {
      context.push(
        '/chat',
        extra: {'title': title, 'device': device, 'online': online},
      );
    }
  }

  /// Plan/32g — the paired-device label for the Chat AppBar's line 2
  /// (nickname → sessionName → epk prefix). Mirrors [ChatPage]'s own peer
  /// resolution so there's no change when the PeerRecord finishes loading.
  static String _deviceFor(PeerRecord peer) =>
      (peer.nickname?.isNotEmpty ?? false)
      ? peer.nickname!
      : peer.sessionName.isNotEmpty
      ? peer.sessionName
      : peer.remoteEpk.substring(0, 8);

  /// Plan/24-fix-title: the peer/room label we already know here, so the
  /// Chat AppBar doesn't show '—' / 'Remote Pi' until the ChatViewModel
  /// loads the PeerRecord + the first room_meta_updated arrives. Prefers
  /// room.name (per-cwd title) → cwd tail → nickname → sessionName.
  static String _titleFor(PeerRecord peer, RoomInfo room) {
    final roomCwdTail = room.cwd
        ?.split('/')
        .where((s) => s.isNotEmpty)
        .lastOrNull;
    return (room.name?.isNotEmpty ?? false)
        ? room.name!
        : (roomCwdTail != null && roomCwdTail.isNotEmpty)
        ? roomCwdTail
        : (peer.nickname?.isNotEmpty ?? false)
        ? peer.nickname!
        : peer.sessionName.isNotEmpty
        ? peer.sessionName
        : peer.remoteEpk.substring(0, 8);
  }
}

class _ConnectionLine extends StatelessWidget {
  const _ConnectionLine({required this.relay});
  final HomeRelay relay;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: switch (relay) {
              HomeRelay.connected => c.online,
              HomeRelay.connecting => c.ink3,
              HomeRelay.offline => c.error,
            },
          ),
        ),
        const SizedBox(width: 8),
        Text(
          switch (relay) {
            HomeRelay.connected => 'Relay connected',
            HomeRelay.connecting => 'Connecting…',
            HomeRelay.offline => 'Relay offline · retrying',
          },
          style: context.typo.footnote.copyWith(
            color: switch (relay) {
              HomeRelay.connected => c.ink2,
              HomeRelay.connecting => c.ink3,
              HomeRelay.offline => c.error,
            },
          ),
        ),
      ],
    );
  }
}

class HomeNoMachine extends StatelessWidget {
  const HomeNoMachine({super.key});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 4,
                  child: Container(height: 2, color: context.colors.ink),
                ),
                Positioned(
                  left: 14,
                  bottom: 6,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: context.colors.working,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('No machines yet', style: context.typo.title2),
          const SizedBox(height: 8),
          Text(
            'Pair the Pi on your Mac to see its agents here.',
            textAlign: TextAlign.center,
            style: context.typo.body.copyWith(color: context.colors.ink2),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Pair a machine',
            onPressed: () => context.push('/pair'),
          ),
        ],
      ),
    ),
  );
}

class HomeNoAgents extends StatelessWidget {
  const HomeNoAgents({
    super.key,
    required this.machine,
    this.highlighted = false,
  });
  final String machine;
  final bool highlighted;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: highlighted ? context.colors.surface2 : context.colors.surface,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'No agents running on $machine',
          style: context.typo.footnote.copyWith(color: context.colors.ink2),
        ),
        const SizedBox(height: 8),
        Text(
          'Open Pi and run /remote-pi',
          style: context.typo.caption.copyWith(color: context.colors.ink2),
        ),
      ],
    ),
  );
}

const _machineEmojis = [
  '🖥️',
  '🧑‍💻',
  '🚀',
  '🦊',
  '🐙',
  '🌵',
  '🍀',
  '🔭',
  '🧭',
  '🛰️',
  '🎧',
  '🌙',
];

/// Stable per-device emoji: laptops get 💻, otherwise a hash of the device key.
String machineEmoji(String key, String label) {
  final l = label.toLowerCase();
  if (l.contains('macbook')) return '💻';
  if (l.contains('mac mini') || l.contains('macmini')) return '🖥️';
  var h = 0;
  for (final c in key.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return _machineEmojis[h % _machineEmojis.length];
}
