import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jenderalcode_mobile/app.dart';
import 'package:jenderalcode_mobile/core/providers.dart';
import 'package:jenderalcode_mobile/core/storage/secure_store.dart';

void main() {
  testWidgets('signed out: the router lands on the login screen', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore())],
      child: const JenderalCodeApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('JenderalCode'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });
}
