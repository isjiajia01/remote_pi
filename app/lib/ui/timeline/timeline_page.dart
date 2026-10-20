import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/core/widgets/widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Scaffold, Divider, MaterialLocalizations, TimeOfDay;
import 'package:provider/provider.dart';

import 'states/timeline_state.dart';
import 'viewmodels/timeline_viewmodel.dart';

class TimelinePage extends StatelessWidget {
  const TimelinePage({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TimelineViewModel>();
    final state = vm.state;
    final rows = <Widget>[];
    DateTime? previousDay;
    for (final event in state.visibleEvents) {
      final time = event.ts.toLocal();
      final day = DateTime(time.year, time.month, time.day);
      if (previousDay != day) {
        previousDay = day;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(_day(context, day), style: context.typo.sectionLabel),
          ),
        );
      }
      rows.add(
        Container(
          key: ValueKey('timeline-event-${event.cursor}'),
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(16),
          constraints: const BoxConstraints(minHeight: 64),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${event.actor} → ${event.target}',
                style: context.typo.mono,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(event.verb, style: context.typo.subhead),
                  ),
                  Text(
                    MaterialLocalizations.of(
                      context,
                    ).formatTimeOfDay(TimeOfDay.fromDateTime(time)),
                    style: context.typo.footnote.copyWith(
                      color: context.colors.ink2,
                      fontFeatures: AppTypography.tabularFigures,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      rows.add(
        Divider(
          height: 1,
          indent: 32,
          endIndent: 32,
          color: context.colors.hairline,
        ),
      );
    }
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
            automaticallyImplyLeading: false,
            largeTitle: Text('Timeline', style: context.typo.largeTitle),
          ),
          CupertinoSliverRefreshControl(onRefresh: vm.refresh),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '${state.machineLabel} · Local broker only',
                style: context.typo.footnote.copyWith(
                  color: context.colors.ink2,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Wrap(
              spacing: 8,
              children: [
                CupertinoButton(
                  onPressed: () => _machines(context, vm),
                  child: Text(
                    'Machine: ${state.machineLabel}',
                    style: context.typo.footnote.copyWith(
                      color: context.colors.accent,
                    ),
                  ),
                ),
                CupertinoButton(
                  onPressed: () => _agents(context, vm),
                  child: Text(
                    state.agentFilter == null
                        ? 'All agents'
                        : 'Agent: ${state.agentFilter}',
                    style: context.typo.footnote.copyWith(
                      color: context.colors.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (state.status == TimelineStatus.offline ||
              state.status == TimelineStatus.stale)
            SliverToBoxAdapter(
              child: AppBanner(
                message: state.status == TimelineStatus.offline
                    ? 'Offline — showing last known state'
                    : 'Stale — unable to refresh timeline',
                actionLabel: 'Retry',
                onAction: vm.refresh,
              ),
            ),
          if (state.lastUpdated != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  'As of ${MaterialLocalizations.of(context).formatShortDate(state.lastUpdated!.toLocal())} '
                  '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(state.lastUpdated!.toLocal()))}',
                  style: context.typo.footnote.copyWith(
                    color: context.colors.ink2,
                  ),
                ),
              ),
            ),
          if (state.historyGap)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 8),
                child: AppBanner(
                  message: 'History gap — some events unavailable',
                ),
              ),
            ),
          if (state.status == TimelineStatus.unsupported)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Not supported by this Pi version',
                    style: context.typo.body,
                  ),
                ),
              ),
            )
          else if (state.status == TimelineStatus.loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CupertinoActivityIndicator()),
            )
          else if (rows.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    state.agentFilter == null
                        ? 'No events yet'
                        : 'No events for this agent',
                    style: context.typo.body,
                  ),
                ),
              ),
            )
          else
            SliverList.list(children: rows),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  String _day(BuildContext context, DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return 'TODAY';
    if (day == DateTime(today.year, today.month, today.day - 1)) {
      return 'YESTERDAY';
    }
    return MaterialLocalizations.of(
      context,
    ).formatMediumDate(day).toUpperCase();
  }

  void _machines(BuildContext context, TimelineViewModel vm) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Machine'),
        actions: [
          for (final machine in vm.state.machines)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(sheetContext);
                vm.selectMachine(machine.id);
              },
              child: Text(machine.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _agents(BuildContext context, TimelineViewModel vm) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Agent'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(sheetContext);
              vm.filterAgent(null);
            },
            child: const Text('All agents'),
          ),
          for (final address in vm.state.addresses)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(sheetContext);
                vm.filterAgent(address);
              },
              child: Text(address),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
}
