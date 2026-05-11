import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'in_app_reminder_dispatcher.dart';
import '../settings/notification_settings.dart';
import 'web_notification_permissions_stub.dart'
    if (dart.library.html) 'web_notification_permissions_web.dart';

/// Parameters for [NotificationService.scheduleUniversal].
class UniversalReminder {
  const UniversalReminder({
    required this.key,
    required this.title,
    required this.body,
    required this.whenLocal,
    this.payload,
    this.alarmItemName,
    this.alarmAmount,
    this.alarmUnit,
  });

  final String key;
  final String title;
  final String body;
  final DateTime whenLocal;
  final Map<String, dynamic>? payload;

  /// Serialized for [AndroidAlarmManager] isolate + SharedPreferences backup.
  final String? alarmItemName;
  final String? alarmAmount;
  final String? alarmUnit;
}

@pragma('vm:entry-point')
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _inited = false;

  /// New channel id — Android will not upgrade an existing channel's importance.
  static const String _androidChannelId = 'vitality_system_alerts';
  static const String _androidChannelName = 'Vitality System Alerts';
  static const String _androidChannelDesc =
      'Critical reminders for health protocols';

  static const AndroidNotificationDetails _androidReminderDetails =
      AndroidNotificationDetails(
    _androidChannelId,
    _androidChannelName,
    channelDescription: _androidChannelDesc,
    importance: Importance.max,
    priority: Priority.max,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.alarm,
    visibility: NotificationVisibility.public,
    playSound: true,
    enableVibration: true,
    audioAttributesUsage: AudioAttributesUsage.alarm,
  );

  static const DarwinNotificationDetails _darwinDetails =
      DarwinNotificationDetails();

  static const NotificationDetails _reminderDetails = NotificationDetails(
    android: _androidReminderDetails,
    iOS: _darwinDetails,
    macOS: _darwinDetails,
  );

  static String _alarmPayloadKey(int id) => 'vitality_os_alarm_payload_$id';
  static String _lastNotifyKey(int id) => 'vitality_os_last_notify_$id';

  static Future<void> _writeAlarmPayloadPref(
    int id,
    String title,
    String body,
    Map<String, dynamic>? payload, {
    String? alarmItemName,
    String? alarmAmount,
    String? alarmUnit,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _alarmPayloadKey(id),
      jsonEncode({
        'title': title,
        'body': body,
        if (alarmItemName != null && alarmItemName.isNotEmpty)
          'item_name': alarmItemName,
        if (alarmAmount != null && alarmAmount.isNotEmpty) 'amount': alarmAmount,
        if (alarmUnit != null && alarmUnit.isNotEmpty) 'unit': alarmUnit,
        if (payload != null) 'payload': jsonEncode(payload),
      }),
    );
  }

  static String? _stringFromDynamic(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    return v.toString();
  }

  static String _bodyFromAlarmParts(
    String? itemName,
    String? amount,
    String? unit,
  ) {
    final name = (itemName ?? '').trim();
    final a = (amount ?? '').trim();
    final u = (unit ?? '').trim();
    if (name.isEmpty) return '';
    if (a.isEmpty && u.isEmpty) return name;
    if (u.isEmpty) return '$name - $a';
    return '$name - $a $u';
  }

  /// True if this [id] was shown from our code paths within the last 2 seconds.
  static Future<bool> _recentlyNotifiedSameId(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final last =
        int.tryParse(prefs.getString(_lastNotifyKey(id)) ?? '') ?? 0;
    return last > 0 && now - last < 2000;
  }

  static Future<void> _markNotified(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _lastNotifyKey(id),
      '${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  @pragma('vm:entry-point')
  static Future<void> _alarmManagerFire(
    int id,
    Map<String, dynamic> params,
  ) async {
    WidgetsFlutterBinding.ensureInitialized();
    // Called from AndroidAlarmManager background isolate.
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidInit);
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(settings);

    if (await _recentlyNotifiedSameId(id)) {
      debugPrint('🛠️ REMINDER_CHECK: Dedupe skip AlarmManager id=$id');
      return;
    }

    try {
      await plugin.cancel(id);
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    var title = _stringFromDynamic(params['title'])?.trim() ?? '';
    var body = _stringFromDynamic(params['body']) ?? '';

    String? itemName = _stringFromDynamic(params['item_name']);
    String? amount = _stringFromDynamic(params['amount']);
    String? unit = _stringFromDynamic(params['unit']);

    final raw = prefs.getString(_alarmPayloadKey(id));
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        if (title.isEmpty) {
          final t = _stringFromDynamic(map['title'])?.trim();
          if (t != null && t.isNotEmpty) title = t;
        }
        if (body.isEmpty) {
          final b = _stringFromDynamic(map['body']);
          if (b != null) body = b;
        }
        itemName ??= _stringFromDynamic(map['item_name']);
        amount ??= _stringFromDynamic(map['amount']);
        unit ??= _stringFromDynamic(map['unit']);
      } catch (_) {}
    }

    if (body.isEmpty) {
      body = _bodyFromAlarmParts(itemName, amount, unit);
    }
    if (title.isEmpty) {
      title = 'Vitality Calendar';
    }

    debugPrint('🛠️ REMINDER_CHECK: AlarmManager FIRE id=$id');
    await plugin.show(
      id,
      title,
      body,
      _reminderDetails,
    );
    await _markNotified(id);
    try {
      await prefs.remove(_alarmPayloadKey(id));
    } catch (_) {}
  }

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

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings();
    const windowsInit = WindowsInitializationSettings(
      appName: 'BIO_CYBER OS',
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

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (resp) {
        debugPrint(
          'DEBUG: onDidReceiveNotificationResponse actionId=${resp.actionId} '
          'payload=${resp.payload} input=${resp.input}',
        );
      },
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _androidChannelId,
        _androidChannelName,
        description: _androidChannelDesc,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );
  }

  static Future<void> _promptExactAlarmSettings(BuildContext context) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF050510),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Text(
          'EXACT ALARMS OFF',
          style: TextStyle(
            color: Color(0xFF00F3FF),
            fontFamily: 'monospace',
            fontWeight: FontWeight.w800,
          ),
        ),
        content: const Text(
          'Reminders need exact alarms so they fire on time (especially on Pixel / Android 14+).\n\n'
          'Open system settings and allow “Alarms & reminders” (or “Schedule exact alarm”) for this app.',
          style: TextStyle(
            color: Color(0xFF00F3FF),
            fontFamily: 'monospace',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('NOT NOW'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await openAppSettings();
            },
            child: const Text('OPEN SETTINGS'),
          ),
        ],
      ),
    );
  }

  /// Best-effort permission request. Returns true if notifications are enabled.
  static Future<bool> requestPermissionIfNeeded(BuildContext context) async {
    await init();

    if (kIsWeb) {
      final ok = await requestWebNotificationPermission();
      return ok;
    }

    if (!_nativeSupported) {
      return true;
    }

    bool? granted;

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      granted = await android.requestNotificationsPermission();

      try {
        await android.requestExactAlarmsPermission();
      } catch (_) {}

      try {
        var exactStatus = await Permission.scheduleExactAlarm.status;
        if (exactStatus.isDenied || exactStatus.isRestricted) {
          await Permission.scheduleExactAlarm.request();
          exactStatus = await Permission.scheduleExactAlarm.status;
        }
        if (context.mounted &&
            (exactStatus.isDenied || exactStatus.isRestricted)) {
          await _promptExactAlarmSettings(context);
        }
      } catch (_) {}

      try {
        await android.requestFullScreenIntentPermission();
      } catch (_) {}
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
    final id = hashId(key);
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await AndroidAlarmManager.cancel(id);
      } catch (_) {}
    }
    if (_nativeSupported) {
      await _plugin.cancel(id);
    } else {
      await InAppReminderDispatcher.cancel(key);
    }
  }

  /// Dual-trigger Android: [zonedSchedule] + [AndroidAlarmManager.oneShotAt].
  /// iOS / desktop: zoned or in-app only.
  static Future<void> scheduleUniversal(UniversalReminder reminder) async {
    await init();

    if (!NotificationSettings.enabled.value) return;

    try {
      tz.setLocalLocation(tz.getLocation('Europe/Sofia'));
    } catch (_) {}
    debugPrint(
      '🌍 TIMEZONE_SYNC: Local time is now ${tz.TZDateTime.now(tz.local)}',
    );

    final targetLocal = reminder.whenLocal.isUtc
        ? reminder.whenLocal.toLocal()
        : reminder.whenLocal;
    final tzNow = tz.TZDateTime.now(tz.local);
    final scheduledDateTime = tz.TZDateTime.from(targetLocal, tz.local);
    if (!scheduledDateTime.isAfter(tzNow)) return;

    if (!_nativeSupported) {
      await InAppReminderDispatcher.schedule(
        key: reminder.key,
        title: reminder.title,
        body: reminder.body,
        whenLocal: targetLocal,
        payload: reminder.payload,
      );
      // ignore: avoid_print
      print(
        'DEBUG: In-app reminder scheduled for ${targetLocal.toIso8601String()} with content "${reminder.title}" | "${reminder.body}"',
      );
      return;
    }

    final id = hashId(reminder.key);
    final payloadStr =
        reminder.payload == null ? null : jsonEncode(reminder.payload);

    Future<void> registerAndroidAlarmBackup() async {
      final alarmParams = <String, dynamic>{
        'title': reminder.title,
        'body': reminder.body,
        if (reminder.alarmItemName != null &&
            reminder.alarmItemName!.trim().isNotEmpty)
          'item_name': reminder.alarmItemName!.trim(),
        if (reminder.alarmAmount != null &&
            reminder.alarmAmount!.trim().isNotEmpty)
          'amount': reminder.alarmAmount!.trim(),
        if (reminder.alarmUnit != null && reminder.alarmUnit!.trim().isNotEmpty)
          'unit': reminder.alarmUnit!.trim(),
      };
      try {
        await AndroidAlarmManager.oneShotAt(
          scheduledDateTime,
          id,
          _alarmManagerFire,
          exact: true,
          wakeup: true,
          allowWhileIdle: true,
          params: alarmParams,
        );
        debugPrint(
          '🛠️ REMINDER_CHECK: Universal dual — AlarmManager backup id=$id at=$scheduledDateTime',
        );
      } catch (e) {
        debugPrint('🛠️ REMINDER_CHECK: AlarmManager oneShotAt failed: $e');
      }
    }

    Future<void> doZoned(AndroidScheduleMode mode) async {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      bool? enabled;
      try {
        enabled = await android?.areNotificationsEnabled();
      } catch (_) {
        enabled = null;
      }
      final exactSt = await Permission.scheduleExactAlarm.status;
      final notifSt = await Permission.notification.status;
      debugPrint(
        '🛠️ REMINDER_CHECK: Device Time: ${tz.TZDateTime.now(tz.local)}',
      );
      debugPrint('🛠️ REMINDER_CHECK: Scheduling for: $scheduledDateTime');
      debugPrint('🛠️ REMINDER_CHECK: Notification ID: $id');
      debugPrint('🚀 PIXEL_LOG: Reminder set for $scheduledDateTime');
      debugPrint(
        '🛠️ REMINDER_CHECK: tz.local=${tz.local.name} '
        'offset=${tz.TZDateTime.now(tz.local).timeZoneOffset} '
        'notifEnabled=$enabled exactAlarm=$exactSt postNotif=$notifSt',
      );

      await _plugin.zonedSchedule(
        id,
        reminder.title,
        reminder.body,
        scheduledDateTime,
        _reminderDetails,
        payload: payloadStr,
        androidScheduleMode: mode,
        matchDateTimeComponents: null,
      );

      try {
        final pending = await _plugin.pendingNotificationRequests();
        debugPrint(
          '🛠️ REMINDER_CHECK: pendingNotificationRequests=${pending.length} '
          '(containsThisId=${pending.any((p) => p.id == id)})',
        );
      } catch (e) {
        debugPrint('🛠️ REMINDER_CHECK: pendingNotificationRequests failed: $e');
      }
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      await _writeAlarmPayloadPref(
        id,
        reminder.title,
        reminder.body,
        reminder.payload,
        alarmItemName: reminder.alarmItemName,
        alarmAmount: reminder.alarmAmount,
        alarmUnit: reminder.alarmUnit,
      );
    }

    // Trigger 1: OS-scheduled notification (all platforms).
    try {
      await doZoned(AndroidScheduleMode.exactAllowWhileIdle);
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print(
        'DEBUG: Notification schedule PlatformException: ${e.code} ${e.message}',
      );
      try {
        await doZoned(AndroidScheduleMode.inexactAllowWhileIdle);
      } catch (e2) {
        // ignore: avoid_print
        print('DEBUG: Notification schedule failed after fallback: $e2');
        if (defaultTargetPlatform != TargetPlatform.android) {
          return;
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('DEBUG: Notification schedule failed: $e');
      if (defaultTargetPlatform != TargetPlatform.android) {
        return;
      }
    }

    // Trigger 2: AlarmManager backup (Android only), synchronized to same [id] and time.
    if (defaultTargetPlatform == TargetPlatform.android) {
      await registerAndroidAlarmBackup();
    }

    // ignore: avoid_print
    print(
      'DEBUG: Notification scheduled for ${targetLocal.toIso8601String()} with content "${reminder.title}" | "${reminder.body}"',
    );
  }

  static Future<void> scheduleByKey({
    required String key,
    required String title,
    required String body,
    required DateTime whenLocal,
    Map<String, dynamic>? payload,
    String? alarmItemName,
    String? alarmAmount,
    String? alarmUnit,
  }) =>
      scheduleUniversal(
        UniversalReminder(
          key: key,
          title: title,
          body: body,
          whenLocal: whenLocal,
          payload: payload,
          alarmItemName: alarmItemName,
          alarmAmount: alarmAmount,
          alarmUnit: alarmUnit,
        ),
      );

  static Future<void> scheduleTestIn5Seconds({
    required String key,
    required String title,
    required String body,
  }) async {
    await init();
    if (!NotificationSettings.enabled.value) return;
    if (!_nativeSupported) return;

    final now = tz.TZDateTime.now(tz.local);
    final scheduledDateTime = now.add(const Duration(seconds: 5));
    debugPrint('🔔 TZ.LOCAL: ${tz.local.name} offset=${now.timeZoneOffset}');
    debugPrint('🔔 ACTUAL LOCAL TIME: ${now.toString()}');
    debugPrint('🔔 ACTUAL TARGET TIME: ${scheduledDateTime.toString()}');

    await scheduleUniversal(
      UniversalReminder(
        key: key,
        title: title,
        body: body,
        whenLocal: scheduledDateTime,
      ),
    );
  }

  static Future<void> showDebugNow({
    required String key,
    required String title,
    required String body,
  }) async {
    await init();
    if (!NotificationSettings.enabled.value) return;
    if (!_nativeSupported) return;

    final id = hashId(key);
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    debugPrint(
      '🛠️ REMINDER_CHECK: showNow START tz.local=${tz.local.name} '
      'now=${tz.TZDateTime.now(tz.local)} notifEnabled=${await android?.areNotificationsEnabled()}',
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      if (await _recentlyNotifiedSameId(id)) {
        debugPrint('🛠️ REMINDER_CHECK: Dedupe skip showDebugNow id=$id');
        return;
      }
    }

    debugPrint(
      '🛠️ REMINDER_CHECK: showNow id=$id tz.local=${tz.local.name} now=${tz.TZDateTime.now(tz.local)}',
    );
    await _plugin.show(
      id,
      title,
      body,
      _reminderDetails,
    );
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _markNotified(id);
    }
  }
}
