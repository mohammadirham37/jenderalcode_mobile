/// Pure parts of the in-app updater: versions, the GitHub release JSON,
/// SHA256SUMS and the "Later" rule. No IO here.
library;

const updateRepo = 'mohammadirham37/jenderalcode_mobile';
const latestReleaseApi = 'https://api.github.com/repos/$updateRepo/releases/latest';
const releasesPage = 'https://github.com/$updateRepo/releases';

/// Stable asset name on every release.
const apkAssetName = 'JenderalCode-Mobile.apk';
const sumsAssetName = 'SHA256SUMS';

const checkInterval = Duration(hours: 6);

/// `major.minor.patch`, optionally with a leading `v` and a `+build` or
/// `-pre` suffix (ignored for ordering). Anything else is malformed.
class SemVer implements Comparable<SemVer> {
  const SemVer(this.major, this.minor, this.patch);
  final int major;
  final int minor;
  final int patch;

  static final _re = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$');

  static SemVer? tryParse(String? s) {
    if (s == null) return null;
    final m = _re.firstMatch(s.trim());
    if (m == null) return null;
    return SemVer(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  @override
  int compareTo(SemVer o) {
    if (major != o.major) return major.compareTo(o.major);
    if (minor != o.minor) return minor.compareTo(o.minor);
    return patch.compareTo(o.patch);
  }

  bool operator >(SemVer o) => compareTo(o) > 0;

  @override
  bool operator ==(Object other) => other is SemVer && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// Strictly newer; malformed versions never count.
bool isNewer(String? candidate, String? installed) {
  final c = SemVer.tryParse(candidate);
  final i = SemVer.tryParse(installed);
  if (c == null || i == null) return false;
  return c > i;
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.tag,
    required this.notes,
    required this.apkUrl,
    required this.sumsUrl,
    required this.pageUrl,
  });
  final SemVer version;
  final String tag;
  final String notes;
  final String apkUrl;
  final String? sumsUrl;
  final String pageUrl;

  /// From `GET /releases/latest`. Null for drafts, prereleases, a malformed
  /// tag or a release without the APK asset.
  static ReleaseInfo? fromGitHub(Object? json) {
    if (json is! Map) return null;
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final tag = json['tag_name'];
    final v = SemVer.tryParse(tag is String ? tag : null);
    if (v == null) return null;
    String? url(String name) {
      final assets = json['assets'];
      if (assets is! List) return null;
      for (final a in assets) {
        if (a is Map && a['name'] == name && a['browser_download_url'] is String) {
          return a['browser_download_url'] as String;
        }
      }
      return null;
    }

    final apk = url(apkAssetName);
    if (apk == null) return null;
    final page = json['html_url'];
    final body = json['body'];
    return ReleaseInfo(
      version: v,
      tag: tag as String,
      notes: body is String ? body.trim() : '',
      apkUrl: apk,
      sumsUrl: url(sumsAssetName),
      pageUrl: page is String ? page : '$releasesPage/tag/$tag',
    );
  }
}

/// The release if it is newer than [installed], else null.
ReleaseInfo? updateFrom(Object? json, String installed) {
  final r = ReleaseInfo.fromGitHub(json);
  if (r == null || !isNewer(r.version.toString(), installed)) return null;
  return r;
}

/// `<sha256>  <file>` (text mode) or `<sha256> *<file>` (binary mode) lines;
/// file name → lowercase hex digest. Malformed lines are skipped.
Map<String, String> parseSha256Sums(String text) {
  final out = <String, String>{};
  final re = RegExp(r'^([0-9a-fA-F]{64}) [ *](.+)$');
  for (final raw in text.split('\n')) {
    final m = re.firstMatch(raw.trimRight());
    if (m == null) continue;
    out[m[2]!.trim()] = m[1]!.toLowerCase();
  }
  return out;
}

class ChecksumError implements Exception {
  const ChecksumError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Throws [ChecksumError] unless [actualHex] matches the SHA256SUMS line for
/// [fileName].
void verifyChecksum({required String sums, required String fileName, required String actualHex}) {
  final expected = parseSha256Sums(sums)[fileName];
  if (expected == null) {
    throw ChecksumError('SHA256SUMS has no line for $fileName.');
  }
  if (expected != actualHex.toLowerCase()) {
    throw const ChecksumError('The download does not match its SHA-256 checksum.');
  }
}

/// Whether the automatic check should open the dialog for [version]. "Later"
/// stores the version; a manual check clears it.
bool shouldPrompt({required String version, required String? dismissed, required String? prompted}) =>
    version != dismissed && version != prompted;

/// A check on resume only when the last one is older than [checkInterval].
bool checkDue(DateTime? last, DateTime now) =>
    last == null || now.difference(last) >= checkInterval;
