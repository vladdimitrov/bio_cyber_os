import 'dart:convert';

import 'package:http/http.dart' as http;

import 'open_food_facts_service.dart';

/// Mirrors library barcode tabs for conditional OpenFDA / DSLD lookups.
enum GlobalBarcodeLibraryTab { ingredients, supplements, medications }

/// External catalog hit normalized for UI + optional Supabase import.
class GlobalCatalogProduct {
  final String sourceKey;
  final String sourceLabel;
  final String name;
  final String? brand;
  /// Combined text used for protocol keyword scan and persistence.
  final String ingredientsSearchText;
  final double calories;
  final double proteins;
  final double carbs;
  final double fats;

  const GlobalCatalogProduct({
    required this.sourceKey,
    required this.sourceLabel,
    required this.name,
    required this.brand,
    required this.ingredientsSearchText,
    required this.calories,
    required this.proteins,
    required this.carbs,
    required this.fats,
  });

  /// Shape compatible with `_IngredientDialog` / import flows (extends OFF map).
  Map<String, dynamic> toCatalogMap() {
    return <String, dynamic>{
      'source': sourceKey,
      'source_label': sourceLabel,
      'name': name,
      'brand': brand ?? '',
      'ingredients_text': ingredientsSearchText,
      'calories': calories,
      'proteins': proteins,
      'carbs': carbs,
      'fats': fats,
    };
  }

  static GlobalCatalogProduct? fromOpenFoodFactsMap(Map<String, dynamic> m) {
    final name = (m['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    final brand = (m['brand'] ?? '').toString().trim();
    final ing = (m['ingredients_text'] ?? '').toString().trim();
    return GlobalCatalogProduct(
      sourceKey: 'open_food_facts',
      sourceLabel: 'Open Food Facts',
      name: name,
      brand: brand.isEmpty ? null : brand,
      ingredientsSearchText: ing,
      calories: _asDouble(m['calories']),
      proteins: _asDouble(m['proteins']),
      carbs: _asDouble(m['carbs']),
      fats: _asDouble(m['fats']),
    );
  }

  static double _asDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}

/// After a miss in Supabase, chains Open Food Facts → OpenFDA (meds) → NIH DSLD (supps).
class GlobalBarcodeLookupService {
  GlobalBarcodeLookupService._();

  static Future<GlobalCatalogProduct?> lookupExternal(
    String barcode, {
    required GlobalBarcodeLibraryTab tab,
  }) async {
    final code = barcode.trim();
    if (code.isEmpty) return null;

    final offMap = await OpenFoodFactsService.fetchByBarcode(code);
    final off = offMap == null ? null : GlobalCatalogProduct.fromOpenFoodFactsMap(offMap);
    if (off != null) return off;

    if (tab == GlobalBarcodeLibraryTab.medications) {
      final fda = await _openFdaByProductCode(code);
      if (fda != null) return fda;
    }

    if (tab == GlobalBarcodeLibraryTab.supplements) {
      final dsld = await _nihDsldByBarcodeOrSearch(code);
      if (dsld != null) return dsld;
    }

    return null;
  }

  static Future<GlobalCatalogProduct?> _openFdaByProductCode(String code) async {
    final digits = code.replaceAll(RegExp(r'\D'), '');
    final queries = <String>{
      'openfda.upc:$code',
      if (digits.isNotEmpty) 'openfda.upc:$digits',
      if (digits.length == 12) 'openfda.upc:0$digits',
      if (digits.length == 13 && digits.startsWith('0')) 'openfda.upc:${digits.substring(1)}',
    };

    for (final q in queries) {
      final hit = await _openFdaRequest(q);
      if (hit != null) return hit;
    }
    return null;
  }

  static Future<GlobalCatalogProduct?> _openFdaRequest(String search) async {
    final uri = Uri.parse('https://api.fda.gov/drug/label.json').replace(
      queryParameters: <String, String>{
        'search': search,
        'limit': '1',
      },
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 14));
      if (res.statusCode == 404) return null;
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return null;
      final results = decoded['results'];
      if (results is! List || results.isEmpty) return null;
      final first = results.first;
      if (first is! Map<String, dynamic>) return null;
      return _parseOpenFdaLabel(first);
    } catch (_) {
      return null;
    }
  }

  static GlobalCatalogProduct? _parseOpenFdaLabel(Map<String, dynamic> label) {
    final openfda = label['openfda'];
    final of = (openfda is Map<String, dynamic>) ? openfda : const <String, dynamic>{};

    String firstStrList(String key) {
      final v = of[key];
      if (v is List && v.isNotEmpty) return v.first.toString().trim();
      return '';
    }

    final brand = firstStrList('brand_name');
    final generic = firstStrList('generic_name');
    final mfg = firstStrList('manufacturer_name');

    String joinField(String key) {
      final v = label[key];
      if (v is! List) return '';
      return v.map((e) => e.toString()).join('\n').trim();
    }

    final ingBlob = [
      joinField('inactive_ingredient'),
      joinField('active_ingredient'),
      joinField('spl_product_data_elements'),
    ].where((s) => s.isNotEmpty).join('\n');

    var name = brand.isNotEmpty ? brand : generic;
    if (name.isEmpty) name = mfg;
    if (name.isEmpty && ingBlob.isNotEmpty) {
      name = ingBlob.split(RegExp(r'[\n,]')).first.trim();
    }
    if (name.isEmpty) return null;

    return GlobalCatalogProduct(
      sourceKey: 'open_fda',
      sourceLabel: 'OpenFDA',
      name: name,
      brand: brand.isNotEmpty ? brand : (mfg.isNotEmpty ? mfg : null),
      ingredientsSearchText: ingBlob,
      calories: 0,
      proteins: 0,
      carbs: 0,
      fats: 0,
    );
  }

  static Future<GlobalCatalogProduct?> _nihDsldByBarcodeOrSearch(String code) async {
    final digits = code.replaceAll(RegExp(r'\D'), '');
    for (final q in <String>{code, if (digits.isNotEmpty) digits}) {
      final id = await _dsldSearchBestId(q, preferSku: digits.isNotEmpty ? digits : code);
      if (id == null) continue;
      final detail = await _dsldFetchLabel(id);
      if (detail == null) continue;
      final parsed = _parseDsldLabel(detail);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static Future<String?> _dsldSearchBestId(String query, {required String preferSku}) async {
    final uri = Uri.parse('https://api.ods.od.nih.gov/dsld/v8/search-filter').replace(
      queryParameters: <String, String>{
        'q': query,
        'from': '0',
        'size': '12',
      },
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 14));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return null;
      final hits = decoded['hits'];
      if (hits is! List || hits.isEmpty) return null;

      final normSku = preferSku.replaceAll(RegExp(r'\s'), '');
      for (final h in hits) {
        if (h is! Map<String, dynamic>) continue;
        final src = h['_source'];
        if (src is! Map<String, dynamic>) continue;
        final sku = (src['sku'] ?? '').toString().replaceAll(RegExp(r'\s'), '');
        if (normSku.isNotEmpty && sku.isNotEmpty && sku == normSku) {
          return h['_id']?.toString();
        }
      }
      final first = hits.first;
      if (first is Map<String, dynamic>) return first['_id']?.toString();
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> _dsldFetchLabel(String id) async {
    final uri = Uri.parse('https://api.ods.od.nih.gov/dsld/v8/label/$id');
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 16));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  static GlobalCatalogProduct? _parseDsldLabel(Map<String, dynamic> root) {
    final productName = (root['productName'] ?? '').toString().trim();
    final brand = (root['brand'] ?? '').toString().trim();
    if (productName.isEmpty && brand.isEmpty) return null;

    final buf = StringBuffer();
    if (productName.isNotEmpty) buf.writeln(productName);
    if (brand.isNotEmpty) buf.writeln('Brand: $brand');

    final groups = root['statementGroups'];
    if (groups is List) {
      for (final g in groups) {
        if (g is! Map<String, dynamic>) continue;
        final stmts = g['statements'];
        if (stmts is List) {
          for (final s in stmts) {
            buf.writeln(s.toString());
          }
        }
      }
    }

    final facts = root['dietarySupplementsFacts'];
    if (facts is List) {
      for (final block in facts) {
        if (block is! Map<String, dynamic>) continue;
        final ingredients = block['ingredients'];
        if (ingredients is! List) continue;
        for (final ing in ingredients) {
          if (ing is! Map<String, dynamic>) continue;
          final n = (ing['name'] ?? '').toString().trim();
          if (n.isNotEmpty) buf.writeln(n);
          final alt = (ing['altName'] ?? '').toString().trim();
          if (alt.isNotEmpty) buf.writeln(alt);
          final children = ing['childInfo'];
          if (children is List) {
            for (final c in children) {
              if (c is Map<String, dynamic>) {
                final cn = (c['name'] ?? '').toString().trim();
                if (cn.isNotEmpty) buf.writeln(cn);
              }
            }
          }
        }
        final other = block['otheringredients'];
        if (other is Map<String, dynamic>) {
          final t = (other['text'] ?? '').toString().trim();
          if (t.isNotEmpty) buf.writeln(t);
        }
      }
    }

    final rootOther = root['otheringredients'];
    if (rootOther is Map<String, dynamic>) {
      final t = (rootOther['text'] ?? '').toString().trim();
      if (t.isNotEmpty) buf.writeln(t);
    }

    final name = productName.isNotEmpty ? productName : brand;
    return GlobalCatalogProduct(
      sourceKey: 'nih_dsld',
      sourceLabel: 'NIH Dietary Supplement Label Database',
      name: name,
      brand: brand.isNotEmpty ? brand : null,
      ingredientsSearchText: buf.toString().trim(),
      calories: 0,
      proteins: 0,
      carbs: 0,
      fats: 0,
    );
  }
}
