class FoodItem {
  final String id;
  final String name;
  final bool isRecipe;
  final int calories;
  final double proteinG;
  final double carbsG;
  final double fatsG;
  final double fiberG;
  /// Owner; matches `food_items.user_id` in Supabase (formerly `created_by`).
  final String? userId;

  const FoodItem({
    required this.id,
    required this.name,
    required this.isRecipe,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatsG,
    required this.fiberG,
    this.userId,
  });

  factory FoodItem.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    int asInt(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    bool asBool(dynamic v) {
      if (v == null) return false;
      if (v is bool) return v;
      final s = v.toString().toLowerCase();
      return s == 'true' || s == '1';
    }

    final ownerId = json['user_id'];
    return FoodItem(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      isRecipe: asBool(json['is_recipe']),
      calories: asInt(json['calories']),
      proteinG: asDouble(json['protein_g']),
      carbsG: asDouble(json['carbs_g']),
      fatsG: asDouble(json['fats_g']),
      fiberG: asDouble(json['fiber_g']),
      userId: ownerId?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'is_recipe': isRecipe,
        'calories': calories,
        'protein_g': proteinG,
        'carbs_g': carbsG,
        'fats_g': fatsG,
        'fiber_g': fiberG,
        if (userId != null) 'user_id': userId,
      };
}
