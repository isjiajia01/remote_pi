import 'package:app/protocol/protocol.dart';

/// Where a room's Pi process came from. Encoded in the room id by the
/// extension because the relay forwards only a fixed room_meta field set
/// (docs/agents-page-design.md § Protocol):
///   `session-<uuid>`               phone-created session (perch-sessiond)
///   `sub.<hash>[.<parentRoomId>]`  pi-subagents child run
///   anything else                  terminal/daemon main session
/// Old extensions never emit `sub.`, so their child runs read as terminal
/// sessions (fallback: titled "Terminal N" from the `#N` name suffix).
enum RoomOrigin { terminal, phone, subagent }

class RoomKind {
  const RoomKind(this.origin, {this.parentRoomId, this.phoneSessionId});
  final RoomOrigin origin;

  /// Sub-agent only: the main room that launched it, when the parent
  /// extension exported one.
  final String? parentRoomId;

  /// Phone sessions only: the perch-sessiond `session_id` (for sessions.stop).
  final String? phoneSessionId;

  bool get isSubagent => origin == RoomOrigin.subagent;
  bool get isPhone => origin == RoomOrigin.phone;
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

RoomKind roomKindOf(String roomId) {
  if (roomId.startsWith('sub.')) {
    final rest = roomId.substring(4);
    final dot = rest.indexOf('.');
    final parent = dot < 0 ? null : rest.substring(dot + 1);
    return RoomKind(
      RoomOrigin.subagent,
      parentRoomId: (parent?.isEmpty ?? true) ? null : parent,
    );
  }
  if (roomId.startsWith('session-')) {
    final id = roomId.substring(8);
    if (_uuid.hasMatch(id)) {
      return RoomKind(RoomOrigin.phone, phoneSessionId: id);
    }
  }
  return const RoomKind(RoomOrigin.terminal);
}

String? _projectOf(RoomInfo room) =>
    room.cwd?.split('/').where((s) => s.isNotEmpty).lastOrNull;

// perch-sessiond names new sessions `<folder>-<uuid>`.
final _autoPhoneName = RegExp(
  r'-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final _ordinal = RegExp(r'^(.*)#(\d+)$');

/// Row title inside a project card. The project name is the card header, so
/// generated names collapse to their origin ("Terminal", "Terminal 2",
/// "Phone session · 000f", "Sub-agent 3"). User-chosen names win.
String sessionTitle(RoomInfo room) {
  final kind = roomKindOf(room.roomId);
  final name = room.name?.trim() ?? '';
  final project = _projectOf(room);
  final ordinal = _ordinal.firstMatch(name);
  final base = ordinal?.group(1) ?? name;
  final n = ordinal?.group(2);
  final generated = name.isEmpty || base == project;
  switch (kind.origin) {
    case RoomOrigin.phone:
      if (name.isEmpty || _autoPhoneName.hasMatch(name)) {
        return 'Phone session · ${kind.phoneSessionId!.substring(0, 4)}';
      }
      return name;
    case RoomOrigin.subagent:
      if (generated) return n == null ? 'Sub-agent' : 'Sub-agent $n';
      return name;
    case RoomOrigin.terminal:
      if (generated) return n == null ? 'Terminal' : 'Terminal $n';
      // A perch-sessiond name on a non-`session-` room (older daemon/cache).
      final auto = _autoPhoneName.firstMatch(name);
      if (auto != null && name.substring(0, auto.start) == project) {
        return 'Phone session · ${name.substring(auto.start + 1, auto.start + 5)}';
      }
      return name;
  }
}

const _tiers = {
  'std': 'Standard',
  'standard': 'Standard',
  'code': 'Code',
  'fast': 'Fast',
  'deep': 'Deep',
  'scout': 'Scout',
  'research': 'Research',
  'oracle': 'Oracle',
  'review': 'Review',
  'design': 'Design',
  'vision': 'Vision',
  // Pi model display names for the same routing tiers (~/.pi models.json
  // `name`, announced verbatim in room_meta.model). The app is English, so
  // they read as the same tier words instead of raw '标准'.
  '标准': 'Standard',
  '编码': 'Code',
  '快速': 'Fast',
  '深度': 'Deep',
  '侦察': 'Scout',
  '调研': 'Research',
  '顾问': 'Oracle',
  '审查': 'Review',
  '设计': 'Design',
  '视觉': 'Vision',
};

/// One label per model regardless of whether the Pi announced a display name
/// or a raw id: drop provider/group path, `model-`/`claude-` prefixes and
/// date stamps; routing tiers (`group/std`, or its display name `标准`) read
/// as their tier word. Other display names are kept as is.
/// Returns (label, isId) — ids render monospace.
(String, bool) friendlyModel(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return ('', false);
  final named = _tiers[value];
  if (named != null) return (named, false);
  final idLike = RegExp(r'^[A-Za-z0-9._:/-]+$').hasMatch(value);
  if (!idLike) return (value, false); // display name, e.g. "Claude Opus · 5.5"
  var last = value.split('/').last;
  final tier = _tiers[last.toLowerCase()];
  if (tier != null) return (tier, false);
  last = last
      .replaceFirst(RegExp(r'^model-'), '')
      .replaceFirst(RegExp(r'^claude-'), '')
      .replaceFirst(RegExp(r'-\d{8}$'), '');
  return (last, true);
}
