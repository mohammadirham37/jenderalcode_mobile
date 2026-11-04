import 'dart:convert';

/// Frames the relay sends on `/v1/ws` (docs/protocol.md §5.1).
sealed class RelayFrame {
  const RelayFrame();
}

class ReadyFrame extends RelayFrame {
  const ReadyFrame(this.deviceId, this.peers);
  final String deviceId;

  /// device_id → online.
  final Map<String, bool> peers;
}

class MsgFrame extends RelayFrame {
  const MsgFrame(this.from, this.id, this.body);
  final String from;
  final String id;
  final String body;
}

class PresenceFrame extends RelayFrame {
  const PresenceFrame(this.deviceId, this.online);
  final String deviceId;
  final bool online;
}

class UndeliverableFrame extends RelayFrame {
  const UndeliverableFrame(this.id, this.to, this.reason);
  final String id;
  final String to;

  /// `offline` or `not_paired`.
  final String reason;
}

class UnpairedFrame extends RelayFrame {
  const UnpairedFrame(this.deviceId);
  final String deviceId;
}

class RevokedFrame extends RelayFrame {
  const RevokedFrame();
}

class ErrorFrame extends RelayFrame {
  const ErrorFrame(this.code);
  final String code;
}

/// Parses one text frame; returns null for invalid or unknown frames.
RelayFrame? parseRelayFrame(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final Map<dynamic, dynamic> j = decoded;
  String? s(String k) => j[k] is String ? j[k] as String : null;
  switch (j['t']) {
    case 'ready':
      final peers = <String, bool>{};
      for (final p in (j['peers'] is List ? j['peers'] as List : const [])) {
        if (p is Map && p['device_id'] is String) {
          peers[p['device_id'] as String] = p['online'] == true;
        }
      }
      return ReadyFrame(s('device_id') ?? '', peers);
    case 'msg':
      final from = s('from'), id = s('id'), body = s('body');
      if (from == null || body == null) return null;
      return MsgFrame(from, id ?? '', body);
    case 'presence':
      final id = s('device_id');
      return id == null ? null : PresenceFrame(id, j['online'] == true);
    case 'undeliverable':
      return UndeliverableFrame(s('id') ?? '', s('to') ?? '', s('reason') ?? '');
    case 'unpaired':
      final id = s('device_id');
      return id == null ? null : UnpairedFrame(id);
    case 'revoked':
      return const RevokedFrame();
    case 'error':
      return ErrorFrame(s('error') ?? 'unknown');
  }
  return null;
}
