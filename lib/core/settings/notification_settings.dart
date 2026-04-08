import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationSettings {
  NotificationSettings._();

  static const _prefKey = 'notifications_enabled';
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      enabled.value = p.getBool(_prefKey) ?? false;
    } catch (_) {
      enabled.value = false;
    }
  }

  static Future<void> setEnabled(bool next) async {
    enabled.value = next;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_prefKey, next);
    } catch (_) {}

    // Best-effort: also persist preference remotely for the signed-in user.
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) return;
      await client.from('profiles').upsert(
        {
          'id': uid,
          'notifications_enabled': next,
        },
        onConflict: 'id',
      );
    } catch (_) {}
  }
}

