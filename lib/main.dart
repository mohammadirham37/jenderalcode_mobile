import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app.dart';
import 'core/config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    AppConfig.appVersion = (await PackageInfo.fromPlatform()).version;
  } catch (_) {
    // Keep the placeholder (e.g. in tests or unsupported platforms).
  }
  runApp(const ProviderScope(child: JenderalCodeApp()));
}
