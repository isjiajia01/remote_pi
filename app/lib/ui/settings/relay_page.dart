import 'package:app/data/transport/relay_config.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/core/widgets/widgets.dart';
import 'package:app/ui/settings/states/settings_state.dart';
import 'package:app/ui/settings/viewmodels/settings_viewmodel.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Scaffold;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

class RelayPage extends StatefulWidget {
  const RelayPage({super.key});

  @override
  State<RelayPage> createState() => _RelayPageState();
}

class _RelayPageState extends State<RelayPage> {
  late final TextEditingController _controller;
  bool _saving = false;
  String? _error;
  String? _saved;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: context.read<SettingsViewModel>().effectiveRelayUrl,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save({bool community = false}) async {
    if (_saving) return;
    if (community) _controller.text = kDefaultRelayUrl;
    setState(() {
      _saving = true;
      _error = null;
      _saved = null;
    });
    final vm = context.read<SettingsViewModel>();
    final error = await vm.saveRelayUrl(_controller.text);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
      _saved = error == null ? vm.state.relay.message : null;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.bg,
    body: CustomScrollView(
      slivers: [
        CupertinoSliverNavigationBar(
          backgroundColor: context.colors.bg,
          border: null,
          automaticallyImplyLeading: false,
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: Semantics(
              label: 'Back',
              child: Icon(
                LucideIcons.chevronLeft,
                size: 22,
                color: context.colors.accent,
              ),
            ),
          ),
          largeTitle: Text('Relay', style: context.typo.largeTitle),
        ),
        SliverSafeArea(
          top: false,
          sliver: SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList.list(
              children: [
                Text(
                  'Your phone and your Mac meet through a relay. Messages pass through it.',
                  style: context.typo.footnote,
                ),
                const SizedBox(height: 24),
                Text('Relay URL', style: context.typo.headline),
                const SizedBox(height: 12),
                CupertinoTextField(
                  controller: _controller,
                  enabled: !_saving,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  placeholder: 'https://host.tailnet.ts.net',
                  placeholderStyle: context.typo.mono.copyWith(
                    color: context.colors.ink2,
                  ),
                  style: context.typo.mono,
                  cursorColor: context.colors.accent,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.colors.surface2,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  onChanged: (_) => setState(() {
                    _error = null;
                    _saved = null;
                  }),
                ),
                const SizedBox(height: 12),
                Text(
                  'All paired machines must use the same relay.',
                  style: context.typo.footnote,
                ),
                const SizedBox(height: 16),
                if (_saving) ...[
                  Row(
                    children: [
                      CupertinoActivityIndicator(
                        radius: 8,
                        color: context.colors.accent,
                      ),
                      const SizedBox(width: 8),
                      Text('Checking relay…', style: context.typo.footnote),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                if (_error != null || _saved != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _error != null
                              ? LucideIcons.circleAlert
                              : LucideIcons.check,
                          size: 18,
                          color: _error != null
                              ? context.colors.error
                              : context.colors.online,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error ?? _saved!,
                            style: context.typo.footnote.copyWith(
                              color: _error != null
                                  ? context.colors.error
                                  : context.colors.online,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                PrimaryButton(
                  label: 'Check & save',
                  onPressed: _saving ? null : _save,
                ),
                const SizedBox(height: 8),
                SecondaryButton(
                  label: 'Use community relay',
                  onPressed: _saving ? null : () => _save(community: true),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class RelayReachabilityDot extends StatelessWidget {
  const RelayReachabilityDot({super.key, required this.status});
  final SettingsRelayStatus status;

  @override
  Widget build(BuildContext context) => status == SettingsRelayStatus.failed
      ? Semantics(
          label: 'Relay unreachable',
          child: Icon(
            LucideIcons.circleAlert,
            size: 20,
            color: context.colors.error,
          ),
        )
      : StatusDot(
          status: status == SettingsRelayStatus.reachable
              ? AgentStatus.online
              : AgentStatus.checking,
        );
}
