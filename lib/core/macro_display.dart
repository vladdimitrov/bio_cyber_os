/// Shared P/C/F/Cal line formatting (matches Fuel ingredient search subtitles).
class MacroDisplay {
  MacroDisplay._();

  static String fmt(double v) {
    if (v.isNaN) return '0';
    final r = v.roundToDouble();
    if ((v - r).abs() < 1e-9) return r.toInt().toString();
    return v.toStringAsFixed(1);
  }

  /// One line: values can be per-100g or already scaled — formatting is identical.
  static String macroLine(
    double proteinG,
    double carbsG,
    double fatG,
    double calories,
  ) =>
      'P: ${fmt(proteinG)}g | C: ${fmt(carbsG)}g | F: ${fmt(fatG)}g | '
      '${fmt(calories)} kcal';

  static double asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  /// Scaled macros for [grams] of an ingredient row with `*_per_100g` columns.
  static ({double p, double c, double f, double cal}) scaledFromIngredientRow(
    Map<String, dynamic> ing,
    double grams,
  ) {
    final factor = grams / 100.0;
    final p = asDouble(ing['protein_per_100g']) * factor;
    final c = asDouble(ing['carbs_per_100g']) * factor;
    final f = asDouble(ing['fat_per_100g']) * factor;
    final cal = asDouble(ing['calories_per_100g']) * factor;
    return (p: p, c: c, f: f, cal: cal);
  }
}
