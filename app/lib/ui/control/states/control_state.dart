import 'package:app/domain/entities/perch_control.dart';

sealed class ControlState {
  const ControlState();
}

final class ControlData extends ControlState {
  ControlData({
    this.busy = false,
    this.ready = false,
    this.disabled = false,
    this.message,
    this.revision,
    this.updatedAt,
    this.retry,
    this.capabilities,
    List<ControlDaemon> daemons = const [],
    List<ControlCron> jobs = const [],
    List<ControlLogEntry>? log,
    this.logJobId,
  }) : daemons = List.unmodifiable(daemons),
       jobs = List.unmodifiable(jobs),
       log = log == null ? null : List.unmodifiable(log);
  final bool busy;
  final bool ready;
  final bool disabled;
  final String? message;
  final int? revision;
  final DateTime? updatedAt;
  final ControlAction? retry;
  final ControlCapabilities? capabilities;
  final List<ControlDaemon> daemons;
  final List<ControlCron> jobs;
  final List<ControlLogEntry>? log;
  final String? logJobId;
  bool can(String method) =>
      ready && !busy && capabilities?.methods.contains(method) == true;
}
