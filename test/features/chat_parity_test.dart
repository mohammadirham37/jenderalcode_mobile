import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jenderalcode_mobile/core/rpc/models.dart';
import 'package:jenderalcode_mobile/features/chat/composer_logic.dart';
import 'package:jenderalcode_mobile/features/chat/images.dart';

void main() {
  group('§6.4 parsing', () {
    test('Agent', () {
      final a = Agent.fromJson({
        'id': 'build', 'name': 'Build', 'mode': 'build', 'policy_mode': 'balanced', 'built_in': true,
      });
      expect(a.modeLabel, 'Build');
      expect(a.builtIn, isTrue);
      expect(a.policyMode, 'balanced');
      expect(Agent.fromJson({'id': 'x', 'name': 'Mine', 'policy_mode': null}).modeLabel, 'Custom');
    });

    test('Model capabilities stay null when unknown; catalog groups by provider', () {
      final cat = ModelCatalog.fromJson({
        'providers': [
          {'id': 'p1', 'name': 'Anthropic', 'kind': 'anthropic'},
          {'id': 'p2', 'name': 'OpenAI', 'kind': 'openai'},
        ],
        'models': [
          {'id': 'm1', 'provider_id': 'p1', 'name': 'claude-x', 'display_name': 'Claude X',
           'capabilities': {'vision': true, 'context_window': 200000, 'tools': true}},
          {'id': 'm2', 'provider_id': 'p2', 'name': 'gpt-y', 'display_name': '',
           'capabilities': {}},
          {'id': 'm3', 'provider_id': 'p2', 'name': 'gpt-text', 'display_name': 'Text',
           'capabilities': {'vision': false}},
        ],
      });
      final g = cat.grouped;
      expect(g.map((e) => e.$1.name), ['Anthropic', 'OpenAI']);
      expect(g[1].$2.length, 2);
      final m1 = cat.find('p1', 'claude-x')!;
      expect(m1.vision, isTrue);
      expect(m1.contextWindow, 200000);
      final m2 = cat.find('p2', 'gpt-y')!;
      expect(m2.vision, isNull);
      expect(m2.contextWindow, isNull);
      expect(m2.label, 'gpt-y');
      expect(imagesAllowedFor(m1), isTrue);
      expect(imagesAllowedFor(m2), isTrue);
      expect(imagesAllowedFor(cat.find('p2', 'gpt-text')), isFalse);
      expect(imagesAllowedFor(null), isTrue);
    });

    test('SessionUsage and the context meter', () {
      final u = SessionUsage.fromJson({
        'total_input': 5000, 'total_output': 800, 'total_cost': null, 'requests': 3,
        'last_input': 50000, 'last_output': 120,
      });
      expect(u.totalCost, isNull);
      expect(u.requests, 3);
      expect(contextFraction(u.lastInput, 200000), 0.25);
      expect(contextFraction(u.lastInput, null), isNull);
      expect(contextFraction(500000, 200000), 1.0);
      expect(compactTokens(50000), '50k');
      expect(compactTokens(1500), '1.5k');
      expect(compactTokens(200000), '200k');
    });

    test('Checkpoint and Skill', () {
      final c = Checkpoint.fromJson({
        'id': 'c1', 'session_id': 's1', 'rel_path': 'src/a.ts', 'existed': false, 'is_dir': false,
        'created_at': 10,
      });
      expect(c.relPath, 'src/a.ts');
      expect(c.existed, isFalse);
      final s = Skill.listFrom([
        {'name': 'review', 'description': 'Review code', 'project': true},
      ]);
      expect(s.single.project, isTrue);
      expect(filterSkills(s, 'REV').length, 1);
      expect(filterSkills(s, 'zz'), isEmpty);
    });

    test('FileStatus, Commit, FileEntry', () {
      final f = FileStatus.fromJson({'path': 'a', 'index': 'modified', 'worktree': 'weird'});
      expect(f.index, StatusKind.modified);
      expect(f.worktree, StatusKind.other);
      expect(f.isStaged, isTrue);
      final u = FileStatus.fromJson({'path': 'b', 'index': 'untracked', 'worktree': 'untracked'});
      expect(u.isStaged, isFalse);
      expect(u.isUnstaged, isTrue);
      final c = Commit.fromJson({
        'hash': 'abcdef0123', 'short_hash': 'abcdef0', 'subject': 'Fix', 'author': 'Me',
        'timestamp': 1730000000,
      });
      expect(c.shortHash, 'abcdef0');
      expect(c.timestampMs, 1730000000000);
      final e = FileEntry.fromJson({'path': 'src', 'name': 'src', 'is_dir': true});
      expect(e.isDir, isTrue);
      expect(e.size, isNull);
    });
  });

  group('images', () {
    test('fitWithin keeps the ratio, caps the longest side, never upscales', () {
      expect(fitWithin(4000, 3000), (width: 1568, height: 1176));
      expect(fitWithin(3000, 4000), (width: 1176, height: 1568));
      expect(fitWithin(800, 600), (width: 800, height: 600));
      expect(fitWithin(1568, 1568), (width: 1568, height: 1568));
      expect(fitWithin(10000, 10), (width: 1568, height: 2));
      expect(fitWithin(0, 10), (width: 0, height: 0));
    });

    test('prepareImage scales down and encodes as base64 JPEG', () async {
      final src = img.Image(width: 2400, height: 1200);
      img.fill(src, color: img.ColorRgb8(20, 160, 140));
      final out = await prepareImage(img.encodeJpg(src));
      expect(out.mime, 'image/jpeg');
      expect(out.width, 1568);
      expect(out.height, 784);
      expect(out.data.startsWith('data:'), isFalse);
      final back = img.decodeImage(base64Decode(out.data))!;
      expect(back.width, 1568);
      expect(out.toJson().keys, ['mime', 'data']);
    });

    test('a PNG with transparency stays PNG', () async {
      final src = img.Image(width: 100, height: 50, numChannels: 4);
      final out = await prepareImage(img.encodePng(src));
      expect(out.mime, 'image/png');
      expect(out.width, 100);
    });

    test('at most 4 images and 6 MB', () {
      const one = ImageAttachment(mime: 'image/jpeg', data: 'AAAA');
      expect(imageAddError(const [], one), isNull);
      expect(imageAddError(const [one, one, one, one], one), isNotNull);
      final big = ImageAttachment(mime: 'image/jpeg', data: 'A' * 4000000);
      expect(imageAddError([big], big), contains('6 MB'));
    });
  });

  group('composer', () {
    test('attachments are unique and capped at 20', () {
      var l = <String>[];
      l = addAttachment(l, 'a.ts');
      l = addAttachment(l, 'a.ts');
      expect(l, ['a.ts']);
      for (var i = 0; i < 30; i++) {
        l = addAttachment(l, 'f$i');
      }
      expect(l.length, maxAttachments);
    });

    test('@ mention detection and insertion', () {
      expect(activeMention('look at @src/ma', 15)!.query, 'src/ma');
      expect(activeMention('@', 1)!.query, '');
      expect(activeMention('mail a@b.com', 12), isNull);
      expect(activeMention('@done next', 10), isNull);
      final m = activeMention('see @ma please', 7)!;
      final r = applyMention('see @ma please', m, 'src/main.dart');
      expect(r.text, 'see @src/main.dart  please');
      expect(r.cursor, 'see @src/main.dart '.length);
    });

    test('/ skill menu', () {
      expect(activeSlash('/rev', 4), 'rev');
      expect(activeSlash('/review now', 11), isNull);
      expect(activeSlash('hi /x', 5), isNull);
      expect(applySlash('/rev', 'review'), '/review ');
      expect(applySlash('/r fix this', 'review'), '/review fix this');
    });

    test('rename validation', () {
      expect(validateTitle('  '), isNotNull);
      expect(validateTitle('x' * 201), isNotNull);
      expect(validateTitle('Refactor auth'), isNull);
    });

    test('checkpoint restore is gated by edit', () {
      const edit = Capabilities(fullAccess: false, terminal: false, edit: true);
      expect(canRestoreCheckpoints(edit, 2), isTrue);
      expect(canRestoreCheckpoints(edit, 0), isFalse);
      expect(canRestoreCheckpoints(Capabilities.none, 2), isFalse);
    });
  });
}
