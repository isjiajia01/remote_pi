import 'package:app/data/preferences/preferences.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/core/widgets/widgets.dart';
import 'package:app/ui/home/states/home_state.dart' show machineLabel;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Scaffold;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'new_session_model.dart';

class NewSessionPage extends StatefulWidget {
  const NewSessionPage({
    super.key,
    required this.model,
    required this.storage,
    required this.preferences,
  });
  final NewSessionModel model;
  final PairingStorage storage;
  final Preferences preferences;

  @override
  State<NewSessionPage> createState() => _NewSessionPageState();
}

class _NewSessionPageState extends State<NewSessionPage> {
  NewSessionModel get model => widget.model;
  bool _opening = false;
  String? _openError;

  @override
  void initState() {
    super.initState();
    model.addListener(_changed);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final peers = await widget.storage.listPeers();
      if (mounted) await model.initialize(peers);
    } catch (_) {
      if (mounted) {
        setState(
          () => _openError =
              'Could not load paired machines. Reopen this page to retry.',
        );
      }
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (model.ready && !_opening) _open();
  }

  Future<void> _open() async {
    _opening = true;
    try {
      final peer = model.peer!;
      final session = model.session!;
      final room = session['room_id'] as String;
      await widget.preferences.setSelectedRoom(
        epk: peer.remoteEpk,
        roomId: room,
      );
      await widget.storage.savePeer(peer.copyWith(roomId: room));
      model.connection.switchRoom(room);
      await model.completeOpening();
      if (!mounted) return;
      context.read<SessionSelection>().select(
        peer.remoteEpk,
        room,
        session['name'] as String,
        machineLabel(peer),
        true,
      );
      if (isWideLayout(context)) {
        context.pop();
      } else {
        context.pushReplacement(
          '/chat',
          extra: {
            'title': session['name'],
            'device': machineLabel(peer),
            'online': true,
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _openError =
              'Could not open the new chat. Retry to open the same session.',
        );
      }
      _opening = false;
    }
  }

  @override
  void dispose() {
    model.removeListener(_changed);
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pending = model.hasPending;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: CupertinoNavigationBar(
        backgroundColor: c.bg,
        middle: const Text('New session'),
        trailing: model.busy ? const CupertinoActivityIndicator() : null,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Start a fresh Pi conversation', style: context.typo.title2),
            const SizedBox(height: 8),
            Text(
              'Choose a folder on your Mac. Each session has its own conversation, even in the same folder.',
              style: context.typo.footnote.copyWith(color: c.ink2),
            ),
            const SizedBox(height: 24),
            if (!pending) ...[
              Text('Machine', style: context.typo.headline),
              for (final peer in model.peers)
                _row(
                  machineLabel(peer),
                  icon: CupertinoIcons.desktopcomputer,
                  selected: model.peer?.remoteEpk == peer.remoteEpk,
                  onTap: model.busy ? null : () => model.selectPeer(peer),
                ),
              if (model.peers.isEmpty && !model.busy)
                const Text('Pair a machine from the Agents screen first.'),
              if (model.roots.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Folders', style: context.typo.headline),
                for (final root in model.roots)
                  _row(
                    root['name'] as String,
                    icon: CupertinoIcons.folder,
                    selected: model.root?['id'] == root['id'],
                    onTap: model.busy ? null : () => model.selectRoot(root),
                  ),
              ],
              if (model.root != null) ...[
                const SizedBox(height: 16),
                Text(
                  '${model.root!['name']}${model.path.isEmpty ? '' : ' / ${model.path}'}',
                  style: context.typo.footnote,
                ),
                if (model.path.isNotEmpty)
                  _row(
                    'Parent folder',
                    icon: CupertinoIcons.arrow_up,
                    onTap: model.busy
                        ? null
                        : () => model.browse(
                            model.path
                                .split('/')
                                .take(model.path.split('/').length - 1)
                                .join('/'),
                          ),
                  ),
                for (final folder in model.directories)
                  _row(
                    folder['name'] as String,
                    icon: CupertinoIcons.folder,
                    onTap: model.busy
                        ? null
                        : () => model.browse(folder['relative_path'] as String),
                  ),
                if (model.directories.isEmpty &&
                    !model.busy &&
                    model.error == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('No subfolders. You can start a session here.'),
                  ),
                if (model.nextOffset != null)
                  CupertinoButton(
                    onPressed: model.busy ? null : model.more,
                    child: const Text('Load more folders'),
                  ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'New session in this folder',
                  onPressed: model.busy || model.error != null
                      ? null
                      : model.create,
                ),
              ],
            ] else ...[
              Text(
                model.peer == null
                    ? 'Pending session'
                    : machineLabel(model.peer!),
                style: context.typo.headline,
              ),
              const SizedBox(height: 8),
              Text(
                model.pending!['relative_path'] as String == ''
                    ? 'Root folder'
                    : model.pending!['relative_path'] as String,
              ),
              const SizedBox(height: 16),
              Text(
                model.busy
                    ? 'Starting Pi and waiting for its chat…'
                    : 'Your request is saved. Retry will recover this session.',
              ),
              if (model.session != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Status: ${model.session!['state']}',
                  style: context.typo.footnote,
                ),
                const SizedBox(height: 12),
                if (['failed', 'stopped'].contains(model.session!['state']))
                  CupertinoButton(
                    onPressed: model.busy ? null : model.resolveTerminal,
                    child: const Text('Dismiss finished request'),
                  )
                else
                  CupertinoButton(
                    onPressed: model.busy ? null : model.stop,
                    child: const Text('Stop this session'),
                  ),
              ],
            ],
            if (model.error != null || _openError != null) ...[
              const SizedBox(height: 20),
              Text(
                _openError ?? model.error!,
                style: context.typo.footnote.copyWith(color: c.error),
              ),
            ],
            if (!model.busy &&
                (model.error != null || pending || _openError != null))
              CupertinoButton(
                onPressed: () {
                  setState(() => _openError = null);
                  if (model.ready) {
                    _open();
                  } else {
                    model.retry();
                  }
                },
                child: const Text('Retry'),
              ),
            if (model.busy)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CupertinoActivityIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    String label, {
    required IconData icon,
    bool selected = false,
    VoidCallback? onTap,
  }) => CupertinoButton(
    padding: const EdgeInsets.symmetric(vertical: 14),
    onPressed: onTap,
    child: Row(
      children: [
        Icon(icon, size: 22, color: context.colors.ink2),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: context.typo.body)),
        Icon(
          selected ? CupertinoIcons.check_mark : CupertinoIcons.chevron_right,
          size: 18,
          color: context.colors.ink2,
        ),
      ],
    ),
  );
}
