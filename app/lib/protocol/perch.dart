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

class PerchToolApprovalRequest extends ServerMessage {
  PerchToolApprovalRequest._(this._json);
  final Map<String, dynamic> _json;
  String get id => _json['id'] as String;
  String get owner => _json['owner'] as String;
  String get sessionId => _json['session_id'] as String;
  String get toolCallId => _json['tool_call_id'] as String;
  String get tool => _json['tool'] as String;
  Map<String, dynamic> get args => _json['args'] as Map<String, dynamic>;
  String get argsDigest => _json['args_digest'] as String;
  DateTime get expiresAt =>
      DateTime.fromMillisecondsSinceEpoch(_json['expires_at'] as int);
  bool isExpired(DateTime now) => !now.isBefore(expiresAt);

  factory PerchToolApprovalRequest.fromJson(Map<String, dynamic> j) {
    _checkPerchVersion(j);
    for (final key in ['id', 'owner', 'session_id', 'tool_call_id', 'tool']) {
      if (j[key] is! String || (j[key] as String).isEmpty) {
        throw const FormatException('Invalid approval binding');
      }
    }
    if (j['args'] is! Map<String, dynamic> ||
        j['expires_at'] is! int ||
        j['args_digest'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(j['args_digest'] as String)) {
      throw const FormatException('Invalid approval arguments or expiry');
    }
    Object? freeze(Object? value) {
      if (value is Map<String, dynamic>) {
        return Map<String, dynamic>.unmodifiable(
          value.map((k, v) => MapEntry(k, freeze(v))),
        );
      }
      if (value is List) return List<Object?>.unmodifiable(value.map(freeze));
      return value;
    }

    return PerchToolApprovalRequest._(freeze(j) as Map<String, dynamic>);
  }
}

enum PerchApprovalDecision { allow, deny }

class PerchToolApprovalDecision extends ClientMessage {
  PerchToolApprovalDecision({required this.request, required this.decision});
  final PerchToolApprovalRequest request;
  final PerchApprovalDecision decision;
  @override
  Map<String, dynamic> toJson() => {
    'type': 'perch_tool_approval_decision',
    'id': request.id,
    'version': 1,
    'owner': request.owner,
    'session_id': request.sessionId,
    'tool_call_id': request.toolCallId,
    'args_digest': request.argsDigest,
    'decision': decision.name,
  };
}

enum PerchPushEnvironment { sandbox, production }

class PerchPushRegister extends ClientMessage {
  PerchPushRegister({
    required this.id,
    required this.owner,
    required this.token,
    required this.environment,
    this.unregister = false,
  });
  final String id;
  final String owner;
  final String token;
  final PerchPushEnvironment environment;
  final bool unregister;
  @override
  Map<String, dynamic> toJson() => {
    'type': unregister ? 'perch_push_unregister' : 'perch_push_register',
    'id': id,
    'version': 1,
    'owner': owner,
    'token': token,
    'environment': environment.name,
  };
}

class PerchPushResult extends ServerMessage {
  PerchPushResult({required this.id, required this.registered});
  final String id;
  final bool registered;
  factory PerchPushResult.fromJson(Map<String, dynamic> j) {
    _checkPerchVersion(j);
    return PerchPushResult(
      id: j['id'] as String,
      registered: j['registered'] as bool,
    );
  }
}
