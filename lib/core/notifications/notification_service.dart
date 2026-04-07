import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:convert';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'in_app_reminder_dispatcher.dart';
import '../settings/notification_settings.dart';
import 'web_notification_permissions_stub.dart'
    if (dart.library.html) 'web_notification_permissions_web.dart';

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _inited = false;

  static bool get _nativeSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Stable, non-cryptographic -> 31-bit positive int.
  static int hashId(String s) {
    var h = 0;
    for (final cu in s.codeUnits) {
      h = 0x1fffffff & (h * 31 + cu);
    }
    return h & 0x7fffffff;
  }

  static Future<void> init() async {
    if (_inited) return;
    _inited = true;

    await NotificationSettings.load();

    if (!_nativeSupported) {
      InAppReminderDispatcher.init();
      return;
    }

    tz.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings();
    const windowsInit = WindowsInitializationSettings(
      appName: 'BIO_CYBER OS',
      // Stable identifiers for Windows toast notifications.
      appUserModelId: 'com.biocyber.os',
      guid: '2b8a8c3e-7d7b-4af2-9fd8-9a7a46b3f3e1',
    );
    const linuxInit = LinuxInitializationSettings(
      defaultActionName: 'Open',
    );

    const settings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
      windows: windowsInit,
      linux: linuxInit,
    );

    await _plugin.initialize(settings);

    // Create the Android channel up front.
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        'reminders',
        'Reminders',
        description: 'Food/Supps/Meds reminders',
        importance: Importance.max,
      ),
    );
  }

  /// Best-effort permission request. Returns true if granted/available.
  static Future<bool> requestPermissionIfNeeded(BuildContext context) async {
    await init();

    if (kIsWeb) {
      final ok = await requestWebNotificationPermission();
      return ok;
    }

    if (!_nativeSupported) {
      // Desktop: in-app reminders don't require OS permissions.
      return true;
    }

    bool? granted;

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      granted = await android.requestNotificationsPermission();
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      granted = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    final mac = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    if (mac != null) {
      granted = await mac.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    // Windows/Linux: no runtime permission prompt in most setups.
    granted ??= true;

    if (granted != true && context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF050510),
          shape:
              const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: const Text(
            'NOTIFICATIONS DISABLED',
            style: TextStyle(
              color: Color(0xFF00F3FF),
              fontFamily: 'monospace',
              fontWeight: FontWeight.w800,
            ),
          ),
          content: const Text(
            'Reminders help keep your protocol consistent.\n\n'
            'Please enable notifications in system settings to receive intake reminders.',
            style: TextStyle(
              color: Color(0xFF00F3FF),
              fontFamily: 'monospace',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }

    return granted == true;
  }

  static Future<void> cancelByKey(String key) async {
    await init();
    if (_nativeSupported) {
      await _plugin.cancel(hashId(key));
    } else {
      await InAppReminderDispatcher.cancel(key);
    }
  }

  static Future<void> scheduleByKey({
    required String key,
    required String title,
    required String body,
    required DateTime whenLocal,
    Map<String, dynamic>? payload,
  }) async {
    await init();

    if (!NotificationSettings.enabled.value) return;

    final now = DateTime.now();
    if (!whenLocal.isAfter(now)) return;

    if (!_nativeSupported) {
      await InAppReminderDispatcher.schedule(
        key: key,
        title: title,
        body: body,
        whenLocal: whenLocal,
        payload: payload,
      );
      // ignore: avoid_print
      print(
        'DEBUG: In-app reminder scheduled for ${whenLocal.toIso8601String()} with content "$title" | "$body"',
      );
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription: 'Food/Supps/Meds reminders',
      importance: Importance.max,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    final when = tz.TZDateTime.from(whenLocal, tz.local);
    await _plugin.zonedSchedule(
      hashId(key),
      title,
      body,
      when,
      details,
      payload: payload == null ? null : jsonEncode(payload),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: null,
    );

    // DEBUG LOGGING
    // ignore: avoid_print
    print(
      'DEBUG: Notification scheduled for ${whenLocal.toIso8601String()} with content "$title" | "$body"',
    );
  }
}

