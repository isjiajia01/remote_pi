part of 'protocol.dart';

class PerchCapabilitiesGet extends ClientMessage {
  PerchCapabilitiesGet({required this.id});
  final String id;
  @override
  Map<String, dynamic> toJson() => {'type': 'perch_capabilities_get', 'id': id};
}

class PerchRequest extends ClientMessage {
  PerchRequest({
    required this.id,
    required this.method,
    this.params = const {},
    this.expectedRevision,
  });
  final String id;
  final String method;
  final Map<String, dynamic> params;
  final int? expectedRevision;
  @override
  Map<String, dynamic> toJson() => {
    'type': 'perch_request',
    'id': id,
    'version': 1,
    'method': method,
    'params': params,
    if (expectedRevision != null) 'expected_revision': expectedRevision,
  };
}

void _checkPerchVersion(Map<String, dynamic> j) {
  if (j['version'] != 1) {
    throw const FormatException('Unsupported Perch version');
  }
}

void _checkPerchScope(Map<String, dynamic> j) {
  if (j['scope'] != 'local_broker' && j['scope'] != 'supervisor') {
    throw const FormatException('Unsupported Perch scope');
  }
}

class PerchCapabilitiesResult extends ServerMessage {
  PerchCapabilitiesResult({
    required this.id,
    required this.methods,
    required this.ackSemantics,
    required this.limits,
    this.scope = 'local_broker',
  });
  final String id;
  final String scope;
  final List<String> methods;
  final String ackSemantics;
  final Map<String, int> limits;
  bool get supportsTimeline =>
      scope == 'local_broker' &&
      methods.contains('agents.list') &&
      methods.contains('agents.events') &&
      ackSemantics == 'delivery_only';
  factory PerchCapabilitiesResult.fromJson(Map<String, dynamic> j) {
    _checkPerchVersion(j);
    _checkPerchScope(j);
    return PerchCapabilitiesResult(
      id: j['id'] as String,
      scope: j['scope'] as String,
      methods: List<String>.unmodifiable(j['methods'] as List),
      ackSemantics: j['ack_semantics'] as String,
      limits: Map.unmodifiable(
        (j['limits'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, (v as num).toInt()),
        ),
      ),
    );
  }
}

BrokerAgent _decodeBrokerAgent(Map<String, dynamic> j) => BrokerAgent(
  cwd: j['cwd'] as String,
  name: j['name'] as String,
  address: j['address'] as String,
);

class PerchResult extends ServerMessage {
  PerchResult({required this.id, required this.method, required this.result});
  final String id;
  final String method;
  final Map<String, dynamic> result;
  factory PerchResult.fromJson(Map<String, dynamic> j) {
    _checkPerchVersion(j);
    final result = j['result'] as Map<String, dynamic>;
    _checkPerchScope(result);
    return PerchResult(
      id: j['id'] as String,
      method: j['method'] as String,
      result: Map.unmodifiable(result),
    );
  }
  ControlReply get control {
    if (result['scope'] != 'supervisor' ||
        result['revision'] is! int ||
        (result['revision'] as int) < 0 ||
        result['data'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid supervisor result');
    }
    return ControlReply(
      result['revision'] as int,
      result['data'] as Map<String, dynamic>,
    );
  }

  AgentSnapshot get snapshot => AgentSnapshot(
    epoch: result['epoch'] as String,
    revision: (result['revision'] as num).toInt(),
    cursor: (result['cursor'] as num).toInt(),
    agents: (result['agents'] as List)
        .map((j) => _decodeBrokerAgent(j as Map<String, dynamic>))
        .toList(),
  );
  AgentEventPage get eventPage => AgentEventPage(
    epoch: result['epoch'] as String,
    cursor: (result['cursor'] as num).toInt(),
    resyncRequired: result['resync_required'] as bool,
    events: (result['events'] as List).map((raw) {
      final j = raw as Map<String, dynamic>;
      return AgentEvent(
        cursor: (j['cursor'] as num).toInt(),
        ts: DateTime.fromMillisecondsSinceEpoch((j['ts'] as num).toInt()),
        type: j['type'] as String,
        agent: j['agent'] == null
            ? null
            : _decodeBrokerAgent(j['agent'] as Map<String, dynamic>),
        id: j['id'] as String?,
        re: j['re'] as String?,
        from: j['from'] as String?,
        to: j['to'] as String?,
        delivered: List<String>.from(j['delivered'] as List? ?? const []),
        ackStatus: j['ack_status'] as String?,
        via: j['via'] as String?,
      );
    }).toList(),
  );
}

class PerchError extends ServerMessage {
  PerchError({required this.id, required this.code, required this.message});
  final String id;
  final String code;
  final String message;
  factory PerchError.fromJson(Map<String, dynamic> j) {
    _checkPerchVersion(j);
    final error = j['error'] as Map<String, dynamic>;
    return PerchError(
      id: j['id'] as String,
      code: error['code'] as String,
      message: error['message'] as String,
    );
  }
}
