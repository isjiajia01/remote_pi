class ControlAction {
  ControlAction(
    this.id,
    this.method,
    Map<String, dynamic> params,
    this.revision,
  ) : params = Map.unmodifiable(params);
  final String id;
  final String method;
  final Map<String, dynamic> params;
  final int? revision;
}

class ControlReply {
  ControlReply(this.revision, Map<String, dynamic> data)
    : data = Map.unmodifiable(data);
  final int revision;
  final Map<String, dynamic> data;
}

class ControlCapabilities {
  ControlCapabilities(Iterable<String> methods, {this.maxPromptChars = 8192})
    : methods = Set.unmodifiable(methods);
  final Set<String> methods;
  final int maxPromptChars;
}

class ControlFailure implements Exception {
  const ControlFailure(this.code, this.message);
  final String code;
  final String message;
  bool get disabled => const ['forbidden', 'unsupported'].contains(code);
  bool get unknown => const ['offline', 'timeout', 'internal'].contains(code);
}

class ControlDaemon {
  const ControlDaemon(this.id, this.name, this.state);
  factory ControlDaemon.fromJson(Map<String, dynamic> json) => ControlDaemon(
    json['id'] as String,
    json['name'] as String,
    json['state'] as String,
  );
  final String id;
  final String name;
  final String state;
}

class ControlCron {
  const ControlCron(
    this.id,
    this.daemonId,
    this.schedule,
    this.prompt,
    this.enabled,
  );
  factory ControlCron.fromJson(Map<String, dynamic> json) => ControlCron(
    json['id'] as String,
    json['daemon_id'] as String,
    json['schedule'] as String,
    json['prompt'] as String,
    json['enabled'] as bool,
  );
  final String id;
  final String daemonId;
  final String schedule;
  final String prompt;
  final bool enabled;
}

class ControlLogEntry {
  const ControlLogEntry(this.time, this.result, this.preview);
  factory ControlLogEntry.fromJson(Map<String, dynamic> json) =>
      ControlLogEntry(
        DateTime.fromMillisecondsSinceEpoch(json['ts'] as int),
        json['result'] as String,
        json['prompt_preview'] as String,
      );
  final DateTime time;
  final String result;
  final String preview;
}

String? validateControlCron(
  String schedule,
  String prompt,
  int maxPromptChars,
) {
  if (schedule.trim().isEmpty || schedule.length > 256) {
    return 'Enter a schedule of 1–256 characters.';
  }
  if (prompt.trim().isEmpty || prompt.length > maxPromptChars) {
    return 'Enter a prompt of 1–$maxPromptChars characters.';
  }
  return null;
}
