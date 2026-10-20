import '../entities/perch_control.dart';
import 'repository.dart';

abstract class ControlClient extends Repository {
  String get connectionKey;
  String get machineLabel;
  Stream<void> get connections;
  Future<ControlCapabilities> capabilities();
  ControlAction action(
    String method,
    Map<String, dynamic> params,
    int? revision,
  );
  Future<ControlReply> execute(ControlAction action);
}
