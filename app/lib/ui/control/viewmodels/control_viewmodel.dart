import 'dart:async';

import 'package:app/domain/contracts/control_client.dart';
import 'package:app/domain/entities/perch_control.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';
import '../states/control_state.dart';

class ControlViewModel extends ViewModel<ControlData> {
  ControlViewModel(this._client) : super(ControlData()) {
    _subscription = _client.connections.listen((_) {
      _generation++;
      emit(ControlData());
      unawaited(refresh());
    });
    unawaited(refresh());
  }
  final ControlClient _client;
  late final StreamSubscription<void> _subscription;
  int _generation = 0;
  bool _disposed = false;
  String get machineLabel => _client.machineLabel;
  bool _valid(int generation) => !_disposed && generation == _generation;

  ControlData _copy({
    bool busy = false,
    bool? ready,
    String? message,
    ControlAction? retry,
  }) => ControlData(
    busy: busy,
    ready: ready ?? state.ready,
    message: message,
    retry: retry,
    revision: state.revision,
    updatedAt: state.updatedAt,
    capabilities: state.capabilities,
    daemons: state.daemons,
    jobs: state.jobs,
    log: state.log,
    logJobId: state.logJobId,
  );

  Future<void> refresh({String? notice}) async {
    if (_disposed || state.busy) return;
    final generation = ++_generation;
    emit(_copy(busy: true, ready: false, message: notice));
    try {
      final caps = await _client.capabilities();
      if (!_valid(generation)) return;
      final daemons = caps.methods.contains('daemon.list')
          ? await _client.execute(_client.action('daemon.list', {}, null))
          : null;
      if (!_valid(generation)) return;
      final jobs = caps.methods.contains('cron.list')
          ? await _client.execute(
              _client.action('cron.list', {}, daemons?.revision),
            )
          : null;
      if (!_valid(generation)) return;
      emit(
        ControlData(
          ready: true,
          capabilities: caps,
          revision: jobs?.revision ?? daemons?.revision,
          daemons: [
            for (final raw in daemons?.data['daemons'] as List? ?? [])
              ControlDaemon.fromJson(raw as Map<String, dynamic>),
          ],
          jobs: [
            for (final raw in jobs?.data['jobs'] as List? ?? [])
              ControlCron.fromJson(raw as Map<String, dynamic>),
          ],
          updatedAt: DateTime.now(),
          message: notice,
        ),
      );
    } on ControlFailure catch (error) {
      if (_valid(generation)) _failure(error);
    } on FormatException {
      if (_valid(generation)) {
        _failure(const ControlFailure('internal', 'Invalid response'));
      }
    } on TypeError {
      if (_valid(generation)) {
        _failure(const ControlFailure('internal', 'Invalid response'));
      }
    }
  }

  void _failure(ControlFailure error, {ControlAction? retry}) {
    if (error.disabled) {
      emit(
        ControlData(
          disabled: true,
          message: 'Remote control not enabled on this Mac',
        ),
      );
    } else {
      emit(
        _copy(
          ready: false,
          message: error.unknown
              ? 'Result unknown, refresh'
              : error.code == 'conflict'
              ? 'State changed, refresh'
              : 'Control request failed (${error.code})',
          retry: error.unknown ? retry : null,
        ),
      );
    }
  }

  Future<void> perform(String method, Map<String, dynamic> params) async {
    if (!state.can(method)) return;
    await _execute(_client.action(method, params, state.revision));
  }

  Future<void> retry() async {
    final action = state.retry;
    if (action == null || state.busy) return;
    await _execute(action);
  }

  Future<void> _execute(ControlAction action) async {
    final generation = _generation;
    emit(_copy(busy: true));
    try {
      final reply = await _client.execute(action);
      if (!_valid(generation)) return;
      if (action.method == 'cron.log') {
        emit(
          ControlData(
            ready: true,
            revision: reply.revision,
            capabilities: state.capabilities,
            daemons: state.daemons,
            jobs: state.jobs,
            updatedAt: state.updatedAt,
            logJobId: action.params['job_id'] as String,
            log: [
              for (final raw in reply.data['entries'] as List)
                ControlLogEntry.fromJson(raw as Map<String, dynamic>),
            ],
          ),
        );
      } else {
        emit(_copy(ready: false));
        // Read fresh state even after an acknowledged mutation; cron.run's
        // delivery result is never presented as task completion.
        await refresh();
      }
    } on ControlFailure catch (error) {
      if (!_valid(generation)) return;
      _failure(error, retry: action);
      if (error.code == 'conflict') {
        await refresh(
          notice: 'State changed; refreshed. Review before another action.',
        );
      }
    } on FormatException {
      if (_valid(generation)) {
        _failure(
          const ControlFailure('internal', 'Invalid response'),
          retry: action,
        );
      }
    } on TypeError {
      if (_valid(generation)) {
        _failure(
          const ControlFailure('internal', 'Invalid response'),
          retry: action,
        );
      }
    }
  }

  Future<void> addCron(String daemonId, String schedule, String prompt) async {
    final error = validateControlCron(
      schedule,
      prompt,
      state.capabilities?.maxPromptChars ?? 8192,
    );
    if (error != null) {
      emit(_copy(message: error));
      return;
    }
    await perform('cron.add', {
      'daemon_id': daemonId,
      'schedule': schedule.trim(),
      'prompt': prompt,
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _subscription.cancel();
    super.dispose();
  }
}
