enum RelayCheckFailure { unreachable, timeout }

class RelayCheckResult {
  const RelayCheckResult.reachable(this.elapsed) : failure = null;
  const RelayCheckResult.failed(this.failure) : elapsed = null;

  final Duration? elapsed;
  final RelayCheckFailure? failure;
}

abstract class RelayReachability {
  Future<RelayCheckResult> check(String url);
}
