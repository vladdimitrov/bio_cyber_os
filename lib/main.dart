import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bio_cyber_os/l10n/app_localizations.dart';

import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'core/bootstrap/user_bootstrap.dart';
import 'core/debug/agent_debug_log.dart';
import 'core/notifications/notification_service.dart';
import 'core/navigation/app_navigator.dart';
import 'core/security/supabase_secure_local_storage.dart';
import 'core/settings/locale_settings.dart';
import 'core/settings/measurement_settings.dart';
import 'core/settings/notification_settings.dart';
import 'core/settings/profile_settings.dart';
import 'app_shell.dart';
import 'features/auth/screens/splash_route.dart';
import 'features/auth/screens/auth_screen.dart';

// Global navigator for deterministic flows (biometric vault).
final GlobalKey<NavigatorState> navigatorKey = AppNavigator.key;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('DEBUG: App started');

  try {
    await AgentDebugLog.ensureInitialized();
  } catch (e, st) {
    debugPrint('DEBUG: AgentDebugLog.ensureInitialized failed: $e $st');
  }

  // Avoid hard-crashing in debug/web when --dart-define is missing.
  // Instead, show a clear configuration screen.
  if (AppConfig.supabaseUrl.isEmpty || AppConfig.supabaseAnonKey.isEmpty) {
    debugPrint(
      'DEBUG: Missing SUPABASE_URL / SUPABASE_ANON_KEY. '
      'Run with --dart-define SUPABASE_URL=... and SUPABASE_ANON_KEY=...',
    );
    runApp(const _MissingSupabaseConfigApp());
    return;
  }

  try {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
      debug: kIsWeb,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        localStorage: SupabaseSecureLocalStorage(),
      ),
    );
    debugPrint('DEBUG: Supabase Client Initialized');
  } catch (e, st) {
    debugPrint(
      'DEBUG: Supabase init with secure localStorage failed: $e — retrying default storage $st',
    );
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
        debug: kIsWeb,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
      );
      debugPrint('DEBUG: Supabase Client Initialized (fallback storage)');
    } catch (e2, st2) {
      debugPrint('DEBUG: Supabase init failed completely: $e2 $st2');
      runApp(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Supabase init failed: $e2'),
              ),
            ),
          ),
        ),
      );
      return;
    }
  }

  try {
    await NotificationService.init();
  } catch (e, st) {
    debugPrint('DEBUG: NotificationService.init failed: $e $st');
  }
  try {
    await MeasurementSettings.load();
  } catch (e, st) {
    debugPrint('DEBUG: MeasurementSettings.load failed: $e $st');
  }
  try {
    await NotificationSettings.load();
  } catch (e, st) {
    debugPrint('DEBUG: NotificationSettings.load failed: $e $st');
  }
  try {
    await LocaleSettings.load();
  } catch (e, st) {
    debugPrint('DEBUG: LocaleSettings.load failed: $e $st');
  }
  try {
    await ProfileSettings.loadLocal();
  } catch (e, st) {
    debugPrint('DEBUG: ProfileSettings.loadLocal failed: $e $st');
  }

  try {
    await UserBootstrap.initialize().timeout(const Duration(seconds: 8));
  } catch (e, st) {
    debugPrint('DEBUG: UserBootstrap.initialize failed or timed out: $e $st');
  }

  runApp(const BioCyberOSApp());

  // Non-blocking: hydrate profile after first frame. A null profile must never
  // prevent app navigation (biometric vault flow depends on this).
  unawaited(
    Future(() async {
      try {
        final uid = Supabase.instance.client.auth.currentUser?.id;
        if (uid == null) {
          final sid = Supabase.instance.client.auth.currentSession?.user.id;
          debugPrint(
            'DEBUG: Startup profile hydrate skipped (no currentUser UID). '
            'currentSession.user.id=$sid',
          );
          return;
        }
        debugPrint('DEBUG: Fetching profile for UID: $uid');
        final data = await ProfileSettings.hydrateFromSupabase().timeout(
          const Duration(seconds: 12),
        );
        debugPrint('DEBUG: Profile fetch result: $data');
        if (data == null) {
          await ProfileSettings.ensureRemoteProfileRow();
        }
      } on TimeoutException catch (e) {
        debugPrint('DEBUG: Startup profile hydrate timed out: $e');
      } catch (e, st) {
        debugPrint('DEBUG: Startup profile hydrate failed: $e $st');
      }
    }),
  );
}

class _MissingSupabaseConfigApp extends StatelessWidget {
  const _MissingSupabaseConfigApp();

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    return const MaterialApp(
      home: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: bg,
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: DefaultTextStyle(
              style: TextStyle(
                color: cyan,
                fontFamily: 'monospace',
                height: 1.4,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'SUPABASE CONFIG MISSING',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'This run did not receive SUPABASE_URL and SUPABASE_ANON_KEY via --dart-define.\\n\\n'
                    'Start with:\\n'
                    'flutter run -d chrome --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BioCyberOSApp extends StatefulWidget {
  const BioCyberOSApp({super.key});

  @override
  State<BioCyberOSApp> createState() => _BioCyberOSAppState();
}

class _BioCyberOSAppState extends State<BioCyberOSApp> {
  @override
  void initState() {
    super.initState();
    LocaleSettings.locale.addListener(_onLocaleChanged);
  }

  void _onLocaleChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    LocaleSettings.locale.removeListener(_onLocaleChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (ctx) => AppLocalizations.of(ctx)!.appTitle,
      theme: AppTheme.darkTheme,
      navigatorKey: navigatorKey,
      locale: LocaleSettings.locale.value,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routes: {
        '/home': (_) => AppShell(key: AppShell.shellKey),
        '/dashboard': (_) => AppShell(key: AppShell.shellKey),
        '/auth': (_) => const AuthScreen(),
      },
      home: const SplashRoute(),
    );
  }
}
