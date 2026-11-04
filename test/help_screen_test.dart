import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jenderalcode_mobile/core/theme/app_theme.dart';
import 'package:jenderalcode_mobile/features/help/help_content.dart';
import 'package:jenderalcode_mobile/features/help/help_screen.dart';

void main() {
  test('every topic has a section, in order and once', () {
    expect(helpSections.map((s) => s.topic).toList(), HelpTopic.values);
    for (final s in helpSections) {
      expect(s.steps.isNotEmpty || s.tips.isNotEmpty, isTrue, reason: s.title);
    }
  });

  test('parse maps query names to topics', () {
    expect(HelpScreen.parse('agents'), HelpTopic.agents);
    expect(HelpScreen.parse('nope'), isNull);
    expect(HelpScreen.parse(null), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('opens at the requested topic on a small phone (dark: $dark)', (t) async {
      t.view.physicalSize = const Size(360 * 3, 640 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(dark ? Brightness.dark : Brightness.light),
        home: const HelpScreen(initial: HelpTopic.agents),
      ));
      await t.pumpAndSettle();
      // The agents section is expanded and scrolled into view.
      expect(find.text('Tekan Start. Agent berjalan di desktop; Anda mengetik dan melihat hasilnya di HP.'),
          findsOneWidget);
      // Other sections are collapsed.
      expect(find.textContaining('Desktop harus terbuka dan tersambung'), findsOneWidget); // summary only
      expect(find.textContaining('Tekan "Pair a phone"'), findsNothing);
      // Expanding another works and lays out without overflow.
      await t.ensureVisible(find.text('Mengatasi masalah'));
      await t.pumpAndSettle();
      await t.tap(find.text('Mengatasi masalah'));
      await t.pumpAndSettle();
      expect(find.textContaining('Strip "Relay offline"'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
