import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/core/widgets/widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Scaffold;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import 'viewmodels/control_viewmodel.dart';

class ControlPage extends StatelessWidget {
  const ControlPage({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ControlViewModel>();
    final state = vm.state;
    return Scaffold(
      backgroundColor: context.colors.bg,
      body: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            backgroundColor: context.colors.bg,
            border: null,
            largeTitle: Text('Control', style: context.typo.largeTitle),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: state.busy ? null : vm.refresh,
              child: Icon(
                LucideIcons.refreshCw,
                size: 22,
                color: context.colors.accent,
              ),
            ),
          ),
          CupertinoSliverRefreshControl(onRefresh: vm.refresh),
          SliverList.list(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    MetaChip(label: vm.machineLabel, monospace: false),
                    if (state.revision != null)
                      MetaChip(label: 'Revision ${state.revision}'),
                  ],
                ),
              ),
              if (state.message != null)
                AppBanner(
                  message: state.message!,
                  actionLabel: state.busy ? null : 'Refresh',
                  onAction: state.busy ? null : vm.refresh,
                ),
              if (state.retry != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: CupertinoButton(
                    onPressed: state.busy ? null : vm.retry,
                    child: Text(
                      'Retry same action',
                      style: context.typo.body.copyWith(
                        color: context.colors.accent,
                      ),
                    ),
                  ),
                ),
              if (state.busy)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CupertinoActivityIndicator()),
                ),
              if (state.updatedAt != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
                  child: Text(
                    '${state.ready ? 'As of' : 'Last known · as of'} ${state.updatedAt!.toLocal()}',
                    style: context.typo.footnote,
                  ),
                ),
              if (!state.disabled) ...[
                _header(context, 'Daemons'),
                _group(context, [
                  if (state.daemons.isEmpty)
                    _empty(
                      context,
                      state.ready
                          ? 'No permitted daemons'
                          : 'Refresh to load daemons',
                    ),
                  for (final daemon in state.daemons)
                    _ControlRow(
                      children: [
                        Row(
                          children: [
                            StatusDot(
                              status: !state.ready
                                  ? AgentStatus.stale
                                  : switch (daemon.state) {
                                      'running' => AgentStatus.online,
                                      'starting' => AgentStatus.checking,
                                      _ => AgentStatus.offline,
                                    },
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                daemon.name,
                                style: context.typo.headline,
                              ),
                            ),
                            Text(daemon.state, style: context.typo.caption),
                          ],
                        ),
                        const SizedBox(height: 8),
                        MetaChip(label: daemon.id),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final verb in ['start', 'stop', 'restart'])
                              _action(
                                context,
                                verb == 'start'
                                    ? 'Start'
                                    : verb == 'stop'
                                    ? 'Stop'
                                    : 'Restart',
                                enabled: state.can('daemon.$verb'),
                                onPressed: () => _daemonAction(
                                  context,
                                  vm,
                                  daemon.id,
                                  daemon.name,
                                  verb,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                ]),
                _header(context, 'Cron'),
                _group(context, [
                  if (state.jobs.isEmpty)
                    _empty(
                      context,
                      state.ready
                          ? 'No permitted cron jobs'
                          : 'Refresh to load cron jobs',
                    ),
                  for (final job in state.jobs)
                    _ControlRow(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(job.id, style: context.typo.headline),
                            ),
                            Semantics(
                              label: 'Enable ${job.id}',
                              child: CupertinoSwitch(
                                value: job.enabled,
                                activeTrackColor: context.colors.accent,
                                onChanged: state.can('cron.set_enabled')
                                    ? (enabled) => vm.perform(
                                        'cron.set_enabled',
                                        {'job_id': job.id, 'enabled': enabled},
                                      )
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            MetaChip(label: job.schedule),
                            MetaChip(label: job.daemonId),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          job.prompt,
                          style: context.typo.body,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            _action(
                              context,
                              'Run now',
                              enabled: state.can('cron.run'),
                              onPressed: () =>
                                  vm.perform('cron.run', {'job_id': job.id}),
                            ),
                            _action(
                              context,
                              'Log',
                              enabled: state.can('cron.log'),
                              onPressed: () => vm.perform('cron.log', {
                                'job_id': job.id,
                                'tail': 100,
                              }),
                            ),
                            _action(
                              context,
                              'Remove',
                              enabled: state.can('cron.remove'),
                              onPressed: () => _remove(context, vm, job.id),
                            ),
                          ],
                        ),
                      ],
                    ),
                ]),
                if (state.log != null) ...[
                  _header(context, 'Log · ${state.logJobId}'),
                  _group(context, [
                    if (state.log!.isEmpty) _empty(context, 'No log entries'),
                    for (final entry in state.log!)
                      _ControlRow(
                        children: [
                          Text(
                            '${entry.time.toLocal()}',
                            style: context.typo.caption,
                          ),
                          Text(entry.result, style: context.typo.body),
                          Text(entry.preview, style: context.typo.footnote),
                        ],
                      ),
                  ]),
                ],
                if (state.capabilities?.methods.contains('cron.add') == true &&
                    state.daemons.isNotEmpty) ...[
                  _header(context, 'Add cron'),
                  _group(context, [const _AddCronForm()]),
                ],
              ],
              const SizedBox(height: 32),
            ],
          ),
          const SliverSafeArea(top: false, sliver: SliverToBoxAdapter()),
        ],
      ),
    );
  }

  Future<void> _daemonAction(
    BuildContext context,
    ControlViewModel vm,
    String id,
    String name,
    String verb,
  ) async {
    if (verb != 'start') {
      final confirmed = await showConfirmSheet(
        context,
        title: '${verb == 'stop' ? 'Stop' : 'Restart'} $name?',
        message: 'This can interrupt work on this Mac.',
        confirmLabel: verb == 'stop' ? 'Stop' : 'Restart',
        destructive: true,
      );
      if (!context.mounted || !confirmed) return;
    }
    await vm.perform('daemon.$verb', {'id': id});
  }

  Future<void> _remove(
    BuildContext context,
    ControlViewModel vm,
    String id,
  ) async {
    final confirmed = await showConfirmSheet(
      context,
      title: 'Remove $id?',
      message: 'This removes the scheduled job from this Mac.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!context.mounted || !confirmed) return;
    await vm.perform('cron.remove', {'job_id': id});
  }
}

Widget _header(BuildContext context, String label) => Padding(
  padding: const EdgeInsets.fromLTRB(32, 24, 32, 8),
  child: Text(label.toUpperCase(), style: context.typo.sectionLabel),
);
Widget _empty(BuildContext context, String label) => Padding(
  padding: const EdgeInsets.all(16),
  child: Text(label, style: context.typo.body),
);
Widget _group(BuildContext context, List<Widget> children) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16),
  child: ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: ColoredBox(
      color: context.colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Container(
                margin: const EdgeInsets.only(left: 56),
                height: 1,
                color: context.colors.hairline,
              ),
            children[i],
          ],
        ],
      ),
    ),
  ),
);
Widget _action(
  BuildContext context,
  String label, {
  required bool enabled,
  required VoidCallback onPressed,
}) => CupertinoButton(
  padding: const EdgeInsets.symmetric(horizontal: 8),
  onPressed: enabled ? onPressed : null,
  child: Text(
    label,
    style: context.typo.body.copyWith(color: context.colors.accent),
  ),
);

class _ControlRow extends StatelessWidget {
  const _ControlRow({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 64),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    ),
  );
}

class _AddCronForm extends StatefulWidget {
  const _AddCronForm();
  @override
  State<_AddCronForm> createState() => _AddCronFormState();
}

class _AddCronFormState extends State<_AddCronForm> {
  final _schedule = TextEditingController();
  final _prompt = TextEditingController();
  String? _daemonId;
  @override
  void dispose() {
    _schedule.dispose();
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ControlViewModel>();
    final state = vm.state;
    final daemonId = state.daemons.any((d) => d.id == _daemonId)
        ? _daemonId!
        : state.daemons.first.id;
    final enabled = state.can('cron.add');
    return _ControlRow(
      children: [
        Text('Daemon', style: context.typo.footnote),
        Wrap(
          children: [
            for (final daemon in state.daemons)
              CupertinoButton(
                onPressed: enabled
                    ? () => setState(() => _daemonId = daemon.id)
                    : null,
                child: Text(
                  '${daemon.id == daemonId ? '✓ ' : ''}${daemon.name}',
                  style: context.typo.body.copyWith(
                    color: context.colors.accent,
                  ),
                ),
              ),
          ],
        ),
        Text(
          'Schedule · at least 60 seconds between runs',
          style: context.typo.footnote,
        ),
        const SizedBox(height: 8),
        CupertinoTextField(
          controller: _schedule,
          enabled: enabled,
          maxLength: 256,
          placeholder: '0 * * * *',
          style: context.typo.mono,
          autocorrect: false,
          decoration: BoxDecoration(
            color: context.colors.surface2,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.all(12),
        ),
        const SizedBox(height: 12),
        Text(
          'Prompt · up to ${state.capabilities?.maxPromptChars ?? 8192} characters',
          style: context.typo.footnote,
        ),
        const SizedBox(height: 8),
        CupertinoTextField(
          controller: _prompt,
          enabled: enabled,
          maxLength: state.capabilities?.maxPromptChars ?? 8192,
          minLines: 3,
          maxLines: 6,
          placeholder: 'What should the agent do?',
          style: context.typo.body,
          decoration: BoxDecoration(
            color: context.colors.surface2,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.all(12),
        ),
        _action(
          context,
          'Add cron',
          enabled: enabled,
          onPressed: () => vm.addCron(daemonId, _schedule.text, _prompt.text),
        ),
      ],
    );
  }
}
