import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bio_cyber_os/l10n/app_localizations.dart';

import 'core/theme/app_theme.dart';
import 'core/bootstrap/user_bootstrap.dart';
import 'core/notifications/notification_service.dart';
import 'core/navigation/app_navigator.dart';
import 'core/settings/locale_settings.dart';
import 'core/settings/measurement_settings.dart';
import 'core/settings/notification_settings.dart';
import 'features/auth/screens/splash_route.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://rzelkxhvqetcyphvftrn.supabase.co',
    anonKey: 'sb_publishable_QEY9ksuDlIJ7bDs0xGQs-g_dlgknaSn',
  );

  // Safe no-op on web; initializes on supported platforms.
  await NotificationService.init();
  await MeasurementSettings.load();
  await NotificationSettings.load();
  await LocaleSettings.load();
  await UserBootstrap.initialize();

  runApp(const BioCyberOSApp());
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
