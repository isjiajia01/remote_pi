/// Read-only inventory and delivery audit for a single local broker.
class BrokerAgent {
  const BrokerAgent({
    required this.cwd,
    required this.name,
    required this.address,
  });
  final String cwd;
  final String name;
  final String address;
}

class AgentSnapshot {
  AgentSnapshot({
    required this.epoch,
    required this.revision,
    required this.cursor,
    required List<BrokerAgent> agents,
  }) : agents = List.unmodifiable(agents);
  final String epoch;
  final int revision;
  final int cursor;
  final List<BrokerAgent> agents;
}

class AgentEvent {
  AgentEvent({
    required this.cursor,
    required this.ts,
    required this.type,
    this.agent,
    this.id,
    this.re,
    this.from,
    this.to,
    List<String> delivered = const [],
    this.ackStatus,
    this.via,
  }) : delivered = List.unmodifiable(delivered);
  final int cursor;
  final DateTime ts;
  final String type;
  final BrokerAgent? agent;

  /// Message id; distinct deliveries may share it. Event identity is epoch/cursor.
  final String? id;
  final String? re;
  final String? from;
  final String? to;
  final List<String> delivered;
  final String? ackStatus;
  final String? via;

  String get actor => from ?? agent?.address ?? 'Agent';
  String get target => to ?? 'Local broker';
  String get verb => switch (type) {
    'peer_joined' => 'joined',
    'peer_left' => 'left',
    'routed' when ackStatus == 'received' => 'delivered',
    'routed' => 'routed · ${ackStatus ?? 'unknown'}',
    _ => type,
  };
}

class AgentEventPage {
  AgentEventPage({
    required this.epoch,
    required this.cursor,
    required List<AgentEvent> events,
    required this.resyncRequired,
  }) : events = List.unmodifiable(events);
  final String epoch;
  final int cursor;
  final List<AgentEvent> events;
  final bool resyncRequired;
}

class TimelineMachine {
  const TimelineMachine(this.id, this.label);
  final String id;
  final String label;
}

class TimelineConnection {
  const TimelineConnection({
    required this.key,
    required this.machineId,
    required this.label,
    required this.online,
  });
  final String key;
  final String? machineId;
  final String label;
  final bool online;
}

class PerchReadFailure implements Exception {
  const PerchReadFailure(this.code, this.message);
  final String code;
  final String message;
}
