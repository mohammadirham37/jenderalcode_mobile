import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/rpc/models.dart';
import '../../core/rpc/rpc_client.dart';

/// Hint shown wherever a capability is off.
const allowOnDesktopHint = 'Allow it on the desktop: Settings → Remote control';

/// What one desktop allows from this phone (§6.5): from `hello`, then kept up
/// to date by the `capabilities` event. Unknown until the first `hello`
/// answers, which reads as "nothing allowed".
class CapabilitiesController extends Notifier<Capabilities> {
  CapabilitiesController(this.desktopId);
  final String desktopId;
  bool _known = false;

  @override
  Capabilities build() {
    final hub = ref.watch(hubProvider);
    if (hub == null || !hub.isKnown(desktopId)) return Capabilities.none;
    final rpc = hub.rpc(desktopId);
    final subs = <StreamSubscription<Object?>>[
      rpc.events
          .where((e) => e.name == 'capabilities')
          .listen((e) => set(Capabilities.fromJson(e.data))),
      // The setting may have changed while we were away.
      hub.linkUp.where((id) => id == desktopId).listen((_) => refresh()),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
    });
    // Skipped when the caller hands us its own `hello` right away.
    Future.microtask(() {
      if (!_known) refresh();
    });
    return Capabilities.none;
  }

  /// Asks the desktop again via `hello`. Errors keep the last known value.
  Future<void> refresh() async {
    final hub = ref.read(hubProvider);
    if (hub == null || !hub.isKnown(desktopId)) return;
    try {
      final r = await hub
          .rpc(desktopId)
          .call('hello', {'app_version': AppConfig.appVersion});
      if (ref.mounted) set(HelloResult.fromJson(r).capabilities);
    } on RpcError {
      // Offline or not confirmed yet: linkUp retries.
    }
  }

  /// Set from a `hello` made elsewhere.
  void set(Capabilities c) {
    _known = true;
    state = c;
  }
}

final capabilitiesProvider =
    NotifierProvider.family<CapabilitiesController, Capabilities, String>(
        CapabilitiesController.new);
