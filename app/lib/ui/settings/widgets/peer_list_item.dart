import 'package:app/pairing/storage.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/core/widgets/widgets.dart';
import 'package:flutter/cupertino.dart';

/// Configuration row: tap to rename, swipe or use the trailing removal action.
class PeerListItem extends StatefulWidget {
  const PeerListItem({
    super.key,
    required this.peer,
    required this.status,
    required this.onRevokeRequested,
    required this.onEditNickname,
  });

  final PeerRecord peer;
  final AgentStatus status;
  final Future<bool> Function() onRevokeRequested;
  final VoidCallback onEditNickname;

  @override
  State<PeerListItem> createState() => _PeerListItemState();
}

class _PeerListItemState extends State<PeerListItem> {
  bool _removing = false;

  Future<bool> _remove() async {
    if (_removing) return false;
    _removing = true;
    try {
      return await widget.onRevokeRequested();
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  String get _pairedDate {
    final date = DateTime.tryParse(widget.peer.pairedAt)?.toLocal();
    if (date == null) return 'Paired';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return 'Paired ${date.day} ${months[date.month - 1]}';
  }

  void _showActions() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheet) => CupertinoActionSheet(
        title: Text(
          (widget.peer.nickname?.isNotEmpty ?? false)
              ? widget.peer.nickname!
              : widget.peer.sessionName,
        ),
        message: Text('${widget.status.label} · $_pairedDate'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(sheet);
              widget.onEditNickname();
            },
            child: const Text('Rename'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(sheet);
              _remove();
            },
            child: const Text('Remove this Mac'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheet),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final peer = widget.peer;
    final name = (peer.nickname?.isNotEmpty ?? false)
        ? peer.nickname!
        : peer.sessionName;
    return Dismissible(
      key: ValueKey('peer-${peer.remoteEpk}'),
      direction: _removing
          ? DismissDirection.none
          : DismissDirection.endToStart,
      // The ViewModel removes the row; never let Dismissible race that rebuild.
      confirmDismiss: (_) async {
        await _remove();
        return false;
      },
      background: ColoredBox(
        color: context.colors.errorSoft,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Remove',
              style: context.typo.headline.copyWith(
                color: context.colors.error,
              ),
            ),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: CupertinoButton(
              padding: const EdgeInsets.fromLTRB(16, 12, 0, 12),
              onPressed: _removing ? null : _showActions,
              child: Row(
                children: [
                  StatusDot(status: widget.status),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: context.typo.headline,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        if (name != peer.sessionName)
                          Text(
                            peer.sessionName,
                            style: context.typo.monoSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.status.label} · $_pairedDate',
                          style: context.typo.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_removing)
            Padding(
              padding: const EdgeInsets.all(16),
              child: CupertinoActivityIndicator(
                radius: 8,
                color: context.colors.accent,
              ),
            )
          else
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(44, 44),
              onPressed: _showActions,
              child: Semantics(
                label: 'Manage $name',
                excludeSemantics: true,
                child: Text(
                  'Details',
                  style: context.typo.body.copyWith(
                    color: context.colors.error,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
