import 'package:app/data/transport/relay_config.dart';
import 'package:app/ui/core/interaction_feedback.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/core/widgets/widgets.dart';
import 'package:app/ui/settings/states/settings_state.dart';
import 'package:app/ui/settings/viewmodels/settings_viewmodel.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

class RelayPage extends StatefulWidget {
  const RelayPage({super.key});
  @override
  State<RelayPage> createState() => _RelayPageState();
}

class _RelayPageState extends State<RelayPage> {
  late final TextEditingController _controller;
  late String _current;
  String _ownDraft = '';
  bool _community = false;
  bool _saving = false;
  String? _error;
  String? _saved;

  @override
  void initState() {
    super.initState();
    _current = context.read<SettingsViewModel>().effectiveRelayUrl;
    _community = _current == kDefaultRelayUrl;
    _ownDraft = _community ? '' : _current;
    _controller = TextEditingController(text: _current);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _select(bool community) {
    if (_saving || community == _community) return;
    InteractionFeedback.selection();
    setState(() {
      if (!_community) _ownDraft = _controller.text;
      _community = community;
      _controller.text = community ? kDefaultRelayUrl : _ownDraft;
      _error = null;
      _saved = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final draft = _controller.text.trim();
    final uri = Uri.tryParse(draft);
    if (uri == null ||
        !['https', 'http', 'wss', 'ws'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      setState(
        () => _error = 'Enter a relay URL, such as https://relay.example.com.',
      );
      InteractionFeedback.result();
      return;
    }
    if (draft != _current) {
      final confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Switch relay?'),
          content: Text(
            'Your Mac must use ${uri.host} too. Until you change it there, its agents may appear offline.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Check & switch'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _saved = null;
    });
    InteractionFeedback.action();
    final vm = context.read<SettingsViewModel>();
    final error = await vm.saveRelayUrl(draft);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
      if (error == null) {
        _current = vm.effectiveRelayUrl;
        _saved = vm.state.relay.message ?? 'Relay saved and reachable';
      }
    });
    InteractionFeedback.result();
    if (error == null) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted) Navigator.of(context).pop();
    }
  }

  Widget _choice(bool community, String title, String subtitle) =>
      CupertinoButton(
        minimumSize: const Size(44, 64),
        padding: const EdgeInsets.all(16),
        onPressed: _saving ? null : () => _select(community),
        child: Row(
          children: [
            Icon(
              _community == community
                  ? LucideIcons.circleCheck
                  : LucideIcons.circle,
              color: context.colors.accent,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.typo.headline),
                  Text(
                    subtitle,
                    style: context.typo.footnote.copyWith(
                      color: context.colors.ink2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.bg,
    body: CustomScrollView(
      slivers: [
        CupertinoSliverNavigationBar(
          backgroundColor: context.colors.bg,
          border: null,
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Icon(LucideIcons.chevronLeft, semanticLabel: 'Back'),
          ),
          automaticallyImplyLeading: false,
          largeTitle: Text('Relay', style: context.typo.largeTitle),
        ),
        SliverSafeArea(
          top: false,
          sliver: SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList.list(
              children: [
                Text(
                  'The relay passes messages between this phone and your Mac.',
                  style: context.typo.body,
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Who can read them', style: context.typo.headline),
                      const SizedBox(height: 8),
                      Text(
                        'TLS protects the connection, but messages are not end-to-end encrypted. The relay operator can read them. Choose one you run or trust.',
                        style: context.typo.footnote.copyWith(
                          color: context.colors.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      _choice(
                        false,
                        'My own relay',
                        'Self-hosted or on your private network',
                      ),
                      _choice(
                        true,
                        'Community relay',
                        'Shared service, operated by someone else',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('Relay URL', style: context.typo.headline),
                const SizedBox(height: 12),
                CupertinoTextField(
                  controller: _controller,
                  enabled: !_saving && !_community,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  placeholder: 'https://relay.example.com',
                  style: context.typo.mono.copyWith(fontSize: 16),
                  padding: const EdgeInsets.all(14),
                  suffix: _community
                      ? null
                      : CupertinoButton(
                          minimumSize: const Size(44, 44),
                          padding: const EdgeInsets.all(10),
                          onPressed: _saving
                              ? null
                              : () async {
                                  final data = await Clipboard.getData(
                                    Clipboard.kTextPlain,
                                  );
                                  if (!mounted || data?.text == null) return;
                                  setState(() {
                                    _controller.text = data!.text!.trim();
                                    _error = null;
                                    _saved = null;
                                  });
                                },
                          child: const Icon(
                            LucideIcons.clipboardPaste,
                            size: 20,
                            semanticLabel: 'Paste relay URL',
                          ),
                        ),
                  decoration: BoxDecoration(
                    color: context.colors.surface2,
                    borderRadius: BorderRadius.circular(14),
                    border: _error == null
                        ? null
                        : Border.all(color: context.colors.error),
                  ),
                  onChanged: (_) => setState(() {
                    _error = null;
                    _saved = null;
                  }),
                ),
                const SizedBox(height: 12),
                Text(
                  'Every paired Mac must use this same relay.',
                  style: context.typo.footnote.copyWith(
                    color: context.colors.ink2,
                  ),
                ),
                const SizedBox(height: 20),
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        CupertinoActivityIndicator(),
                        SizedBox(width: 12),
                        Text('Checking relay…'),
                      ],
                    ),
                  ),
                if (_error != null || _saved != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error != null
                            ? '$_error\nYour current relay is unchanged.'
                            : _saved!,
                        style: context.typo.footnote.copyWith(
                          color: _error != null
                              ? context.colors.error
                              : context.colors.online,
                        ),
                      ),
                    ),
                  ),
                PrimaryButton(
                  label: _saving
                      ? 'Checking…'
                      : _error != null
                      ? 'Try again'
                      : _controller.text.trim() == _current
                      ? 'Check again'
                      : 'Check & save',
                  onPressed: _saving ? null : _save,
                ),
                if (_error != null)
                  SecondaryButton(
                    label: 'Keep current relay',
                    onPressed: () => setState(() {
                      _controller.text = _current;
                      _community = _current == kDefaultRelayUrl;
                      _error = null;
                    }),
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
