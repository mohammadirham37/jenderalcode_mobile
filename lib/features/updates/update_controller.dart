import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import 'update_io.dart';
import 'update_logic.dart';

enum UpdatePhase { idle, needsPermission, downloading, verifying, installing, failed }

class UpdateState {
  const UpdateState({
    this.installed,
    this.checking = false,
    this.lastCheck,
    this.available,
    this.status,
    this.phase = UpdatePhase.idle,
    this.progress,
    this.error,
    this.promptVersion,
  });

  /// `version` from package_info_plus, e.g. 1.0.0.
  final String? installed;
  final bool checking;
  final DateTime? lastCheck;

  /// A strictly newer, non-draft, non-prerelease release with the APK.
  final ReleaseInfo? available;

  /// Result of the last manual check ("Up to date", an error), for About.
  final String? status;
  final UpdatePhase phase;

  /// 0–1 while downloading; null when the size is unknown.
  final double? progress;
  final String? error;

  /// Set when the automatic check wants the dialog shown for this version.
  final String? promptVersion;

  bool get busy =>
      phase == UpdatePhase.downloading || phase == UpdatePhase.verifying || phase == UpdatePhase.installing;

  UpdateState copyWith({
    String? installed,
    bool? checking,
    DateTime? lastCheck,
    Object? available = _keep,
    Object? status = _keep,
    UpdatePhase? phase,
    Object? progress = _keep,
    Object? error = _keep,
    Object? promptVersion = _keep,
  }) =>
      UpdateState(
        installed: installed ?? this.installed,
        checking: checking ?? this.checking,
        lastCheck: lastCheck ?? this.lastCheck,
        available: available == _keep ? this.available : available as ReleaseInfo?,
        status: status == _keep ? this.status : status as String?,
        phase: phase ?? this.phase,
        progress: progress == _keep ? this.progress : progress as double?,
        error: error == _keep ? this.error : error as String?,
        promptVersion: promptVersion == _keep ? this.promptVersion : promptVersion as String?,
      );
}

const _keep = Object();
const _dismissedKey = 'update_dismissed_version';

/// Only on a real Android device or emulator, never under `flutter test`.
bool get updatesSupported =>
    !kIsWeb && Platform.isAndroid && !Platform.environment.containsKey('FLUTTER_TEST');

/// Checks GitHub releases (2 s after launch, every 6 h, on resume when due),
/// downloads and verifies the APK and hands it to the system installer.
class UpdateController extends Notifier<UpdateState> {
  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 60),
  ));
  UpdateBridge? _bridge;
  Timer? _first;
  Timer? _periodic;
  CancelToken? _cancel;
  String? _dismissed;
  String? _prompted;

  @override
  UpdateState build() {
    ref.onDispose(() {
      _first?.cancel();
      _periodic?.cancel();
      _cancel?.cancel();
      _dio.close(force: true);
    });
    if (!updatesSupported) return const UpdateState();
    _bridge = UpdateBridge()..onInstallStatus = _onInstallStatus;
    _init();
    return const UpdateState();
  }

  Future<void> _init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _dismissed = await ref.read(keyValueStoreProvider).read(_dismissedKey);
      if (!ref.mounted) return;
      state = state.copyWith(installed: info.version);
    } catch (_) {
      return;
    }
    _first = Timer(const Duration(seconds: 2), () => check());
    _periodic = Timer.periodic(checkInterval, (_) => check());
  }

  Map<String, String> get _headers => {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'JenderalCode-Mobile/${state.installed ?? '0'}',
      };

  /// [manual] clears "Later", reports the result and never opens the dialog.
  Future<void> check({bool manual = false}) async {
    final installed = state.installed;
    if (installed == null || state.checking) return;
    if (manual && _dismissed != null) {
      _dismissed = null;
      ref.read(keyValueStoreProvider).delete(_dismissedKey).ignore();
    }
    state = state.copyWith(checking: true, status: manual ? null : state.status);
    try {
      final r = await _dio.get<Object?>(latestReleaseApi, options: Options(headers: _headers));
      if (!ref.mounted) return;
      final rel = updateFrom(r.data, installed);
      final v = rel?.version.toString();
      final prompt = !manual && v != null && shouldPrompt(version: v, dismissed: _dismissed, prompted: _prompted);
      state = state.copyWith(
        checking: false,
        lastCheck: DateTime.now(),
        available: rel,
        status: manual ? (rel == null ? 'You have the latest version.' : 'Version $v is available.') : state.status,
        promptVersion: prompt ? v : state.promptVersion,
      );
    } catch (e) {
      // Offline or rate limited (60/h): stay quiet unless asked.
      if (!ref.mounted) return;
      state = state.copyWith(
        checking: false,
        lastCheck: DateTime.now(),
        status: manual ? 'Could not reach GitHub. Try again later.' : state.status,
      );
    }
  }

  /// The dialog for [promptVersion] was shown.
  void promptShown() {
    _prompted = state.promptVersion;
    state = state.copyWith(promptVersion: null);
  }

  /// "Later": no dialog for this version until the next manual check.
  void later(String version) {
    _dismissed = version;
    ref.read(keyValueStoreProvider).write(_dismissedKey, version).ignore();
  }

  void onResume() {
    if (_bridge == null) return;
    if (checkDue(state.lastCheck, DateTime.now())) check();
    if (state.phase == UpdatePhase.needsPermission) _recheckPermission();
  }

  Future<void> _recheckPermission() async {
    if (await _bridge!.canRequestPackageInstalls()) {
      state = state.copyWith(phase: UpdatePhase.idle, error: null);
      await startUpdate();
    }
  }

  Future<void> openInstallSettings() async => _bridge?.openInstallSettings();

  /// Debug builds are signed with the debug key: Android refuses a release
  /// update over them, so they open the release page instead.
  Future<void> startUpdate() async {
    final rel = state.available;
    final bridge = _bridge;
    if (rel == null || bridge == null || state.busy) return;
    if (kDebugMode) {
      await launchUrl(Uri.parse(rel.pageUrl), mode: LaunchMode.externalApplication);
      return;
    }
    if (!await bridge.canRequestPackageInstalls()) {
      state = state.copyWith(phase: UpdatePhase.needsPermission, error: null);
      return;
    }
    final sumsUrl = rel.sumsUrl;
    if (sumsUrl == null) {
      state = state.copyWith(
          phase: UpdatePhase.failed, error: 'This release has no SHA256SUMS, so it cannot be verified.');
      return;
    }
    final dir = await bridge.updatesDir();
    final file = File('$dir/$apkAssetName');
    final token = _cancel = CancelToken();
    state = state.copyWith(phase: UpdatePhase.downloading, progress: 0.0, error: null);
    try {
      if (file.existsSync()) file.deleteSync();
      final sums = await _dio.get<String>(sumsUrl,
          options: Options(responseType: ResponseType.plain, headers: {'User-Agent': _headers['User-Agent']!}),
          cancelToken: token);
      await _dio.download(
        rel.apkUrl,
        file.path,
        cancelToken: token,
        options: Options(headers: {'User-Agent': _headers['User-Agent']!}),
        onReceiveProgress: (got, total) {
          if (ref.mounted) state = state.copyWith(progress: total > 0 ? got / total : null);
        },
      );
      state = state.copyWith(phase: UpdatePhase.verifying, progress: null);
      await verifyDownloadedApk(file, sums.data ?? '');
      state = state.copyWith(phase: UpdatePhase.installing);
      final how = await bridge.installApk(file.path);
      // The system installer screen reports nothing back.
      if (how == 'view' && ref.mounted) state = state.copyWith(phase: UpdatePhase.idle);
    } on DioException catch (e) {
      if (file.existsSync()) file.deleteSync();
      if (!ref.mounted) return;
      state = CancelToken.isCancel(e)
          ? state.copyWith(phase: UpdatePhase.idle, progress: null)
          : state.copyWith(phase: UpdatePhase.failed, progress: null, error: 'Download failed. Check the connection and try again.');
    } on ChecksumError catch (e) {
      if (ref.mounted) {
        state = state.copyWith(phase: UpdatePhase.failed, error: '${e.message} The file was deleted.');
      }
    } catch (e) {
      if (ref.mounted) state = state.copyWith(phase: UpdatePhase.failed, error: 'Update failed: $e');
    } finally {
      _cancel = null;
    }
  }

  void cancel() => _cancel?.cancel();

  void _onInstallStatus(String status, String? message) {
    if (!ref.mounted) return;
    switch (status) {
      case 'pending_user_action':
        break; // the system confirmation is showing
      case 'success':
        state = state.copyWith(phase: UpdatePhase.idle);
      case 'cancelled':
        state = state.copyWith(phase: UpdatePhase.idle, error: 'Installation cancelled.');
      case 'conflict':
        state = state.copyWith(
            phase: UpdatePhase.failed,
            error: 'Android refused the update: the installed app is signed with a different key. '
                'Uninstall it and install the release APK from GitHub.');
      case 'blocked':
        state = state.copyWith(phase: UpdatePhase.failed, error: 'The installation was blocked by the system.');
      default:
        state = state.copyWith(
            phase: UpdatePhase.failed, error: 'Installation failed${message == null ? '' : ': $message'}.');
    }
  }
}

final updateProvider = NotifierProvider<UpdateController, UpdateState>(UpdateController.new);
