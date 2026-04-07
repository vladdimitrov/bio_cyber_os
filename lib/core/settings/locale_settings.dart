import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguagePreference { system, english, bulgarian }

/// Persists optional locale override; `null` [locale] means follow the device.
class LocaleSettings {
  LocaleSettings._();

  static const _prefKey = 'app_language_override';

  static final ValueNotifier<Locale?> locale = ValueNotifier<Locale?>(null);

  static AppLanguagePreference _preference = AppLanguagePreference.system;

  static AppLanguagePreference get preference => _preference;

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = (p.getString(_prefKey) ?? '').toLowerCase().trim();
      switch (raw) {
        case 'en':
          _preference = AppLanguagePreference.english;
          locale.value = const Locale('en');
          break;
        case 'bg':
          _preference = AppLanguagePreference.bulgarian;
          locale.value = const Locale('bg');
          break;
        default:
          _preference = AppLanguagePreference.system;
          locale.value = null;
      }
    } catch (_) {
      _preference = AppLanguagePreference.system;
      locale.value = null;
    }
  }

  static Future<void> setPreference(AppLanguagePreference pref) async {
    _preference = pref;
    switch (pref) {
      case AppLanguagePreference.system:
        locale.value = null;
        await _persist('');
        break;
      case AppLanguagePreference.english:
        locale.value = const Locale('en');
        await _persist('en');
        break;
      case AppLanguagePreference.bulgarian:
        locale.value = const Locale('bg');
        await _persist('bg');
        break;
    }
  }

  static Future<void> _persist(String code) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (code.isEmpty) {
        await p.remove(_prefKey);
      } else {
        await p.setString(_prefKey, code);
      }
    } catch (_) {}
  }
}
