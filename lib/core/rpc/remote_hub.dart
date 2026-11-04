import 'dart:async';

import 'package:uuid/uuid.dart';

import '../crypto/channel.dart';
import '../crypto/keypair.dart';
import '../crypto/replay_guard.dart';
import '../relay/relay_frames.dart';
import '../relay/relay_socket.dart';
import '../storage/secure_store.dart';
import 'models.dart';
import 'rpc_client.dart';

/// Largest sealed body that fits the relay's 1 MiB frame with its envelope.
const maxBodyBytes = (1 << 20) - 1024;

/// Why the relay session ended for good (the app must sign in again).
enum SessionEnd { revoked, unauthorized }

/// Routes relay frames to one encrypted [RpcClient] per paired desktop.
///
/// Only desktops in the local list (confirmed via QR + SAS) are ever talked
/// to, always with the public key from the QR code. Messages from any other
/// `from`, or that fail decryption / replay checks, are dropped silently.
class RemoteHub {
  RemoteHub({
    required this.socket,
    required this.keys,
    required this.selfId,
    List<PairedDesktop> desktops = const [],
    int Function()? clock,
    this.rpcTimeout = const Duration(seconds: 20),
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    setDesktops(desktops);
    _frameSub = socket.frames.listen(_onFrame);
  }

  final RelaySocket socket;
  final DeviceKeyPair keys;
  final String selfId;
  final Duration rpcTimeout;
  final int Function() _clock;

  final _desktops = <String, PairedDesktop>{};
  final _channels = <String, Future<RemoteChannel>>{};
  final _guards = <String, ReplayGuard>{};
  final _rpcs = <String, RpcClient>{};
  final _online = <String, bool>{};

  final _presence = StreamController<Map<String, bool>>.broadcast();
  final _linkUp = StreamController<String>.broadcast();
  final _unpaired = StreamController<String>.broadcast();
  final _ended = StreamController<SessionEnd>.broadcast();

  late final StreamSubscription<RelayFrame> _frameSub;
  Future<void> _inbound = Future.value();
  Future<void> _outbound = Future.value();

  /// device_id → online, as last reported by the relay.
  Map<String, bool> get online => Map.unmodifiable(_online);
  Stream<Map<String, bool>> get presence => _presence.stream;

  /// A desktop became reachable (after `ready` or a `presence` online):
  /// open screens should re-subscribe and reload.
  Stream<String> get linkUp => _linkUp.stream;

  /// The relay removed the pairing with this device id.
  Stream<String> get unpaired => _unpaired.stream;
  Stream<SessionEnd> get ended => _ended.stream;

  void start() => socket.start();

  void setDesktops(List<PairedDesktop> list) {
    final ids = {for (final d in list) d.deviceId};
    for (final id in _desktops.keys.toList()) {
      if (!ids.contains(id)) {
        _desktops.remove(id);
        _channels.remove(id);
        _guards.remove(id);
        _rpcs.remove(id)?.dispose();
      }
    }
    for (final d in list) {
      final old = _desktops[d.deviceId];
      if (old != null && old.publicKey != d.publicKey) {
        _channels.remove(d.deviceId);
      }
      _desktops[d.deviceId] = d;
    }
  }

  bool isKnown(String deviceId) => _desktops.containsKey(deviceId);

  /// The RPC client for a paired desktop.
  RpcClient rpc(String desktopId) {
    if (!_desktops.containsKey(desktopId)) {
      throw const RpcError('not_paired', 'unknown desktop');
    }
    return _rpcs.putIfAbsent(
      desktopId,
      () => RpcClient(
        transport: (m) => _sendTo(desktopId, m),
        timeout: rpcTimeout,
      ),
    );
  }

  Future<RemoteChannel> _channel(String desktopId) {
    final d = _desktops[desktopId];
    if (d == null) return Future.error(const RpcError('not_paired'));
    return _channels.putIfAbsent(
      desktopId,
      () => RemoteChannel.create(
        own: keys,
        peerPublic: publicKeyFromB64u(d.publicKey),
        side: Side.mobile,
        desktopId: desktopId,
        mobileId: selfId,
      ),
    );
  }

  /// Seals and sends in call order; returns the relay envelope id.
  Future<String> _sendTo(String desktopId, Json m) {
    final done = Completer<String>();
    _outbound = _outbound.then((_) async {
      try {
        final ch = await _channel(desktopId);
        final body = await ch.sealApp(m, _clock());
        // The relay closes the connection on a frame over 1 MiB.
        if (body.length > maxBodyBytes) {
          throw const RpcError('too_large', 'This message is too large to send. Attach fewer or smaller images.');
        }
        final env = const Uuid().v4();
        if (!socket.sendMsg(to: desktopId, id: env, body: body)) {
          throw const RpcError('offline');
        }
        done.complete(env);
      } catch (e) {
        done.completeError(e is RpcError ? e : RpcError('offline', '$e'));
      }
    });
    return done.future;
  }

  void _onFrame(RelayFrame f) {
    switch (f) {
      case ReadyFrame(:final peers):
        _online
          ..clear()
          ..addAll(peers);
        _presence.add(online);
        for (final id in _desktops.keys) {
          if (_online[id] == true) _linkUp.add(id);
        }
      case PresenceFrame(:final deviceId, online: final on):
        final was = _online[deviceId] == true;
        _online[deviceId] = on;
        _presence.add(online);
        if (on && !was && _desktops.containsKey(deviceId)) {
          _linkUp.add(deviceId);
        }
      case MsgFrame():
        // Decrypt strictly in arrival order so deltas stay ordered.
        _inbound = _inbound.then((_) => _handleMsg(f));
      case UndeliverableFrame(:final id, :final to, :final reason):
        _rpcs[to]?.handleUndeliverable(id, reason);
      case UnpairedFrame(:final deviceId):
        _online.remove(deviceId);
        _presence.add(online);
        _unpaired.add(deviceId);
      case RevokedFrame():
        _endAll(SessionEnd.revoked);
      case ErrorFrame(:final code):
        if (code == 'unauthorized' || code == 'forbidden') {
          _endAll(SessionEnd.unauthorized);
        }
    }
  }

  Future<void> _handleMsg(MsgFrame f) async {
    if (!_desktops.containsKey(f.from)) return;
    try {
      final ch = await _channel(f.from);
      final guard = _guards.putIfAbsent(f.from, ReplayGuard.new);
      final m = await ch.openApp(f.body, _clock(), guard);
      rpc(f.from).handleMessage(m);
    } catch (_) {
      // §3.4: drop silently.
    }
  }

  void _endAll(SessionEnd why) {
    for (final r in _rpcs.values) {
      r.failAll(const RpcError('offline'));
    }
    if (!_ended.isClosed) _ended.add(why);
  }

  /// Wait until queued inbound frames are processed (tests).
  Future<void> drain() async {
    await _inbound;
    await _outbound;
  }

  Future<void> dispose() async {
    await _frameSub.cancel();
    for (final r in _rpcs.values) {
      await r.dispose();
    }
    _rpcs.clear();
    await socket.dispose();
    await _presence.close();
    await _linkUp.close();
    await _unpaired.close();
    await _ended.close();
  }
}
