import 'dart:convert';

import 'package:http/http.dart' as http;

class OpenFoodFactsService {
  OpenFoodFactsService._();

  /// Returns a map with keys: name, calories, proteins, carbs, fats (per 100g).
  /// Returns null if product not found or response invalid.
  static Future<Map<String, dynamic>?> fetchByBarcode(String barcode) async {
    final code = barcode.trim();
    if (code.isEmpty) return null;

    final uri = Uri.parse(
      'https://world.openfoodfacts.org/api/v2/product/$code.json',
    );

    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;

    final json = jsonDecode(res.body);
    if (json is! Map<String, dynamic>) return null;

    final status = json['status'];
    final ok = (status is num && status.toInt() == 1) ||
        (status is String && status.trim() == '1');
    if (!ok) return null;

    final product = json['product'];
    if (product is! Map<String, dynamic>) return null;

    String s(dynamic v) => (v ?? '').toString().trim();
    double d(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    final name =
        s(product['product_name']).isNotEmpty ? s(product['product_name']) : s(product['generic_name']);
    if (name.isEmpty) return null;

    final nutr = product['nutriments'];
    final nutriments =
        (nutr is Map<String, dynamic>) ? nutr : const <String, dynamic>{};

    return <String, dynamic>{
      'name': name,
      'calories': d(nutriments['energy-kcal_100g']),
      'proteins': d(nutriments['proteins_100g']),
      'carbs': d(nutriments['carbohydrates_100g']),
      'fats': d(nutriments['fat_100g']),
    };
  }
}

