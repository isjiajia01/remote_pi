import 'package:app/domain/entities/agent_timeline.dart';

enum TimelineStatus { loading, ready, offline, stale, unsupported }

sealed class TimelineState {
  const TimelineState();
}

final class TimelineData extends TimelineState {
  TimelineData({
    this.status = TimelineStatus.loading,
    this.machineId,
    this.machineLabel = 'Local broker',
    List<TimelineMachine> machines = const [],
    List<AgentEvent> events = const [],
    List<BrokerAgent> agents = const [],
    this.agentFilter,
    this.lastUpdated,
    this.historyGap = false,
  }) : machines = List.unmodifiable(machines),
       events = List.unmodifiable(events),
       agents = List.unmodifiable(agents);
  final TimelineStatus status;
  final String? machineId;
  final String machineLabel;
  final List<TimelineMachine> machines;
  final List<AgentEvent> events;
  final List<BrokerAgent> agents;
  final String? agentFilter;
  final DateTime? lastUpdated;
  final bool historyGap;
  List<AgentEvent> get visibleEvents => events
      .where(
        (e) =>
            agentFilter == null ||
            e.actor == agentFilter ||
            e.target == agentFilter ||
            e.delivered.contains(agentFilter),
      )
      .toList();
  List<String> get addresses => ({
    for (final agent in agents) agent.address,
    for (final event in events) event.actor,
    for (final event in events) event.target,
  }..remove('Local broker')).toList()..sort();
}
