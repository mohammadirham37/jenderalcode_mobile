import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config.dart';
import 'crypto/keypair.dart';
import 'relay/relay_api.dart';
import 'relay/relay_socket.dart';
import 'rpc/remote_hub.dart';
import 'storage/secure_store.dart';
import '../features/auth/auth_controller.dart';
import '../features/desktops/desktops_controller.dart';

final keyValueStoreProvider =
    Provider<KeyValueStore>((ref) => SecureKeyValueStore());

final storageProvider =
    Provider<AppStorage>((ref) => AppStorage(ref.watch(keyValueStoreProvider)));

final relayApiProvider =
    Provider<RelayApi>((ref) => RelayApi(baseUrl: AppConfig.relayBase));

/// Loads this phone's X25519 key pair, creating and storing one on first use.
Future<DeviceKeyPair> loadOrCreateKeyPair(AppStorage storage) async {
  final stored = await storage.readSecretKey();
  if (stored != null) {
    try {
      return await DeviceKeyPair.fromSecretB64u(stored);
    } catch (_) {
      // Corrupt entry: fall through and make a new identity.
    }
  }
  final kp = await DeviceKeyPair.generate();
  await storage.writeSecretKey(kp.secretB64u);
  return kp;
}

/// The live relay connection while signed in; null when signed out.
final hubProvider = Provider<RemoteHub?>((ref) {
  final session = ref.watch(authProvider).value;
  if (session == null) return null;
  final socket = RelaySocket(
    uri: AppConfig.relaySocketUri,
    token: session.account.deviceToken,
  );
  final hub = RemoteHub(
    socket: socket,
    keys: session.keys,
    selfId: session.account.deviceId,
    desktops: ref.read(desktopsProvider).value ?? const [],
  );
  ref.listen(desktopsProvider, (_, next) {
    final list = next.value;
    if (list != null) hub.setDesktops(list);
  });
  final subs = <StreamSubscription<Object?>>[
    hub.unpaired.listen((id) =>
        ref.read(desktopsProvider.notifier).removeLocal(id)),
    hub.ended.listen((_) =>
        ref.read(authProvider.notifier).signOutLocally(
            reason: 'This phone was signed out or revoked. Sign in again.')),
  ];
  hub.start();
  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
    hub.dispose();
  });
  return hub;
});

/// device_id → online.
final presenceProvider = StreamProvider<Map<String, bool>>((ref) async* {
  final hub = ref.watch(hubProvider);
  if (hub == null) {
    yield const {};
    return;
  }
  yield hub.online;
  yield* hub.presence;
});

final socketStateProvider = StreamProvider<SocketState>((ref) async* {
  final hub = ref.watch(hubProvider);
  if (hub == null) {
    yield SocketState.disconnected;
    return;
  }
  yield hub.socket.state;
  yield* hub.socket.states;
});

/// Dark by default; the user can switch to light or follow the system.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    ref.read(keyValueStoreProvider).read(_key).then((v) {
      final m = ThemeMode.values.where((e) => e.name == v).firstOrNull;
      if (m != null && ref.mounted) state = m;
    }).ignore();
    return ThemeMode.dark;
  }

  void set(ThemeMode m) {
    state = m;
    ref.read(keyValueStoreProvider).write(_key, m.name).ignore();
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
