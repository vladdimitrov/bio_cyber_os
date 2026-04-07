import 'measurement_settings.dart';

enum UnitContext { food, supplement, medication }

class UnitOptions {
  static const _universalMedical = <String>[
    'pcs',
    'mg',
    'mcg',
    'IU',
    'drops',
    'tsp',
    'tbsp',
  ];

  static const _metric = <String>['g', 'ml', 'kg'];
  static const _imperial = <String>['oz', 'fl oz', 'lbs'];

  static List<String> forContext(
    UnitContext ctx,
    MeasurementSystem system,
  ) {
    final base = system == MeasurementSystem.imperial ? _imperial : _metric;
    if (ctx == UnitContext.food) {
      return List<String>.from(base);
    }
    final out = <String>[
      ...base,
      ..._universalMedical,
    ];
    // Keep stable order and unique.
    final seen = <String>{};
    return out.where((u) => seen.add(u)).toList(growable: false);
  }

  static String defaultUnit(UnitContext ctx, MeasurementSystem system) {
    if (ctx == UnitContext.food) {
      return system == MeasurementSystem.imperial ? 'oz' : 'g';
    }
    // Supps/Meds default.
    return 'pcs';
  }
}

