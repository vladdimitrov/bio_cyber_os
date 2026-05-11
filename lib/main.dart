import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:bio_cyber_os/l10n/app_localizations.dart';

import 'core/config/app_config.dart';
import 'core/supabase/library_schema_probe.dart';
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

  // Required for tz.TZDateTime scheduling on Android/iOS.
  tzdata.initializeTimeZones();
  // Hard force Sofia for deterministic local scheduling.
  // (We still attempt to read native timezone below.)
  tz.setLocalLocation(tz.getLocation('Europe/Sofia'));
  debugPrint(
    '🌍 TIMEZONE_SYNC: Local time is now ${tz.TZDateTime.now(tz.local)}',
  );

  // Force tz.local to match the device timezone (fixes tz.local returning UTC).
  try {
    final String timeZoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timeZoneName));
    // ignore: avoid_print
    print('🛠️ DEBUG: Timezone set to $timeZoneName');
    debugPrint('🛠️ DEBUG: tz.local.name=${tz.local.name}');
    debugPrint(
      '🛠️ DEBUG: tz.now=${tz.TZDateTime.now(tz.local)} offset=${tz.TZDateTime.now(tz.local).timeZoneOffset}',
    );
  } catch (e) {
    debugPrint('DEBUG: FlutterTimezone.getLocalTimezone failed: $e');
  }

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await AndroidAlarmManager.initialize();
    } catch (e) {
      debugPrint('DEBUG: AndroidAlarmManager.initialize failed: $e');
    }
  }

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

  if (kDebugMode) {
    unawaited(
      LibrarySchemaProbe.verifyBarcodeColumnsVisible(Supabase.instance.client),
    );
  }

  try {
    await NotificationService.init();
  } catch (e, st) {
    debugPrint('DEBUG: NotificationService.init failed: $e $st');
  }

  // Best-effort startup permissions for Android reminders.
  // - POST_NOTIFICATIONS (Android 13+)
  // - SCHEDULE_EXACT_ALARM (Android 12+ app-op)
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final notif = await Permission.notification.status;
      if (notif.isDenied || notif.isRestricted) {
        await Permission.notification.request();
      }
    } catch (e) {
      debugPrint('DEBUG: Permission.notification request failed: $e');
    }
    try {
      final overlay = await Permission.systemAlertWindow.status;
      if (overlay.isDenied || overlay.isRestricted) {
        await Permission.systemAlertWindow.request();
      }
    } catch (e) {
      debugPrint('DEBUG: Permission.systemAlertWindow request failed: $e');
    }
    try {
      final exact = await Permission.scheduleExactAlarm.status;
      if (exact.isDenied || exact.isRestricted) {
        debugPrint('⚠️ WARNING: Exact Alarms DENIED.');
        await Permission.scheduleExactAlarm.request();
      }
    } catch (e) {
      debugPrint('DEBUG: Permission.scheduleExactAlarm request failed: $e');
    }
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
  StreamSubscription<AuthState>? _rootAuthSub;

  /// When true, [MaterialApp.home] is [AppShell] so sign-in (e.g. biometrics) cannot
  /// leave the user stuck under a nested [AuthScreen] route.
  bool _rootShowsShell = false;

  @override
  void initState() {
    super.initState();
    _rootShowsShell =
        Supabase.instance.client.auth.currentSession != null;
    _rootAuthSub =
        Supabase.instance.client.auth.onAuthStateChange.listen(_onRootAuth);
    LocaleSettings.locale.addListener(_onLocaleChanged);
  }

  void _onRootAuth(AuthState state) {
    final e = state.event;
    if (e == AuthChangeEvent.passwordRecovery ||
        e.toString().toLowerCase().contains('passwordrecovery')) {
      if (mounted) setState(() => _rootShowsShell = false);
      return;
    }
    if (e == AuthChangeEvent.signedOut) {
      if (mounted) setState(() => _rootShowsShell = false);
      return;
    }
    if (e == AuthChangeEvent.signedIn && state.session != null) {
      if (mounted) setState(() => _rootShowsShell = true);
      return;
    }
    if (e == AuthChangeEvent.initialSession) {
      if (mounted) {
        setState(() => _rootShowsShell = state.session != null);
      }
    }
  }

  void _onLocaleChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _rootAuthSub?.cancel();
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
      // Signed-in users: root is [AppShell] (global auth listener). Otherwise
      // [SplashRoute] handles splash / auth / password recovery flows.
      home: _rootShowsShell
          ? AppShell(key: AppShell.shellKey)
          : const SplashRoute(),
    );
  }
}
