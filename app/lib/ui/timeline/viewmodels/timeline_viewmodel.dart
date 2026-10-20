import 'dart:async';

import 'package:app/domain/contracts/timeline_reader.dart';
import 'package:app/domain/entities/agent_timeline.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';
import '../states/timeline_state.dart';

class TimelineViewModel extends ViewModel<TimelineData> {
  TimelineViewModel(this._reader) : super(TimelineData()) {
    _subscription = _reader.connections.listen(_onConnection);
    unawaited(_loadMachines());
    _onConnection(_reader.connection);
  }
  final TimelineReader _reader;
  late final StreamSubscription<TimelineConnection> _subscription;
  final _events = <String, AgentEvent>{};
  List<BrokerAgent> _agents = [];
  List<TimelineMachine> _machines = [];
  TimelineConnection? _connection;
  String? _epoch;
  int? _cursor;
  bool? _supported;
  bool _active = false;
  bool _disposed = false;
  bool _historyGap = false;
  int _generation = 0;
  int? _running;
  Timer? _retry;
  DateTime? _lastUpdated;
  String? _agentFilter;

  Future<void> _loadMachines() async {
    _machines = await _reader.machines();
    if (!_disposed) _publish(state.status);
  }

  void _onConnection(TimelineConnection next) {
    if (_disposed) return;
    final changed = _connection?.key != next.key;
    _connection = next;
    _generation++;
    _retry?.cancel();
    if (changed) {
      _events.clear();
      _agents = [];
      _epoch = null;
      _cursor = null;
      _lastUpdated = null;
      _agentFilter = null;
      _historyGap = false;
    }
    _supported = null;
    _publish(
      next.online
          ? (_lastUpdated == null
                ? TimelineStatus.loading
                : TimelineStatus.stale)
          : TimelineStatus.offline,
    );
    _start();
  }

  void setActive(bool active) {
    if (_disposed || active == _active) return;
    _active = active;
    _retry?.cancel();
    // A pending read may complete while hidden; it can update cache but cannot
    // open another long poll until the Timeline is visible again.
    if (active) {
      if (_lastUpdated != null &&
          _connection?.online == true &&
          _supported != false) {
        _publish(TimelineStatus.stale);
      }
      _start();
    }
  }

  bool _valid(int generation) => !_disposed && generation == _generation;

  void _start() {
    if (!_active ||
        _disposed ||
        _connection?.online != true ||
        _supported == false ||
        _running == _generation) {
      return;
    }
    final generation = _generation;
    _running = generation;
    unawaited(_run(generation));
  }

  Future<void> _run(int generation) async {
    try {
      if (_supported == null) {
        final supported = await _reader.isSupported();
        if (!_valid(generation)) return;
        _supported = supported;
        if (!supported) {
          _publish(TimelineStatus.unsupported);
          return;
        }
      }
      if (_epoch == null) {
        final snapshot = await _reader.snapshot();
        if (!_valid(generation)) return;
        _applySnapshot(snapshot);
      }
      while (_valid(generation) && _active && _connection!.online) {
        final page = await _reader.events(epoch: _epoch!, cursor: _cursor!);
        if (!_valid(generation)) return;
        if (page.resyncRequired ||
            page.epoch != _epoch ||
            page.cursor < _cursor!) {
          _historyGap = true;
          _publish(TimelineStatus.stale);
          final snapshot = await _reader.snapshot();
          if (!_valid(generation)) return;
          _applySnapshot(snapshot);
          continue;
        }
        for (final event in page.events) {
          // The wire has no separate event id. Epoch/cursor identifies one
          // audit record; message ids can be reused across separate deliveries.
          final eventId = '${page.epoch}:${event.cursor}';
          if (_events.containsKey(eventId)) continue;
          _events[eventId] = event;
          final agent = event.agent;
          if (agent != null) {
            _agents.removeWhere((a) => a.address == agent.address);
            if (event.type == 'peer_joined') _agents.add(agent);
          }
        }
        _cursor = page.cursor;
        _lastUpdated = DateTime.now();
        _publish(TimelineStatus.ready);
      }
    } on PerchReadFailure catch (error) {
      if (!_valid(generation)) return;
      if (error.code == 'unsupported') {
        _supported = false;
        _publish(TimelineStatus.unsupported);
      } else {
        _publish(
          _connection?.online == true
              ? TimelineStatus.stale
              : TimelineStatus.offline,
        );
        _retry = Timer(const Duration(seconds: 5), _start);
      }
    } on FormatException {
      if (_valid(generation)) _publish(TimelineStatus.stale);
    } finally {
      if (_running == generation) _running = null;
    }
  }

  void _applySnapshot(AgentSnapshot snapshot) {
    if (_epoch != snapshot.epoch) _events.clear();
    _epoch = snapshot.epoch;
    _cursor = snapshot.cursor;
    _agents = snapshot.agents.toList();
    _lastUpdated = DateTime.now();
    _publish(TimelineStatus.ready);
  }

  void _publish(TimelineStatus status) {
    if (_disposed) return;
    final events = _events.values.toList()
      ..sort((a, b) {
        final byTime = b.ts.compareTo(a.ts);
        return byTime != 0 ? byTime : b.cursor.compareTo(a.cursor);
      });
    emit(
      TimelineData(
        status: status,
        machineId: _connection?.machineId,
        machineLabel: _connection?.label ?? 'Local broker',
        machines: _machines,
        events: events,
        agents: _agents,
        agentFilter: _agentFilter,
        lastUpdated: _lastUpdated,
        historyGap: _historyGap,
      ),
    );
  }

  void filterAgent(String? address) {
    _agentFilter = address;
    _publish(state.status);
  }

  Future<void> selectMachine(String id) => _reader.selectMachine(id);
  Future<void> refresh() async {
    _supported = null;
    _start();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _retry?.cancel();
    _subscription.cancel();
    super.dispose();
  }
}
