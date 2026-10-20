import 'dart:async';

import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/epk_encoding.dart';
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
import 'package:flutter/material.dart' show Scaffold, Divider;
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.pairedPeerEpk});
  final String? pairedPeerEpk;
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
                CupertinoButton(
                  padding: const EdgeInsets.all(10),
                  minimumSize: const Size(44, 44),
                  onPressed: state is HomeList
                      ? () => _showGrouping(context, vm, state.grouping)
                      : null,
                  child: Semantics(
                    label: 'Group agents',
                    child: Icon(
                      LucideIcons.layers,
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

  Widget _list(BuildContext context, HomeViewModel vm, HomeList state) {
    final groups = state.groups(normalizeEpk: toStandardB64);
    final children = <Widget>[];
    for (final group in groups) {
      children.add(
        AgentSectionHeader(label: group.label, summary: _summary(group, state)),
      );
      final rows = <Widget>[];
      if (group.items.isEmpty) {
        rows.add(
          HomeNoAgents(
            machine: group.label,
            highlighted:
                group.peer?.remoteEpk == _highlightedEpk &&
                _highlightedEpk != null,
          ),
        );
      } else {
        for (var i = 0; i < group.items.length; i++) {
          final item = group.items[i];
          if (i > 0) {
            rows.add(
              Padding(
                padding: const EdgeInsets.only(left: 56),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: context.colors.hairline,
                ),
              ),
            );
          }
          rows.add(
            AgentRow(
              key: ValueKey(item.key),
              item: item,
              highlighted:
                  item.peer.remoteEpk == _highlightedEpk &&
                  _highlightedEpk != null,
              showMachine: state.grouping == HomeGrouping.project,
              selected:
                  isWideLayout(context) &&
                  context.watch<SessionSelection>().matches(
                    item.peer.remoteEpk,
                    item.room.roomId,
                  ),
              staleSince: state.staleSince,
              now: state.now,
              onOpen: () => _open(context, vm, item.peer, item.room),
            ),
          );
        }
      }
      final highlighted =
          group.peer?.remoteEpk == _highlightedEpk && _highlightedEpk != null;
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AnimatedContainer(
            key: ValueKey('machine-card-${group.key}'),
            duration: Duration(
              milliseconds: MediaQuery.disableAnimationsOf(context) ? 150 : 250,
            ),
            curve: Curves.easeInOutCubic,
            decoration: BoxDecoration(
              color: highlighted
                  ? context.colors.surface2
                  : context.colors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Column(children: rows),
            ),
          ),
        ),
      );
    }
    // Project grouping has no project to name until rooms are announced.
    if (groups.isEmpty && state.filter == HomeFilter.all) {
      for (final peer in state.peers) {
        children.add(PeerSectionHeader(peer: peer));
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: HomeNoAgents(machine: machineLabel(peer)),
          ),
        );
      }
    }
    return SliverMainAxisGroup(
      slivers: [
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

  String _summary(HomeGroup group, HomeList state) {
    final now = state.now ?? DateTime.now();
    if (state.relay != HomeRelay.connected) {
      return 'Last known · as of ${activityTime(state.staleSince, now)}';
    }
    final peer = group.peer;
    final presence = peer == null
        ? null
        : state.statusByEpk[toStandardB64(peer.remoteEpk)];
    if (presence is PresenceOffline) {
      final at = presence.sinceTs;
      return at == null
          ? 'Offline'
          : 'Offline · seen ${activityTime(DateTime.fromMillisecondsSinceEpoch(at), now)} ago';
    }
    final working = group.items
        .where((i) => i.lastKnownStatus == AgentStatus.working)
        .length;
    final online = group.items
        .where((i) => i.lastKnownStatus == AgentStatus.online)
        .length;
    if (working > 0 || online > 0) return '$working working · $online online';
    if (group.items.any((i) => i.lastKnownStatus == AgentStatus.checking)) {
      return 'Checking';
    }
    return group.items.isEmpty ? '' : 'Offline';
  }

  void _showGrouping(
    BuildContext context,
    HomeViewModel vm,
    HomeGrouping grouping,
  ) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          for (final value in HomeGrouping.values)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                vm.setGrouping(value);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    value == HomeGrouping.machine
                        ? 'Group by machine'
                        : 'Group by project',
                    style: context.typo.body.copyWith(
                      color: context.colors.accent,
                    ),
                  ),
                  if (grouping == value)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(
                        LucideIcons.check,
                        size: 20,
                        color: context.colors.accent,
                      ),
                    ),
                ],
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
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
