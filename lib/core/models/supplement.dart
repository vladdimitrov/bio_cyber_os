/// Row from `supplements` (macros keys may vary by schema; diet flags follow ingredients).
class Supplement {
  final String id;
  final String name;
  final double protein;
  final double carbs;
  final double fat;
  final double calories;
  final bool isGlutenFree;
  final bool lowGlycemicIndex;
  final int allergenLevel;

  const Supplement({
    required this.id,
    required this.name,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.calories,
    required this.isGlutenFree,
    required this.lowGlycemicIndex,
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

  factory Supplement.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    return Supplement(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      protein: asDouble(json['protein_per_100g'] ?? json['protein']),
      carbs: asDouble(json['carbs_per_100g'] ?? json['carbs']),
      fat: asDouble(json['fat_per_100g'] ?? json['fat']),
      calories: asDouble(json['calories_per_100g'] ?? json['calories']),
      isGlutenFree: _asBool(json['is_gluten_free']),
      lowGlycemicIndex: _asBool(json['low_glycemic_index']),
      allergenLevel: parseAllergenLevel(json['allergen_level']),
    );
  }
}
