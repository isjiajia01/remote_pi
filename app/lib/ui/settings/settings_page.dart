import 'package:app/data/preferences/preferences.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/core/widgets/widgets.dart';
import 'package:app/ui/settings/relay_page.dart';
import 'package:app/ui/settings/states/settings_state.dart';
import 'package:app/ui/settings/viewmodels/settings_viewmodel.dart';
import 'package:app/ui/settings/widgets/widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Scaffold, ThemeMode, showLicensePage;
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();
    final prefs = context.watch<Preferences>();
    return Scaffold(
      backgroundColor: context.colors.bg,
      body: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            backgroundColor: context.colors.bg,
            border: null,
            automaticallyImplyLeading: false,
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/home'),
              child: Semantics(
                label: embedded ? 'Close' : 'Back',
                child: Icon(
                  embedded ? LucideIcons.x : LucideIcons.chevronLeft,
                  size: 22,
                  color: context.colors.accent,
                ),
              ),
            ),
            largeTitle: Text('Settings', style: context.typo.largeTitle),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverList.list(
              children: [
                const _SectionHeader('Machines'),
                _Group(
                  children: [
                    switch (vm.state) {
                      SettingsLoading() => const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CupertinoActivityIndicator()),
                      ),
                      SettingsNoPeer() => Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No machines yet',
                          style: context.typo.body,
                        ),
                      ),
                      SettingsList(:final peers) => Column(
                        children: [
                          for (final peer in peers) ...[
                            PeerListItem(
                              key: ValueKey(peer.remoteEpk),
                              peer: peer,
                              status: vm.statusFor(peer.remoteEpk),
                              onEditNickname: () =>
                                  _editNickname(context, vm, peer),
                              onRevokeRequested: () async {
                                final confirmed = await showRevokeConfirmDialog(
                                  context,
                                  peer: peer,
                                );
                                if (!confirmed) return false;
                                await vm.revoke(peer.remoteEpk);
                                return true;
                              },
                            ),
                            const _Separator(),
                          ],
                        ],
                      ),
                    },
                    _SettingsRow(
                      icon: LucideIcons.plus,
                      label: 'Pair a machine',
                      accent: true,
                      onTap: () => context.push('/pair'),
                    ),
                  ],
                ),
                const _SectionHeader('Relay'),
                _Group(
                  children: [
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      onPressed: () => Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          builder: (_) => ChangeNotifierProvider.value(
                            value: vm,
                            child: const RelayPage(),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          RelayReachabilityDot(status: vm.state.relay.status),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  Uri.tryParse(vm.effectiveRelayUrl)?.host ??
                                      vm.effectiveRelayUrl,
                                  style: context.typo.mono,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(switch (vm.state.relay.status) {
                                  SettingsRelayStatus.unknown ||
                                  SettingsRelayStatus.checking =>
                                    'Checking relay…',
                                  SettingsRelayStatus.reachable => 'Reachable',
                                  SettingsRelayStatus.failed => 'Unreachable',
                                }, style: context.typo.caption),
                              ],
                            ),
                          ),
                          Icon(
                            LucideIcons.chevronRight,
                            size: 20,
                            color: context.colors.ink3,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    'All paired machines must use the same relay.',
                    style: context.typo.footnote,
                  ),
                ),
                const _SectionHeader('Appearance'),
                _Group(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        child: CupertinoSlidingSegmentedControl<ThemeMode>(
                          groupValue: prefs.themeMode,
                          backgroundColor: context.colors.surface2,
                          thumbColor: context.colors.surface,
                          children: {
                            for (final mode in ThemeMode.values)
                              mode: Text(
                                switch (mode) {
                                  ThemeMode.system => 'System',
                                  ThemeMode.light => 'Light',
                                  ThemeMode.dark => 'Dark',
                                },
                                style: context.typo.subhead.copyWith(
                                  color: context.colors.ink,
                                ),
                              ),
                          },
                          onValueChanged: (mode) {
                            if (mode != null) prefs.setThemeMode(mode);
                          },
                        ),
                      ),
                    ),
                    const _Separator(),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Text size', style: context.typo.body),
                          const SizedBox(height: 12),
                          CupertinoSlidingSegmentedControl<AppFontScale>(
                            groupValue: prefs.fontScale,
                            backgroundColor: context.colors.surface2,
                            thumbColor: context.colors.surface,
                            children: {
                              for (final scale in AppFontScale.values)
                                scale: Text(
                                  scale.label,
                                  style: context.typo.footnote.copyWith(
                                    color: context.colors.ink,
                                  ),
                                ),
                            },
                            onValueChanged: (scale) {
                              if (scale != null) prefs.setFontScale(scale);
                            },
                          ),
                        ],
                      ),
                    ),
                    const _Separator(),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Hide tool calls in chat',
                              style: context.typo.body,
                            ),
                          ),
                          const SizedBox(width: 8),
                          CupertinoSwitch(
                            value: prefs.hideToolCalls,
                            activeTrackColor: context.colors.accent,
                            onChanged: prefs.setHideToolCalls,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const _SectionHeader('About'),
                _Group(
                  children: [
                    _SettingsRow(
                      icon: LucideIcons.info,
                      label:
                          'Version ${vm.appVersion}${vm.buildNumber.isEmpty ? '' : ' (${vm.buildNumber})'}',
                    ),
                    const _Separator(),
                    if (vm.updatesEnabled)
                      const _UpdateRow()
                    else
                      _SettingsRow(
                        icon: LucideIcons.download,
                        label: 'Updates come from TestFlight / the App Store',
                      ),
                    const _Separator(),
                    _SettingsRow(
                      icon: LucideIcons.fileText,
                      label: 'Licenses',
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: 'Perch',
                        applicationVersion: vm.appVersion,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SliverSafeArea(top: false, sliver: SliverToBoxAdapter()),
        ],
      ),
    );
  }

  Future<void> _editNickname(
    BuildContext context,
    SettingsViewModel vm,
    PeerRecord peer,
  ) async {
    final result = await showNicknameEditor(
      context,
      defaultName: peer.sessionName,
      currentNickname: peer.nickname ?? '',
    );
    if (result != null) {
      await vm.setNickname(peer.remoteEpk, result.isEmpty ? null : result);
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Text(label.toUpperCase(), style: context.typo.sectionLabel),
  );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: ColoredBox(
      color: context.colors.surface,
      child: AnimatedSize(
        duration: Duration(
          milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 250,
        ),
        curve: Curves.easeInOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}

class _Separator extends StatelessWidget {
  const _Separator();
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 56),
    height: 1,
    color: context.colors.hairline,
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    this.onTap,
    this.accent = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ? context.colors.accent : context.colors.ink;
    final child = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: accent ? color : context.colors.ink3),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                label,
                style: context.typo.body.copyWith(color: color),
              ),
            ),
            if (onTap != null && !accent)
              Icon(
                LucideIcons.chevronRight,
                size: 20,
                color: context.colors.ink3,
              ),
          ],
        ),
      ),
    );
    return onTap == null
        ? child
        : CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onTap,
            child: child,
          );
  }
}

class _UpdateRow extends StatefulWidget {
  const _UpdateRow();
  @override
  State<_UpdateRow> createState() => _UpdateRowState();
}

class _UpdateRowState extends State<_UpdateRow> {
  bool _checking = false;
  String? _result;

  Future<void> _check() async {
    setState(() => _checking = true);
    final result = await context.read<SettingsViewModel>().checkForUpdates();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _SettingsRow(
        icon: LucideIcons.download,
        label: _checking ? 'Checking for updates…' : 'Check for updates',
        onTap: _checking ? null : _check,
      ),
      if (_result != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(56, 0, 16, 12),
          child: Text(_result!, style: context.typo.footnote),
        ),
      if (context.watch<SettingsViewModel>().hasUpdate)
        SecondaryButton(
          label: 'Download update',
          onPressed: context.read<SettingsViewModel>().openUpdate,
        ),
    ],
  );
}
