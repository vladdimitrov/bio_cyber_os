/// Ingredient row from `ingredients` (per-100g macros + diet metadata).
class Ingredient {
  final String id;
  final String name;
  final double caloriesPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;
  final bool isGlutenFree;
  /// Glycemic Index (0–100). Null = unknown/not set.
  final int? glycemicIndex;
  /// 1–5 inclusive (higher = more allergen concern in UI).
  final int allergenLevel;

  const Ingredient({
    required this.id,
    required this.name,
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    required this.isGlutenFree,
    required this.glycemicIndex,
    required this.allergenLevel,
  });

  static bool _asBool(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    final s = v.toString().trim().toLowerCase();
    return s == 'true' || s == 't' || s == '1' || s == 'yes';
  }

  static int parseAllergenLevel(dynamic v) {
    if (v == null) return 1;
    final n = v is num ? v.toInt() : int.tryParse(v.toString()) ?? 1;
    return n.clamp(1, 5);
  }

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    int? asIntOrNull(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      return int.tryParse(s);
    }

    return Ingredient(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      caloriesPer100g: asDouble(json['calories_per_100g']),
      proteinPer100g: asDouble(json['protein_per_100g']),
      carbsPer100g: asDouble(json['carbs_per_100g']),
      fatPer100g: asDouble(json['fat_per_100g']),
      isGlutenFree: _asBool(json['is_gluten_free']),
      glycemicIndex: asIntOrNull(json['glycemic_index']),
      allergenLevel: parseAllergenLevel(json['allergen_level']),
    );
  }
}
