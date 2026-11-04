import 'package:flutter_test/flutter_test.dart';
import 'package:jenderalcode_mobile/core/config.dart';
import 'package:jenderalcode_mobile/core/rpc/models.dart';
import 'package:jenderalcode_mobile/core/rpc/rpc_client.dart';

void main() {
  test('the official relay is the default', () {
    expect(AppConfig.officialRelay, 'https://backendcode.jenderalcorp.com');
    expect(AppConfig.hasRelay, isTrue);
    expect(AppConfig.socketUriFor(AppConfig.officialRelay).toString(),
        'wss://backendcode.jenderalcorp.com/v1/ws');
  });

  test('hello capabilities are parsed', () {
    final h = HelloResult.fromJson({
      'desktop_version': '0.2.0',
      'desktop_name': 'Mac',
      'capabilities': {'full_access': true, 'terminal': true, 'edit': true, 'future': 1},
    });
    expect(h.capabilities, const Capabilities(fullAccess: true, terminal: true, edit: true));
  });

  test('an older desktop without capabilities allows nothing', () {
    final h = HelloResult.fromJson({'desktop_version': '0.1.5', 'desktop_name': 'Mac'});
    expect(h.capabilities, Capabilities.none);
    expect(h.capabilities.fullAccess, isFalse);
    expect(h.capabilities.terminal, isFalse);
    expect(h.capabilities.edit, isFalse);
  });

  test('missing or malformed fields read as false', () {
    expect(Capabilities.fromJson({'full_access': true}),
        const Capabilities(fullAccess: true, terminal: false, edit: false));
    expect(Capabilities.fromJson({'full_access': 'yes', 'terminal': 1}), Capabilities.none);
    expect(Capabilities.fromJson(null), Capabilities.none);
    expect(Capabilities.fromJson([]), Capabilities.none);
  });

  test('capabilities event data is a Capabilities object', () {
    const e = RpcEvent('capabilities', {'full_access': false, 'terminal': true, 'edit': false});
    expect(Capabilities.fromJson(e.data).terminal, isTrue);
  });

  test('new error codes read well', () {
    expect(const RpcError('not_allowed').readable, contains('Settings → Remote control'));
    expect(const RpcError('yolo_blocked').readable, contains('Full access'));
  });
}
