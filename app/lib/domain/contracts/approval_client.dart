import 'package:app/protocol/protocol.dart';

class BoundApproval {
  const BoundApproval({
    required this.request,
    required this.peerEpk,
    required this.roomId,
  });
  final PerchToolApprovalRequest request;
  final String peerEpk;
  final String roomId;
}

abstract interface class ApprovalClient {
  Stream<void> get changes;
  List<BoundApproval> approvalsFor(String peerEpk, String roomId);
  BoundApproval? resolveNotification(Map<String, dynamic> payload);
  Future<void> decide(BoundApproval approval, PerchApprovalDecision decision);
}
