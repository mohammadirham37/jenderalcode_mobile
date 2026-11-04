// Three-way interop check: this phone code (Dart) ↔ the Go relay ↔ the
// Rust desktop crate. Skipped unless JCODE_LIVE=1. Run together with the
// desktop side:
//
//   (relay)    DEV_LOGIN=1 LISTEN_ADDR=127.0.0.1:18080 go run ./cmd/jcrelay
//   (desktop)  JCODE_RELAY_URL=http://127.0.0.1:18080 cargo test -p jcode-remote --test live_e2e -- --ignored
//   (phone)    JCODE_LIVE=1 JCODE_RELAY_URL=http://127.0.0.1:18080 flutter test test/live/live_relay_test.dart
//
// The desktop writes its QR payload to /tmp/jc-e2e/qr.txt; the phone writes
// its SAS to /tmp/jc-e2e/sas-mobile.txt so the desktop can compare.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jenderalcode_mobile/core/crypto/keypair.dart';
import 'package:jenderalcode_mobile/core/relay/relay_api.dart';
import 'package:jenderalcode_mobile/core/relay/relay_socket.dart';
import 'package:jenderalcode_mobile/core/rpc/remote_hub.dart';
import 'package:jenderalcode_mobile/features/pairing/pairing_service.dart';
import 'package:jenderalcode_mobile/features/pairing/qr_payload.dart';

void main() {
  final live = Platform.environment['JCODE_LIVE'] == '1';
  final relay = Platform.environment['JCODE_RELAY_URL'] ?? 'http://127.0.0.1:18080';

  test('phone pairs with the Rust desktop and talks over the Go relay', () async {
    final qrFile = File('/tmp/jc-e2e/qr.txt');
    for (var i = 0; i < 100 && !qrFile.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    final qr = parsePairingQr(qrFile.readAsStringSync());

    final keys = await DeviceKeyPair.generate();
    final api = RelayApi(baseUrl: relay);
    final login = await api.authDev(
        email: 'e2e@example.com', deviceName: 'E2E phone', publicKey: keys.publicB64u);
    api.token = login.deviceToken;

    final pairing = PairingService(api, keys);
    final pending = await pairing.claim(qr);
    File('/tmp/jc-e2e/sas-mobile.txt').writeAsStringSync(pending.sas);
    final desktop = await pairing.approve(pending);

    final wsUri = Uri.parse('${relay.replaceFirst('http', 'ws')}/v1/ws');
    final socket = RelaySocket(uri: wsUri, token: login.deviceToken);
    final hub = RemoteHub(socket: socket, keys: keys, selfId: login.deviceId, desktops: [desktop]);
    final up = hub.linkUp.firstWhere((id) => id == desktop.deviceId);
    hub.start();
    await up.timeout(const Duration(seconds: 15));

    final rpc = hub.rpc(desktop.deviceId);
    final hello = await rpc.call('hello', {'app_version': 'e2e'});
    expect(hello['desktop_name'], 'E2E desktop');

    final ws = await rpc.call('workspaces.list');
    expect((ws['workspaces'] as List).single['name'], 'demo');

    final ev = rpc.events.firstWhere((e) => e.name == 'status');
    await rpc.call('session.subscribe', {'session_id': 's1'});
    final status = await ev.timeout(const Duration(seconds: 10));
    expect(status.sessionId, 's1');
    expect(status.data['status'], 'streaming');

    try {
      await rpc.call('chat.send', {'session_id': 's1', 'content': 'hi'});
      fail('expected yolo_blocked');
    } catch (e) {
      expect(e.toString(), contains('yolo_blocked'));
    }

    await rpc.call('bye');
    await hub.dispose();
  }, skip: live ? false : 'set JCODE_LIVE=1 with a running relay and desktop', timeout: const Timeout(Duration(seconds: 90)));
}
