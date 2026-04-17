import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../debug/agent_debug_log.dart';
import 'locale_settings.dart';
import 'notification_settings.dart';

/// User profile settings that should be available before first render.
///
/// - Local source of truth is SharedPreferences for instant startup.
/// - Supabase hydration is best-effort and skipped when logged out.
class ProfileSettings {
  ProfileSettings._();

  // Keep in sync with Settings screen prefs keys.
  static const _kPrefHeightCm = 'profile_height_cm';
  static const _kPrefWeightKg = 'profile_weight_kg';
  static const _kPrefAge = 'profile_age';
  static const _kPrefSelectedLanguage = 'selected_language';
  static const _kPrefNotificationsEnabled = 'notifications_enabled';

  static final ValueNotifier<double?> heightCm = ValueNotifier<double?>(null);
  static final ValueNotifier<double?> weightKg = ValueNotifier<double?>(null);
  static final ValueNotifier<int?> age = ValueNotifier<int?>(null);
  static final ValueNotifier<String> selectedLanguage =
      ValueNotifier<String>(''); // '' = system
  static final ValueNotifier<bool> notificationsEnabled =
      ValueNotifier<bool>(false);

  static bool _loadedLocal = false;
  static final Map<String, Object?> _memFallback = <String, Object?>{};

  static double? _parseOptionalDouble(String v) {
    final t = v.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  static Future<void> loadLocal() async {
    if (_loadedLocal) return;
    _loadedLocal = true;
    try {
      final p = await SharedPreferences.getInstance();
      heightCm.value = _parseOptionalDouble(p.getString(_kPrefHeightCm) ?? '');
      weightKg.value = _parseOptionalDouble(p.getString(_kPrefWeightKg) ?? '');
      age.value = int.tryParse((p.getString(_kPrefAge) ?? '').trim());
      selectedLanguage.value = (p.getString(_kPrefSelectedLanguage) ?? '').trim();
      notificationsEnabled.value =
          p.getBool(_kPrefNotificationsEnabled) ?? false;

      // Apply to app-level providers (no UI layout changes).
      if (selectedLanguage.value.isNotEmpty) {
        final pref = selectedLanguage.value == 'bg'
            ? AppLanguagePreference.bulgarian
            : AppLanguagePreference.english;
        await LocaleSettings.setPreference(pref);
      }
      await NotificationSettings.load();
      if (NotificationSettings.enabled.value != notificationsEnabled.value) {
        await NotificationSettings.setEnabled(notificationsEnabled.value);
      }

      // #region agent log
      AgentDebugLog.log(
        runId: 'pre-fix',
        hypothesisId: 'H1',
        location: 'lib/core/settings/profile_settings.dart:loadLocal',
        message: 'Loaded profile from SharedPreferences',
        data: {
          'has_height_key': p.containsKey(_kPrefHeightCm),
          'has_weight_key': p.containsKey(_kPrefWeightKg),
          'heightCm': heightCm.value,
          'weightKg': weightKg.value,
          'selected_language': selectedLanguage.value,
          'notifications_enabled': notificationsEnabled.value,
        },
      );
      // #endregion
    } catch (_) {
      // Fallback for web/storage failures: use in-memory cache.
      heightCm.value =
          _parseOptionalDouble((_memFallback[_kPrefHeightCm] ?? '').toString());
      weightKg.value =
          _parseOptionalDouble((_memFallback[_kPrefWeightKg] ?? '').toString());
      age.value = int.tryParse((_memFallback[_kPrefAge] ?? '').toString().trim());
      selectedLanguage.value =
          (_memFallback[_kPrefSelectedLanguage] ?? '').toString().trim();
      final n = _memFallback[_kPrefNotificationsEnabled];
      notificationsEnabled.value = n is bool ? n : false;
    }
  }

  static Future<void> setLocal({
    double? heightCm,
    double? weightKg,
    int? age,
    String? selectedLanguage,
    bool? notificationsEnabled,
  }) async {
    ProfileSettings.heightCm.value = heightCm;
    ProfileSettings.weightKg.value = weightKg;
    ProfileSettings.age.value = age;
    if (selectedLanguage != null) {
      ProfileSettings.selectedLanguage.value = selectedLanguage;
    }
    if (notificationsEnabled != null) {
      ProfileSettings.notificationsEnabled.value = notificationsEnabled;
    }
    try {
      final p = await SharedPreferences.getInstance();
      if (kIsWeb) {
        await p.reload();
      }

      final nextH = heightCm?.toString() ?? '';
      final nextW = weightKg?.toString() ?? '';
      final nextAge = age?.toString() ?? '';
      final nextLang = ProfileSettings.selectedLanguage.value;
      final nextNotif = ProfileSettings.notificationsEnabled.value;

      final okH = await p.setString(_kPrefHeightCm, nextH);
      final okW = await p.setString(_kPrefWeightKg, nextW);
      final okAge = await p.setString(_kPrefAge, nextAge);
      final okLang = await p.setString(
        _kPrefSelectedLanguage,
        nextLang,
      );
      final okNotif = await p.setBool(
        _kPrefNotificationsEnabled,
        nextNotif,
      );
      if (!okH || !okW || !okAge || !okLang || !okNotif) {
        _memFallback[_kPrefHeightCm] = nextH;
        _memFallback[_kPrefWeightKg] = nextW;
        _memFallback[_kPrefAge] = nextAge;
        _memFallback[_kPrefSelectedLanguage] = nextLang;
        _memFallback[_kPrefNotificationsEnabled] = nextNotif;
        debugPrint(
          'DEBUG: SharedPreferences save returned false (web=$kIsWeb) '
          'height=$okH weight=$okW age=$okAge lang=$okLang notif=$okNotif',
        );
      }
    } catch (_) {}
  }

  /// Best-effort remote hydration. Also updates local prefs.
  static Future<Map<String, dynamic>?> hydrateFromSupabase() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) {
      // #region agent log
      AgentDebugLog.log(
        runId: 'pre-fix',
        hypothesisId: 'H2',
        location: 'lib/core/settings/profile_settings.dart:hydrateFromSupabase',
        message: 'Skipped Supabase hydration (uid is null)',
      );
      // #endregion
      return null;
    }
    try {
      final row = await client
          .from('profiles')
          .select('height_cm, weight_kg, selected_language, notifications_enabled')
          .eq('id', uid)
          .maybeSingle();
      if (row == null) return null;
      final h = row['height_cm'];
      final w = row['weight_kg'];
      final lang = (row['selected_language'] ?? '').toString().trim();
      final notifRaw = row['notifications_enabled'];
      final notif = notifRaw is bool
          ? notifRaw
          : (notifRaw is num
              ? notifRaw != 0
              : (notifRaw?.toString().toLowerCase() == 'true'));
      final hCm = h is num ? h.toDouble() : double.tryParse('$h');
      final wKg = w is num ? w.toDouble() : double.tryParse('$w');
      // Local fallback: never wipe local cached values with nulls from Supabase.
      await setLocal(
        heightCm: hCm ?? heightCm.value,
        weightKg: wKg ?? weightKg.value,
        selectedLanguage: lang.isEmpty ? ProfileSettings.selectedLanguage.value : lang,
        notificationsEnabled: notif,
      );

      if (lang.isNotEmpty) {
        await LocaleSettings.setPreference(
          lang == 'bg' ? AppLanguagePreference.bulgarian : AppLanguagePreference.english,
        );
      }
      await NotificationSettings.load();
      if (NotificationSettings.enabled.value != notif) {
        await NotificationSettings.setEnabled(notif);
      }

      // #region agent log
      AgentDebugLog.log(
        runId: 'pre-fix',
        hypothesisId: 'H3',
        location: 'lib/core/settings/profile_settings.dart:hydrateFromSupabase',
        message: 'Hydrated profile from Supabase and updated local cache',
        data: {
          'uid_present': true,
          'height_cm': hCm,
          'weight_kg': wKg,
          'selected_language': lang,
          'notifications_enabled': notif,
          'row_keys': row.keys.toList(),
        },
      );
      // #endregion
      return Map<String, dynamic>.from(row);
    } catch (_) {}
    return null;
  }

  /// Ensure a row exists for the current user.
  ///
  /// This is safe to call after login/biometric restore. It never blocks app
  /// navigation; failures are swallowed (but can be logged by callers).
  static Future<void> ensureRemoteProfileRow() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await client.from('profiles').upsert({'id': uid}, onConflict: 'id');
    } catch (_) {}
  }
}

