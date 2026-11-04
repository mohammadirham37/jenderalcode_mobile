import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jenderalcode_mobile/core/config.dart';
import 'package:jenderalcode_mobile/features/updates/update_io.dart';
import 'package:jenderalcode_mobile/features/updates/update_logic.dart';

Map<String, dynamic> release({
  String tag = 'v1.0.1',
  bool draft = false,
  bool prerelease = false,
  bool withApk = true,
  bool withSums = true,
}) =>
    {
      'tag_name': tag,
      'draft': draft,
      'prerelease': prerelease,
      'body': '  Fixes and terminals.\n',
      'html_url': 'https://github.com/$updateRepo/releases/tag/$tag',
      'assets': [
        if (withApk) {'name': 'JenderalCode-Mobile.apk', 'browser_download_url': 'https://x/apk'},
        {'name': 'JenderalCode-Mobile-1.0.1.apk', 'browser_download_url': 'https://x/apk-v'},
        if (withSums) {'name': 'SHA256SUMS', 'browser_download_url': 'https://x/sums'},
      ],
    };

void main() {
  test('Google client id has a public default', () {
    expect(AppConfig.googleServerClientId, endsWith('.apps.googleusercontent.com'));
  });

  group('semver', () {
    test('ordering', () {
      expect(isNewer('1.0.10', '1.0.9'), isTrue);
      expect(isNewer('v1.1.0', '1.0.99'), isTrue);
      expect(isNewer('2.0.0', '1.9.9'), isTrue);
      expect(isNewer('1.0.0', '1.0.0'), isFalse);
      expect(isNewer('v1.0.0', '1.0.0+5'), isFalse);
      expect(isNewer('1.0.0', '1.0.1'), isFalse);
    });

    test('malformed versions are ignored', () {
      expect(isNewer('latest', '1.0.0'), isFalse);
      expect(isNewer('1.0', '0.9.0'), isFalse);
      expect(isNewer('1.0.1', 'garbage'), isFalse);
      expect(isNewer(null, '1.0.0'), isFalse);
      expect(SemVer.tryParse('v1.2.3-beta'), const SemVer(1, 2, 3));
    });
  });

  group('release JSON', () {
    test('a newer release with the APK is an update', () {
      final r = updateFrom(release(), '1.0.0')!;
      expect(r.version.toString(), '1.0.1');
      expect(r.apkUrl, 'https://x/apk');
      expect(r.sumsUrl, 'https://x/sums');
      expect(r.notes, 'Fixes and terminals.');
      expect(r.pageUrl, contains('/releases/tag/v1.0.1'));
    });

    test('drafts, prereleases, same version and missing APK are no update', () {
      expect(updateFrom(release(draft: true), '1.0.0'), isNull);
      expect(updateFrom(release(prerelease: true), '1.0.0'), isNull);
      expect(updateFrom(release(), '1.0.1'), isNull);
      expect(updateFrom(release(withApk: false), '1.0.0'), isNull);
      expect(updateFrom(release(tag: 'nightly'), '1.0.0'), isNull);
      expect(updateFrom({'message': 'API rate limit exceeded'}, '1.0.0'), isNull);
      expect(updateFrom(null, '1.0.0'), isNull);
    });

    test('missing SHA256SUMS keeps the release but without a sums url', () {
      expect(updateFrom(release(withSums: false), '1.0.0')!.sumsUrl, isNull);
    });
  });

  group('SHA256SUMS', () {
    final a = 'a' * 64;
    final b = 'B' * 64;
    test('text and binary mode lines, other files kept separately', () {
      final m = parseSha256Sums('$a  JenderalCode-Mobile.apk\n'
          '$b *JenderalCode-Mobile-1.0.1.apk\r\n'
          'not a line\n'
          '1234  short.apk\n');
      expect(m['JenderalCode-Mobile.apk'], a);
      expect(m['JenderalCode-Mobile-1.0.1.apk'], 'b' * 64);
      expect(m.length, 2);
    });

    test('mismatch and missing line are rejected', () {
      final sums = '$a  JenderalCode-Mobile.apk\n';
      expect(() => verifyChecksum(sums: sums, fileName: apkAssetName, actualHex: a), returnsNormally);
      expect(() => verifyChecksum(sums: sums, fileName: apkAssetName, actualHex: 'c' * 64),
          throwsA(isA<ChecksumError>()));
      expect(() => verifyChecksum(sums: '$a  other.apk', fileName: apkAssetName, actualHex: a),
          throwsA(isA<ChecksumError>()));
    });

    test('a downloaded file that does not match is deleted', () async {
      final dir = Directory.systemTemp.createTempSync('jc_upd');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}/$apkAssetName')..writeAsStringSync('apk bytes');
      final good = sha256.convert('apk bytes'.codeUnits).toString();
      expect(await sha256OfFile(f), good);

      await verifyDownloadedApk(f, '$good  $apkAssetName\n');
      expect(f.existsSync(), isTrue);

      await expectLater(verifyDownloadedApk(f, '${'0' * 64}  $apkAssetName\n'),
          throwsA(isA<ChecksumError>()));
      expect(f.existsSync(), isFalse);

      final g = File('${dir.path}/$apkAssetName')..writeAsStringSync('apk bytes');
      await expectLater(verifyDownloadedApk(g, ''), throwsA(isA<ChecksumError>()));
      expect(g.existsSync(), isFalse);
    });
  });

  group('Later', () {
    test('suppresses the dialog for that version only', () {
      expect(shouldPrompt(version: '1.0.1', dismissed: null, prompted: null), isTrue);
      expect(shouldPrompt(version: '1.0.1', dismissed: '1.0.1', prompted: null), isFalse);
      expect(shouldPrompt(version: '1.0.2', dismissed: '1.0.1', prompted: null), isTrue);
      // Shown once per version even without "Later".
      expect(shouldPrompt(version: '1.0.1', dismissed: null, prompted: '1.0.1'), isFalse);
    });

    test('resume checks only when the last check is 6 h old', () {
      final now = DateTime(2026, 11, 4, 12);
      expect(checkDue(null, now), isTrue);
      expect(checkDue(now.subtract(const Duration(hours: 5)), now), isFalse);
      expect(checkDue(now.subtract(const Duration(hours: 6)), now), isTrue);
    });
  });
}
