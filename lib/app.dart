import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/desktops/desktops_screen.dart';
import 'features/pairing/pairing_service.dart';
import 'features/pairing/sas_screen.dart';
import 'features/pairing/scanner_screen.dart';
import 'features/sessions/sessions_screen.dart';
import 'features/sessions/workspaces_screen.dart';
import 'features/agents/agent_usage_screen.dart';
import 'features/updates/update_controller.dart';
import 'features/updates/update_ui.dart';
import 'features/project/project_screen.dart';
import 'features/terminal/terminal_screen.dart';
import 'features/terminal/terminals_screen.dart';

/// Bridges the auth provider to go_router's refresh.
class _AuthRefresh extends ChangeNotifier {
  void ping() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh();
  ref.listen(authProvider, (_, _) => refresh.ping());
  ref.onDispose(refresh.dispose);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.matchedLocation;
      if (auth.isLoading && !auth.hasValue) {
        return loc == '/splash' ? null : '/splash';
      }
      final signedIn = auth.value != null;
      if (!signedIn) return loc == '/login' ? null : '/login';
      if (loc == '/login' || loc == '/splash') return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const _Splash()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/',
        builder: (_, _) => const DesktopsScreen(),
        routes: [
          GoRoute(path: 'pair', builder: (_, _) => const ScannerScreen()),
          GoRoute(path: 'about', builder: (_, _) => const AboutScreen()),
          GoRoute(
            path: 'pair/confirm',
            redirect: (_, s) => s.extra is PendingPairing ? null : '/pair',
            builder: (_, s) => SasScreen(pending: s.extra! as PendingPairing),
          ),
          GoRoute(
            path: 'd/:did',
            builder: (_, s) =>
                WorkspacesScreen(desktopId: s.pathParameters['did']!),
            routes: [
              GoRoute(
                path: 'w/:wid',
                builder: (_, s) => SessionsScreen(
                  desktopId: s.pathParameters['did']!,
                  workspaceId: s.pathParameters['wid']!,
                  workspaceName: s.uri.queryParameters['name'] ?? 'Project',
                ),
                routes: [
                  GoRoute(
                    path: 'p',
                    builder: (_, s) => ProjectScreen(
                      desktopId: s.pathParameters['did']!,
                      workspaceId: s.pathParameters['wid']!,
                      workspaceName: s.uri.queryParameters['name'] ?? 'Project',
                      initialTab: s.uri.queryParameters['tab'],
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'usage',
                builder: (_, s) => AgentUsageScreen(desktopId: s.pathParameters['did']!),
              ),
              GoRoute(
                path: 't',
                builder: (_, s) => TerminalsScreen(desktopId: s.pathParameters['did']!),
                routes: [
                  GoRoute(
                    path: ':tid',
                    builder: (_, s) => TerminalScreen(
                      desktopId: s.pathParameters['did']!,
                      terminalId: s.pathParameters['tid']!,
                      initialTitle: s.uri.queryParameters['title'],
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 's/:sid',
                builder: (_, s) => ChatScreen(
                  desktopId: s.pathParameters['did']!,
                  sessionId: s.pathParameters['sid']!,
                  initialTitle: s.uri.queryParameters['title'],
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class JenderalCodeApp extends ConsumerStatefulWidget {
  const JenderalCodeApp({super.key});
  @override
  ConsumerState<JenderalCodeApp> createState() => _JenderalCodeAppState();
}

class _JenderalCodeAppState extends ConsumerState<JenderalCodeApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Phones drop sockets in the background; reconnect when we come back.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        ref.read(hubProvider)?.socket.resume();
        ref.read(updateProvider.notifier).onResume();
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep the relay connection alive for the whole signed-in session.
    ref.watch(hubProvider);
    // Update checks run for the whole app lifetime.
    ref.watch(updateProvider);
    return MaterialApp.router(
      title: 'JenderalCode',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
}
