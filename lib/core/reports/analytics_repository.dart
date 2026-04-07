import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/ingredient.dart';
import '../macro_display.dart';
import '../supabase_log_date.dart';
import 'analytics_models.dart';

/// Fetches analytics + PDF payloads scoped to [user_id] (must match RLS).
class AnalyticsRepository {
  AnalyticsRepository(this._client);

  final SupabaseClient _client;

  String? get currentUserId => _client.auth.currentUser?.id;

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Inclusive range of local calendar days [start … end].
  List<DateTime> _eachDay(DateTime start, DateTime end) {
    var a = _dateOnly(start);
    var b = _dateOnly(end);
    if (a.isAfter(b)) {
      final t = a;
      a = b;
      b = t;
    }
    final out = <DateTime>[];
    for (var d = a; !d.isAfter(b); d = d.add(const Duration(days: 1))) {
      out.add(d);
    }
    return out;
  }

  bool _isConsumedFood(Map<String, dynamic> row) {
    final ic = row['is_consumed'];
    if (ic == null) return true;
    if (ic is bool) return ic;
    if (ic is num) return ic != 0;
    final s = ic.toString().trim().toLowerCase();
    if (s.isEmpty) return true;
    if (s == 'true' || s == 't' || s == '1' || s == 'yes' || s == 'y') {
      return true;
    }
    if (s == 'false' || s == 'f' || s == '0' || s == 'no' || s == 'n') {
      return false;
    }
    return true;
  }

  bool _isFoodRow(Map<String, dynamic> row) {
    final sid = row['supplement_id'];
    if (sid != null && sid.toString().trim().isNotEmpty) return false;
    final iid = row['ingredient_id'];
    final rid = row['recipe_id'];
    return (iid != null && iid.toString().trim().isNotEmpty) ||
        (rid != null && rid.toString().trim().isNotEmpty);
  }

  double _perGramFromRecipeMap(Map<String, dynamic> recipe, String key) {
    final riRaw = recipe['recipe_ingredients'];
    if (riRaw is! List || riRaw.isEmpty) return 0.0;
    double totalDef = 0;
    for (final x in riRaw) {
      if (x is! Map<String, dynamic>) continue;
      totalDef += MacroDisplay.asDouble(x['amount_grams']);
    }
    if (totalDef <= 0) return 0.0;
    double acc = 0;
    for (final x in riRaw) {
      if (x is! Map<String, dynamic>) continue;
      final ing = x['ingredients'];
      if (ing is! Map<String, dynamic>) continue;
      final portionInDef = MacroDisplay.asDouble(x['amount_grams']);
      final w = portionInDef / totalDef;
      switch (key) {
        case 'p':
          acc += MacroDisplay.asDouble(ing['protein_per_100g']) / 100.0 * w;
          break;
        case 'c':
          acc += MacroDisplay.asDouble(ing['carbs_per_100g']) / 100.0 * w;
          break;
        case 'f':
          acc += MacroDisplay.asDouble(ing['fat_per_100g']) / 100.0 * w;
          break;
        case 'cal':
          acc += MacroDisplay.asDouble(ing['calories_per_100g']) / 100.0 * w;
          break;
      }
    }
    return acc;
  }

  double _glycemicLoadIngredient(Ingredient ing, double grams) {
    final gi = ing.glycemicIndex;
    if (gi == null) return 0;
    final carbG = grams * ing.carbsPer100g / 100.0;
    return (gi * carbG) / 100.0;
  }

  double _glycemicLoadRecipe(Map<String, dynamic> recipe, double logGrams) {
    final riRaw = recipe['recipe_ingredients'];
    if (riRaw is! List || riRaw.isEmpty || logGrams <= 0) return 0.0;
    double totalDef = 0;
    for (final x in riRaw) {
      if (x is! Map<String, dynamic>) continue;
      totalDef += MacroDisplay.asDouble(x['amount_grams']);
    }
    if (totalDef <= 0) return 0.0;
    final scale = logGrams / totalDef;
    double gl = 0;
    for (final x in riRaw) {
      if (x is! Map<String, dynamic>) continue;
      final ingMap = x['ingredients'];
      if (ingMap is! Map<String, dynamic>) continue;
      final ing = Ingredient.fromJson(ingMap);
      final portionG = MacroDisplay.asDouble(x['amount_grams']) * scale;
      gl += _glycemicLoadIngredient(ing, portionG);
    }
    return gl;
  }

  ({double cal, double gl}) _caloriesAndGlForFoodRow(Map<String, dynamic> row) {
    final g = MacroDisplay.asDouble(row['amount_grams']);
    final ingMap = row['ingredients'];
    if (ingMap is Map<String, dynamic> &&
        (row['ingredient_id'] ?? '').toString().trim().isNotEmpty) {
      final ing = Ingredient.fromJson(ingMap);
      final factor = g / 100.0;
      final cal = ing.caloriesPer100g * factor;
      final gl = _glycemicLoadIngredient(ing, g);
      return (cal: cal, gl: gl);
    }
    final recMap = row['recipes'];
    if (recMap is Map<String, dynamic> &&
        (row['recipe_id'] ?? '').toString().trim().isNotEmpty) {
      final calPerG = _perGramFromRecipeMap(recMap, 'cal');
      final cal = calPerG * g;
      final gl = _glycemicLoadRecipe(recMap, g);
      return (cal: cal, gl: gl);
    }
    return (cal: 0.0, gl: 0.0);
  }

  DateTime? _parseLocalDateFromRow(Map<String, dynamic> row) {
    final raw =
        (row['consumed_at'] ?? row['scheduled_at'] ?? '').toString().trim();
    if (raw.isEmpty) return null;
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return null;
    }
  }

  /// Calories + estimated glycemic load from **consumed** food logs only.
  Future<List<DailyFuelPoint>> fetchFuelSeries({
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    final uid = currentUserId;
    final days = _eachDay(rangeStart, rangeEnd);
    if (uid == null) {
      return days
          .map((d) => DailyFuelPoint(day: d, calories: 0, glycemicLoad: 0))
          .toList();
    }

    final startStr = supabaseDateOnly(days.first);
    final endStr = supabaseDateOnly(days.last);

    final data = await _client
        .from('daily_logs')
        .select(
          'created_at,consumed_at,scheduled_at,amount_grams,is_consumed,ingredient_id,recipe_id,supplement_id,'
          'ingredients(*),recipes(*, recipe_ingredients(*, ingredients(*)))',
        )
        .eq('user_id', uid)
        .gte('created_at', supabaseCreatedAtDayGte(startStr))
        .lte('created_at', supabaseCreatedAtDayLte(endStr))
        .order('created_at', ascending: true);

    final rows = (data as List).cast<Map<String, dynamic>>();
    final byDay = <String, ({double c, double g})>{};
    for (final d in days) {
      final k =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      byDay[k] = (c: 0, g: 0);
    }

    for (final row in rows) {
      if (!_isFoodRow(row)) continue;
      if (!_isConsumedFood(row)) continue;
      final dk = supabaseYmdFromCreatedAt(row['created_at']);
      if (dk == null || !byDay.containsKey(dk)) continue;
      final m = _caloriesAndGlForFoodRow(row);
      final cur = byDay[dk]!;
      byDay[dk] = (c: cur.c + m.cal, g: cur.g + m.gl);
    }

    return days.map((d) {
      final k =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final v = byDay[k] ?? (c: 0.0, g: 0.0);
      return DailyFuelPoint(day: d, calories: v.c, glycemicLoad: v.g);
    }).toList();
  }

  bool _isTakenSuppOrMed(Map<String, dynamic> row) {
    final v = row['is_taken'];
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = (v ?? '').toString().trim().toLowerCase();
    return s == 'true' || s == 't' || s == '1' || s == 'yes';
  }

  DateTime? _scheduledLocal(Map<String, dynamic> row) {
    final raw = (row['scheduled_at'] ?? '').toString().trim();
    if (raw.isEmpty) return null;
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return null;
    }
  }

  /// Calendar bucket for adherence charts when `created_at` is null on legacy rows.
  String? _dayKeyForAdherenceRow(Map<String, dynamic> row) {
    final fromCreated = supabaseYmdFromCreatedAt(row['created_at']);
    if (fromCreated != null) return fromCreated;
    return supabaseYmdFromCreatedAt(row['scheduled_at']);
  }

  String _medicationDisplayName(Map<String, dynamic> row) {
    final nested = row['medications'];
    if (nested is Map<String, dynamic>) {
      final n = (nested['name'] ?? '').toString().trim();
      if (n.isNotEmpty) return n;
    }
    final mid = (row['medication_id'] ?? '').toString().trim();
    if (mid.isNotEmpty) return 'Medication ($mid)';
    return 'Medication';
  }

  bool _isMissedScheduled({
    required DateTime scheduledLocal,
    required DateTime dayDate,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    if (dayDate.isBefore(today)) {
      return true;
    }
    if (dayDate.isAfter(today)) {
      return false;
    }
    return now.isAfter(scheduledLocal.add(const Duration(minutes: 60)));
  }

  Future<List<DailyAdherencePoint>> _adherenceFromDailyLogs({
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required bool supplementOnly,
  }) async {
    final uid = currentUserId;
    final days = _eachDay(rangeStart, rangeEnd);
    if (uid == null) {
      return days
          .map((d) => DailyAdherencePoint(day: d, taken: 0, missed: 0))
          .toList();
    }

    final startStr = supabaseDateOnly(days.first);
    final endStr = supabaseDateOnly(days.last);
    final data = await _client
        .from('daily_logs')
        .select('scheduled_at,is_taken,supplement_id,created_at')
        .eq('user_id', uid)
        .gte('created_at', supabaseCreatedAtDayGte(startStr))
        .lte('created_at', supabaseCreatedAtDayLte(endStr))
        .order('scheduled_at', ascending: true);

    final rows = (data as List).cast<Map<String, dynamic>>();
    final filtered = rows.where((row) {
      final sid = row['supplement_id'];
      final hasSid = sid != null && sid.toString().trim().isNotEmpty;
      return supplementOnly && hasSid;
    });

    final byDay = <String, ({int t, int m})>{};
    for (final d in days) {
      final k =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      byDay[k] = (t: 0, m: 0);
    }

    final now = DateTime.now();
    for (final row in filtered) {
      final sched = _scheduledLocal(row);
      final dk = _dayKeyForAdherenceRow(row);
      if (dk == null || !byDay.containsKey(dk)) continue;
      DateTime? dayDate;
      try {
        final p = dk.split('-');
        if (p.length == 3) {
          dayDate = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
        }
      } catch (_) {}
      dayDate ??= sched == null
          ? null
          : DateTime(sched.year, sched.month, sched.day);
      if (dayDate == null) continue;

      if (_isTakenSuppOrMed(row)) {
        final cur = byDay[dk]!;
        byDay[dk] = (t: cur.t + 1, m: cur.m);
        continue;
      }

      if (sched != null &&
          _isMissedScheduled(
            scheduledLocal: sched,
            dayDate: dayDate,
            now: now,
          )) {
        final cur = byDay[dk]!;
        byDay[dk] = (t: cur.t, m: cur.m + 1);
      }
    }

    return days.map((d) {
      final k =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final v = byDay[k] ?? (t: 0, m: 0);
      return DailyAdherencePoint(day: d, taken: v.t, missed: v.m);
    }).toList();
  }

  Future<List<DailyAdherencePoint>> fetchSupplementAdherence({
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) =>
      _adherenceFromDailyLogs(
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        supplementOnly: true,
      );

  Future<List<DailyAdherencePoint>> fetchMedicationAdherence({
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    final uid = currentUserId;
    final days = _eachDay(rangeStart, rangeEnd);
    if (uid == null) {
      return days
          .map((d) => DailyAdherencePoint(day: d, taken: 0, missed: 0))
          .toList();
    }

    final startStr = supabaseDateOnly(days.first);
    final endStr = supabaseDateOnly(days.last);

    final data = await _client
        .from('medication_logs')
        .select(
          'medication_id,medications(name),scheduled_at,is_taken,created_at,taken_at',
        )
        .eq('user_id', uid)
        .gte('created_at', supabaseCreatedAtDayGte(startStr))
        .lte('created_at', supabaseCreatedAtDayLte(endStr))
        .order('created_at', ascending: true);

    final rows = (data as List).cast<Map<String, dynamic>>();
    final byDay = <String, ({int t, int m})>{};
    for (final d in days) {
      final k =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      byDay[k] = (t: 0, m: 0);
    }

    final now = DateTime.now();
    for (final row in rows) {
      final sched = _scheduledLocal(row);
      final dk = _dayKeyForAdherenceRow(row);
      if (dk == null || !byDay.containsKey(dk)) continue;
      DateTime? dayDate;
      try {
        final p = dk.split('-');
        if (p.length == 3) {
          dayDate = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
        }
      } catch (_) {}
      dayDate ??= sched == null
          ? null
          : DateTime(sched.year, sched.month, sched.day);
      if (dayDate == null) continue;

      if (_isTakenSuppOrMed(row)) {
        final cur = byDay[dk]!;
        byDay[dk] = (t: cur.t + 1, m: cur.m);
      } else if (sched != null &&
          _isMissedScheduled(
            scheduledLocal: sched,
            dayDate: dayDate,
            now: now,
          )) {
        final cur = byDay[dk]!;
        byDay[dk] = (t: cur.t, m: cur.m + 1);
      }
    }

    return days.map((d) {
      final k =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final v = byDay[k] ?? (t: 0, m: 0);
      return DailyAdherencePoint(day: d, taken: v.t, missed: v.m);
    }).toList();
  }

  String _mealTypeToBlock(String meal) {
    final u = meal.toUpperCase();
    if (u.contains('BREAKFAST')) return 'MORNING';
    if (u.contains('LUNCH')) return 'AFTERNOON';
    if (u.contains('DINNER')) return 'EVENING';
    return 'NIGHT';
  }

  String _hhmm(DateTime? dt) {
    if (dt == null) return '--:--';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// All planned items for [day] (food, supplements, medications) for PDF / checklists.
  Future<List<DailyPlanLine>> fetchDailyPlanLines(DateTime day) async {
    final uid = currentUserId;
    if (uid == null) return [];

    final d0 = _dateOnly(day);
    final dayStr = supabaseDateOnly(d0);

    final lines = <DailyPlanLine>[];

    final food = await _client
        .from('daily_logs')
        .select(
          'meal_type,schedule_block,consumed_at,scheduled_at,taken_at,is_taken,amount_grams,unit,'
          'ingredient_id,recipe_id,supplement_id,ingredients(name),recipes(name),'
          'supplements(name)',
        )
        .eq('user_id', uid)
        .gte('created_at', supabaseCreatedAtDayGte(dayStr))
        .lte('created_at', supabaseCreatedAtDayLte(dayStr));

    DateTime? parseIsoLocal(dynamic v) {
      final s = (v ?? '').toString().trim();
      if (s.isEmpty) return null;
      try {
        return DateTime.parse(s).toLocal();
      } catch (_) {
        return null;
      }
    }

    for (final row in (food as List).cast<Map<String, dynamic>>()) {
      final sid = row['supplement_id'];
      if (sid != null && sid.toString().trim().isNotEmpty) {
        final sup = row['supplements'];
        final name = sup is Map ? (sup['name'] ?? 'Supplement').toString() : 'Supplement';
        final sched = _isTakenSuppOrMed(row)
            ? (parseIsoLocal(row['taken_at']) ?? parseIsoLocal(row['consumed_at']))
            : (_scheduledLocal(row) ?? _parseLocalDateFromRow(row));
        final block = (row['schedule_block'] ?? 'MORNING').toString().toUpperCase();
        final amt = MacroDisplay.asDouble(row['amount_grams']);
        final u = (row['unit'] ?? '').toString().trim().isEmpty
            ? 'g'
            : row['unit'].toString();
        lines.add(
          DailyPlanLine(
            block: block,
            timeLabel: _hhmm(sched),
            name: name,
            amountUnit: '${MacroDisplay.fmt(amt)} $u'.trim(),
            categoryLabel: 'SUPP',
          ),
        );
        continue;
      }

      if (!_isFoodRow(row)) continue;

      final ing = row['ingredients'];
      final rec = row['recipes'];
      final name = ing is Map
          ? (ing['name'] ?? 'Ingredient').toString()
          : rec is Map
              ? (rec['name'] ?? 'Recipe').toString()
              : 'Food';
      final sched = _isConsumedFood(row)
          ? (parseIsoLocal(row['consumed_at']) ?? _parseLocalDateFromRow(row))
          : (_scheduledLocal(row) ?? _parseLocalDateFromRow(row));
      final meal = (row['meal_type'] ?? '').toString();
      final block = _mealTypeToBlock(meal);
      final amt = MacroDisplay.asDouble(row['amount_grams']);
      final u = (row['unit'] ?? '').toString().trim().isEmpty
          ? 'g'
          : row['unit'].toString();
      lines.add(
        DailyPlanLine(
          block: block,
          timeLabel: _hhmm(sched),
          name: name,
          amountUnit: '${MacroDisplay.fmt(amt)} $u'.trim(),
          categoryLabel: 'FOOD',
        ),
      );
    }

    final medRows = await _client
        .from('medication_logs')
        .select(
          'medication_id,scheduled_at,taken_at,is_taken,dose_amount,unit_type,'
          'medications(name),schedule_block,created_at',
        )
        .eq('user_id', uid)
        .gte('created_at', supabaseCreatedAtDayGte(dayStr))
        .lte('created_at', supabaseCreatedAtDayLte(dayStr))
        .order('scheduled_at', ascending: true);

    for (final row in (medRows as List).cast<Map<String, dynamic>>()) {
      final name = _medicationDisplayName(row);
      final sched = _isTakenSuppOrMed(row)
          ? parseIsoLocal(row['taken_at'])
          : _scheduledLocal(row);
      final block = (row['schedule_block'] ?? 'MORNING').toString().toUpperCase();
      final amt = MacroDisplay.asDouble(row['dose_amount']);
      final u = (row['unit_type'] ?? '').toString().trim();
      final unitLabel = u.isEmpty ? 'units' : u;
      lines.add(
        DailyPlanLine(
          block: block,
          timeLabel: _hhmm(sched),
          name: name,
          amountUnit: '${MacroDisplay.fmt(amt)} $unitLabel'.trim(),
          categoryLabel: 'MED',
        ),
      );
    }

    const order = ['MORNING', 'AFTERNOON', 'EVENING', 'NIGHT'];
    int rank(String b) {
      final i = order.indexOf(b);
      return i < 0 ? 99 : i;
    }

    lines.sort((a, b) {
      final c = rank(a.block).compareTo(rank(b.block));
      if (c != 0) return c;
      return a.timeLabel.compareTo(b.timeLabel);
    });

    return lines;
  }

  Future<WeeklySummaryStats> fetchWeeklySummary({
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    final fuel = await fetchFuelSeries(
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
    );
    final sup = await fetchSupplementAdherence(
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
    );
    final med = await fetchMedicationAdherence(
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
    );
    return WeeklySummaryStats(
      rangeStart: _dateOnly(rangeStart),
      rangeEnd: _dateOnly(rangeEnd),
      fuelByDay: fuel,
      suppsByDay: sup,
      medsByDay: med,
    );
  }
}
