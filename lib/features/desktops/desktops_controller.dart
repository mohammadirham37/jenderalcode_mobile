import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/relay/relay_api.dart';
import '../../core/storage/secure_store.dart';
import '../auth/auth_controller.dart';

/// Locally confirmed desktops. Keys always come from the QR code; the relay's
/// peer list is only used for names/presence and to drop removed pairings.
class DesktopsController extends AsyncNotifier<List<PairedDesktop>> {
  @override
  Future<List<PairedDesktop>> build() async {
    final session = ref.watch(authProvider).value;
    if (session == null) return const [];
    return ref.read(storageProvider).readDesktops();
  }

  Future<void> _save(List<PairedDesktop> list) async {
    await ref.read(storageProvider).writeDesktops(list);
    state = AsyncData(list);
  }

  Future<void> add(PairedDesktop d) async {
    final list = [
      for (final e in state.value ?? const <PairedDesktop>[])
        if (e.deviceId != d.deviceId) e,
      d,
    ];
    await _save(list);
  }

  Future<void> removeLocal(String deviceId) async {
    final cur = state.value ?? const <PairedDesktop>[];
    if (!cur.any((d) => d.deviceId == deviceId)) return;
    await _save([for (final d in cur) if (d.deviceId != deviceId) d]);
  }

  /// `DELETE /v1/peers/{id}`, then forget the desktop.
  Future<void> unpair(String deviceId) async {
    try {
      await ref.read(relayApiProvider).unpair(deviceId);
    } on RelayError catch (e) {
      if (e.code != 'not_found') rethrow;
    }
    await removeLocal(deviceId);
  }

  /// Fetches `GET /v1/peers` and forgets desktops the relay no longer pairs
  /// with us. Returns the peers by id.
  Future<Map<String, Peer>> syncWithPeers() async {
    final peers = await ref.read(relayApiProvider).peers();
    final byId = {for (final p in peers) p.deviceId: p};
    final cur = state.value ?? const <PairedDesktop>[];
    final kept = [for (final d in cur) if (byId.containsKey(d.deviceId)) d];
    if (kept.length != cur.length) await _save(kept);
    return byId;
  }
}

final desktopsProvider =
    AsyncNotifierProvider<DesktopsController, List<PairedDesktop>>(
        DesktopsController.new);
