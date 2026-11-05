import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jenderalcode_mobile/core/rpc/rpc_client.dart';
import 'package:jenderalcode_mobile/core/theme/app_theme.dart';
import 'package:jenderalcode_mobile/features/chat/composer.dart';

void main() {
  Future<void> pump(WidgetTester t, EnhanceFn? onEnhance) => t.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Composer(
                desktopId: 'd',
                workspaceId: null,
                busy: false,
                sending: false,
                imagesAllowed: true,
                onSend: (_, _, _) async => true,
                onStop: () {},
                onEnhance: onEnhance,
              ),
            ),
          ),
        ),
      ));

  testWidgets('enhance replaces the draft and Undo brings it back', (t) async {
    String? got;
    await pump(t, (d) async {
      got = d;
      return 'Fix the login bug in auth.dart and add a test.';
    });
    final button = find.byTooltip('Enhance prompt');
    expect(t.widget<IconButton>(find.ancestor(of: find.byIcon(Icons.edit_note), matching: find.byType(IconButton))).onPressed, isNull, reason: 'disabled while empty');
    await t.enterText(find.byType(TextField), 'fix login');
    await t.pump();
    await t.tap(button);
    await t.pumpAndSettle();
    expect(got, 'fix login');
    expect(find.text('Fix the login bug in auth.dart and add a test.'), findsOneWidget);
    await t.tap(find.text('Undo'));
    await t.pumpAndSettle();
    expect(find.text('fix login'), findsOneWidget);
  });

  testWidgets('an older desktop is explained', (t) async {
    await pump(t, (_) async => throw const RpcError('bad_request', 'unknown method chat.enhance'));
    await t.enterText(find.byType(TextField), 'hello');
    await t.pump();
    await t.tap(find.byTooltip('Enhance prompt'));
    await t.pumpAndSettle();
    expect(find.textContaining('Update JenderalCode Desktop'), findsOneWidget);
    expect(find.text('hello'), findsOneWidget, reason: 'draft kept');
  });

  testWidgets('no session model: no button action', (t) async {
    await pump(t, null);
    await t.enterText(find.byType(TextField), 'hello');
    await t.pump();
    expect(t.widget<IconButton>(find.ancestor(of: find.byIcon(Icons.edit_note), matching: find.byType(IconButton))).onPressed, isNull);
  });
}
