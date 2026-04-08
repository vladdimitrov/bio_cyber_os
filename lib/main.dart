import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bio_cyber_os/l10n/app_localizations.dart';

import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'core/bootstrap/user_bootstrap.dart';
import 'core/debug/agent_debug_log.dart';
import 'core/notifications/notification_service.dart';
import 'core/navigation/app_navigator.dart';
import 'core/settings/locale_settings.dart';
import 'core/settings/measurement_settings.dart';
import 'core/settings/notification_settings.dart';
import 'core/settings/profile_settings.dart';
import 'features/auth/screens/splash_route.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AgentDebugLog.ensureInitialized();

  // Avoid hard-crashing in debug/web when --dart-define is missing.
  // Instead, show a clear configuration screen.
  if (AppConfig.supabaseUrl.isEmpty || AppConfig.supabaseAnonKey.isEmpty) {
    // ignore: avoid_print
    print(
      'DEBUG: Missing SUPABASE_URL / SUPABASE_ANON_KEY. '
      'Run with --dart-define SUPABASE_URL=... and SUPABASE_ANON_KEY=...',
    );
    runApp(const _MissingSupabaseConfigApp());
    return;
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  // Safe no-op on web; initializes on supported platforms.
  await NotificationService.init();
  await MeasurementSettings.load();
  await NotificationSettings.load();
  await LocaleSettings.load();
  await ProfileSettings.loadLocal();
  await UserBootstrap.initialize();
  // STARTUP TRACE (deep debug)
  // ignore: avoid_print
  print('DEBUG: Startup - Loading user profile from Supabase...');
  // #region agent log
  AgentDebugLog.log(
    runId: 'pre-fix',
    hypothesisId: 'H3',
    location: 'lib/main.dart:startup',
    message: 'Startup begin: loaded local profile prefs',
    data: {
      'heightCm_local': ProfileSettings.heightCm.value,
      'weightKg_local': ProfileSettings.weightKg.value,
      'uid_present': Supabase.instance.client.auth.currentUser?.id != null,
    },
  );
  // #endregion

  final data = await ProfileSettings.hydrateFromSupabase();
  // ignore: avoid_print
  print('DEBUG: Startup - Profile data received: $data');
  // #region agent log
  AgentDebugLog.log(
    runId: 'pre-fix',
    hypothesisId: 'H3',
    location: 'lib/main.dart:startup',
    message: 'Startup: Supabase profile hydration result',
    data: {
      'row_null': data == null,
      'row_keys': data?.keys.toList(),
    },
  );
  // #endregion

  runApp(const BioCyberOSApp());
}

class _MissingSupabaseConfigApp extends StatelessWidget {
  const _MissingSupabaseConfigApp();

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    return const MaterialApp(
      home: Scaffold(
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
      navigatorKey: AppNavigator.key,
      locale: LocaleSettings.locale.value,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SplashRoute(),
    );
  }
}
