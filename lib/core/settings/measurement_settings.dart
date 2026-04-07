import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MeasurementSystem { metric, imperial }

class MeasurementSettings {
  MeasurementSettings._();

  static const _prefKey = 'measurement_system';
  static final ValueNotifier<MeasurementSystem> system =
      ValueNotifier<MeasurementSystem>(MeasurementSystem.metric);

  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = (p.getString(_prefKey) ?? '').toLowerCase().trim();
      system.value = raw == 'imperial'
          ? MeasurementSystem.imperial
          : MeasurementSystem.metric;
    } catch (_) {
      system.value = MeasurementSystem.metric;
    }
  }

  static Future<void> setSystem(MeasurementSystem next) async {
    system.value = next;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _prefKey,
        next == MeasurementSystem.imperial ? 'imperial' : 'metric',
      );
    } catch (_) {}
  }
}

