import '../entities/agent_timeline.dart';
import 'repository.dart';

abstract class TimelineReader extends Repository {
  TimelineConnection get connection;
  Stream<TimelineConnection> get connections;
  Future<List<TimelineMachine>> machines();
  Future<void> selectMachine(String id);
  Future<bool> isSupported();
  Future<AgentSnapshot> snapshot();
  Future<AgentEventPage> events({
    required String epoch,
    required int cursor,
    int waitMs = 25000,
  });
}
