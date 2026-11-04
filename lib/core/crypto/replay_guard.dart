/// Messages whose timestamp is further than this from now are dropped.
const int maxSkewMs = 60000;

/// How long a message id is remembered for replay detection.
const int replayWindowMs = 120000;

/// Remembers recently seen message ids (docs/protocol.md §3.4).
class ReplayGuard {
  final Map<String, int> _seen = {};

  /// Number of remembered ids (for tests).
  int get size => _seen.length;
  bool remembers(String mid) => _seen.containsKey(mid);

  /// Throws [ReplayRejected] for a stale timestamp or a replayed `mid`.
  void check(String mid, int ts, int nowMs) {
    if ((nowMs - ts).abs() > maxSkewMs) {
      throw const ReplayRejected('message timestamp outside the allowed window');
    }
    _seen.removeWhere((_, at) => nowMs - at > replayWindowMs);
    if (_seen.containsKey(mid)) {
      throw const ReplayRejected('replayed message');
    }
    _seen[mid] = nowMs;
  }
}

class ReplayRejected implements Exception {
  const ReplayRejected(this.message);
  final String message;
  @override
  String toString() => 'ReplayRejected: $message';
}
