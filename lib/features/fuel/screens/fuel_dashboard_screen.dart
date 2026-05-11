import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bio_cyber_os/l10n/app_localizations.dart';
import 'package:bio_cyber_os/l10n/app_localizations_format.dart';
import 'package:bio_cyber_os/l10n/context_l10n.dart';
import 'package:bio_cyber_os/l10n/meal_labels.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/macro_display.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/supabase_error_message.dart';
import '../../../core/supabase_log_date.dart';
import '../../../core/widgets/reminder_section.dart';
import '../../../core/widgets/schedule_selector.dart';
import '../../../core/models/ingredient.dart';
import '../../../core/widgets/diet_indicator_badges.dart';
import '../../food/screens/barcode_scanner_screen.dart';
import '../../../core/settings/measurement_settings.dart';
import '../../../core/settings/unit_options.dart';
import '../../../core/settings/unit_converter.dart';

class FuelDashboardScreen extends StatefulWidget {
  final String? focusLogId;
  final DateTime? focusDate;
  final bool isActive;

  const FuelDashboardScreen({
    super.key,
    this.focusLogId,
    this.focusDate,
    this.isActive = true,
  });

  @override
  State<FuelDashboardScreen> createState() => _FuelDashboardScreenState();
}

class _FuelDashboardScreenState extends State<FuelDashboardScreen>
    with WidgetsBindingObserver {
  final _client = Supabase.instance.client;

  /// Supabase table for fuel entries (`daily_logs` or `food_logs` if renamed).
  static const String _fuelLogsTable = 'daily_logs';

  bool _loading = true;
  String? _error;

  RealtimeChannel? _todayLogsChannel;
  RealtimeChannel? _targetsChannel;

  bool _autoRefreshingTargets = false;

  /// Consumed (`is_consumed` true) — "Current" chart only.
  double _todayProtein = 0;
  double _todayCarbs = 0;
  double _todayFats = 0;
  int _todayCalories = 0;

  /// Planned totals are still calculated for data completeness (not shown in UI).
  // ignore: unused_field
  double _plannedProtein = 0;
  // ignore: unused_field
  double _plannedCarbs = 0;
  // ignore: unused_field
  double _plannedFats = 0;
  // ignore: unused_field
  int _plannedCalories = 0;

  double? _targetProtein;
  double? _targetCarbs;
  double? _targetFats;
  int? _targetCalories;

  DateTime _selectedDay = DateTime.now();
  String? _highlightLogId;
  final Map<String, GlobalKey> _rowKeys = {};

  List<_DailyRecord> _dailyRecords = const [];
  // Extra meals are derived from logs for the selected date.

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (t) {
      if (mounted) setState(() {});
    });
    _loadTargets();
    _subscribeTargets();
    _initDayTotals();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant FuelDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      // `IndexedStack` keeps this screen mounted; refresh when it becomes visible.
      _refreshTargetsWithIndicator();
    }
    if (widget.focusDate != null && widget.focusDate != oldWidget.focusDate) {
      final d = widget.focusDate!;
      _selectedDay = DateTime(d.year, d.month, d.day);
      _fetchAndApplyDailyLogs().then((_) {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _ensureHighlightVisible(),
        );
      });
    }
    if (widget.focusLogId != null &&
        widget.focusLogId!.trim().isNotEmpty &&
        widget.focusLogId != oldWidget.focusLogId) {
      setState(() => _highlightLogId = widget.focusLogId);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ensureHighlightVisible(),
      );
    }
  }

  void _ensureHighlightVisible() {
    final id = (_highlightLogId ?? '').trim();
    if (id.isEmpty) return;
    final key = _rowKeys[id];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      alignment: 0.15,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _todayLogsChannel?.unsubscribe();
    _targetsChannel?.unsubscribe();
    super.dispose();
  }

  void _subscribeTargets() {
    _targetsChannel?.unsubscribe();
    _targetsChannel = null;
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;

    _targetsChannel = _client.channel('user-targets-$uid');
    _targetsChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_targets',
          callback: (payload) {
            // Best-effort: only react to the current user.
            try {
              final next = payload.newRecord.isNotEmpty
                  ? payload.newRecord
                  : payload.oldRecord;
              final userId = next['user_id']?.toString();
              if (userId != null && userId.isNotEmpty && userId != uid) return;
            } catch (_) {
              // ignore; still refresh targets
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _refreshTargetsWithIndicator();
            });
          },
        )
        .subscribe();
  }

  Future<void> _refreshTargetsWithIndicator() async {
    if (_autoRefreshingTargets) return;
    setState(() => _autoRefreshingTargets = true);
    try {
      await _loadTargets();
    } finally {
      if (mounted) setState(() => _autoRefreshingTargets = false);
    }
  }

  void _setStatePostFrame(VoidCallback fn) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(fn);
    });
  }

  /// Alias for refresh (planning / charts / lists).
  Future<void> _fetchFuelData() => _fetchAndApplyDailyLogs();

  // Single path to refresh logs + totals and trigger repaint.
  Future<void> _fetchAndApplyDailyLogs() async {
    try {
      setState(() {
        _dailyRecords = const [];
        _loading = true;
        _error = null;
      });

      final records = await _fetchDailyLogs();
      if (!mounted) return;

      setState(() {
        _dailyRecords = records;
        _loading = false;
      });

      await _calculateTotals(); // does setState
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dailyRecords = const [];
        _todayProtein = 0;
        _todayCarbs = 0;
        _todayFats = 0;
        _todayCalories = 0;
        _plannedProtein = 0;
        _plannedCarbs = 0;
        _plannedFats = 0;
        _plannedCalories = 0;
        _loading = false;
        _error = e.toString();
      });
    }
  }

  DateTime _startOfSelectedDayLocal() {
    final d = _selectedDay;
    return DateTime(d.year, d.month, d.day);
  }

  String _isoUtc(DateTime dtLocal) => dtLocal.toUtc().toIso8601String();

  bool _isSelectedDayToday() {
    final now = DateTime.now();
    return now.year == _selectedDay.year &&
        now.month == _selectedDay.month &&
        now.day == _selectedDay.day;
  }

  Future<void> _initDayTotals() async {
    await _fetchAndApplyDailyLogs();
    _subscribeIfToday();
  }

  void _subscribeIfToday() {
    _todayLogsChannel?.unsubscribe();
    _todayLogsChannel = null;
    if (!_isSelectedDayToday()) return;

    _todayLogsChannel = _client.channel('today-daily-logs');
    _todayLogsChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: _fuelLogsTable,
          callback: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _refreshSelectedDay();
            });
          },
        )
        .subscribe();
  }

  /// Loads rows from `daily_logs` for the selected calendar day via [created_at] (UTC day bounds).
  /// Does not filter `is_consumed`; planned vs consumed is handled in the UI.
  Future<List<_DailyRecord>> _fetchDailyLogs() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];

    final dayStr = supabaseDateOnly(_selectedDay);

    final data = await _client
        .from(_fuelLogsTable)
        .select(
          '*, ingredients(*), recipes(*, recipe_ingredients(*, ingredients(*)))',
        )
        .eq('user_id', uid)
        .gte('created_at', supabaseCreatedAtDayGte(dayStr))
        .lte('created_at', supabaseCreatedAtDayLte(dayStr))
        .order('created_at', ascending: true);

    final rows = (data as List).cast<Map<String, dynamic>>();

    final records = <_DailyRecord>[];
    for (final row in rows) {
      final suppId = row['supplement_id'];
      if (suppId != null && suppId.toString().trim().isNotEmpty) {
        continue;
      }
      final ing = row['ingredients'];
      final rec = row['recipes'];
      final grams = row['amount_grams'];

      final ic = row['is_consumed'];
      // Be tolerant to Supabase returning boolean, numeric, or string values
      // (and to legacy rows where the column might be NULL).
      final isConsumed = () {
        if (ic == null) return true;
        if (ic is bool) return ic;
        if (ic is num) return ic != 0;
        if (ic is String) {
          final s = ic.trim().toLowerCase();
          if (s.isEmpty) return true;
          if (s == 'true' || s == 't' || s == '1' || s == 'yes' || s == 'y') {
            return true;
          }
          if (s == 'false' || s == 'f' || s == '0' || s == 'no' || s == 'n') {
            return false;
          }
        }
        return true;
      }();

      final ca = (row['consumed_at'] ?? '').toString();
      final sa = (row['scheduled_at'] ?? '').toString();
      final scheduledSlot = sa.trim().isNotEmpty ? sa : ca;
      final consumedEvt = isConsumed && ca.trim().isNotEmpty ? ca : '';
      final sortKey = isConsumed
          ? (ca.trim().isNotEmpty ? ca : scheduledSlot)
          : (scheduledSlot.trim().isNotEmpty ? scheduledSlot : ca);

      records.add(
        _DailyRecord(
          id: (row['id'] ?? '').toString(),
          mealType: (row['meal_type'] ?? '').toString(),
          consumedAt: sortKey,
          scheduledAt: scheduledSlot,
          consumedEventAt: consumedEvt,
          reminderAt: (row['reminder_at'] ?? '').toString(),
          reminderOffsetMinutes: row['reminder_offset_minutes'],
          amountGrams: grams is num ? grams.toDouble() : 0.0,
          ingredient: ing is Map<String, dynamic>
              ? Ingredient.fromJson(ing)
              : null,
          recipe: rec is Map<String, dynamic> ? _Recipe.fromJson(rec) : null,
          recipeId: (row['recipe_id'] ?? '').toString(),
          ingredientId: (row['ingredient_id'] ?? '').toString(),
          isConsumed: isConsumed,
        ),
      );
    }
    return records;
  }

  final Map<String, _Totals> _recipeTotalsCache = {};

  _Totals _recipePerGramTotalsFromNested(_Recipe recipe) {
    double totalWeight = 0.0;
    double p = 0.0, c = 0.0, f = 0.0;
    double cal = 0.0;

    for (final ri in recipe.recipeIngredients) {
      final ing = ri.ingredient;
      if (ing == null) continue;
      final g = ri.amountGrams;
      if (g <= 0) continue;
      totalWeight += g;

      final factor = g / 100.0;
      p += ing.proteinPer100g * factor;
      c += ing.carbsPer100g * factor;
      f += ing.fatPer100g * factor;
      cal += ing.caloriesPer100g * factor;
    }

    if (totalWeight <= 0) {
      return const _Totals(protein: 0, carbs: 0, fats: 0, calories: 0);
    }

    // Per-gram totals (store calories as rounded per-gram).
    final perGramCalories = cal / totalWeight;
    return _Totals(
      protein: p / totalWeight,
      carbs: c / totalWeight,
      fats: f / totalWeight,
      calories: perGramCalories.round(),
    );
  }

  Future<_Totals> _getRecipeTotals(String recipeId) async {
    final cached = _recipeTotalsCache[recipeId];
    if (cached != null) return cached;

    // Try compute from recipes(*) payload if it contains manual macros.
    final fromLoaded = _dailyRecords
        .map((r) => r.recipe)
        .whereType<_Recipe>()
        .firstWhere(
          (r) => r.id == recipeId,
          orElse: () => const _Recipe.empty(),
        );
    if (fromLoaded.id.isNotEmpty) {
      final t = fromLoaded.manualTotals;
      if (t != null) {
        _recipeTotalsCache[recipeId] = t;
        return t;
      }
    }

    // Fallback: batch compute from recipe_ingredients + ingredients per100g.
    final data = await _client
        .from('recipe_ingredients')
        .select(
          'amount_grams,ingredients(protein_per_100g,carbs_per_100g,fat_per_100g,calories_per_100g)',
        )
        .eq('recipe_id', recipeId);
    final rows = (data as List).cast<Map<String, dynamic>>();
    double p = 0, c = 0, f = 0;
    double cal = 0;
    for (final row in rows) {
      final ing = row['ingredients'];
      if (ing is! Map<String, dynamic>) continue;
      final grams = row['amount_grams'];
      final g = grams is num ? grams.toDouble() : 0.0;
      final factor = g <= 0 ? 0.0 : (g / 100.0);
      final i = Ingredient.fromJson(ing);
      p += i.proteinPer100g * factor;
      c += i.carbsPer100g * factor;
      f += i.fatPer100g * factor;
      cal += i.caloriesPer100g * factor;
    }
    final t = _Totals(protein: p, carbs: c, fats: f, calories: cal.round());
    _recipeTotalsCache[recipeId] = t;
    return t;
  }

  /// Sync macros for the logged amount (ingredient or recipe portion) for list row UI+.
  ({double p, double c, double f, double cal}) _lineMacrosForDisplay(
    _DailyRecord r,
  ) {
    if (r.ingredient != null && r.ingredientId.isNotEmpty) {
      final g = r.amountGrams;
      final factor = g / 100.0;
      final i = r.ingredient!;
      return (
        p: i.proteinPer100g * factor,
        c: i.carbsPer100g * factor,
        f: i.fatPer100g * factor,
        cal: i.caloriesPer100g * factor,
      );
    }
    if (r.recipe != null && r.recipeId.isNotEmpty) {
      final g = r.amountGrams;
      final perGram = _recipePerGramTotalsFromNested(r.recipe!);
      return (
        p: perGram.protein * g,
        c: perGram.carbs * g,
        f: perGram.fats * g,
        cal: perGram.calories * g,
      );
    }
    return (p: 0, c: 0, f: 0, cal: 0);
  }

  Future<({double p, double c, double f, int cal})?>
  _macrosForRecordOnSelectedDay(_DailyRecord r) async {
    // List is already filtered to the selected day via `created_at`.
    if (r.ingredientId.isNotEmpty && r.ingredient != null) {
      final factor = (r.amountGrams <= 0) ? 0.0 : (r.amountGrams / 100.0);
      return (
        p: r.ingredient!.proteinPer100g * factor,
        c: r.ingredient!.carbsPer100g * factor,
        f: r.ingredient!.fatPer100g * factor,
        cal: (r.ingredient!.caloriesPer100g * factor).round(),
      );
    }

    if (r.recipeId.isNotEmpty) {
      final grams = r.amountGrams;
      if (grams > 0 && r.recipe != null) {
        final perGram = _recipePerGramTotalsFromNested(r.recipe!);
        return (
          p: perGram.protein * grams,
          c: perGram.carbs * grams,
          f: perGram.fats * grams,
          cal: (perGram.calories * grams).round(),
        );
      } else {
        final t = await _getRecipeTotals(r.recipeId);
        return (p: t.protein, c: t.carbs, f: t.fats, cal: t.calories);
      }
    }

    return null;
  }

  Future<void> _calculateTotals() async {
    double cp = 0, cc = 0, cf = 0;
    int ccal = 0;
    double pp = 0, pc = 0, pf = 0;
    int pcal = 0;

    for (final r in List<_DailyRecord>.from(_dailyRecords)) {
      final m = await _macrosForRecordOnSelectedDay(r);
      if (m == null) continue;
      if (r.isConsumed) {
        cp += m.p;
        cc += m.c;
        cf += m.f;
        ccal += m.cal;
      } else {
        pp += m.p;
        pc += m.c;
        pf += m.f;
        pcal += m.cal;
      }
    }

    if (!mounted) return;
    setState(() {
      _todayProtein = cp;
      _todayCarbs = cc;
      _todayFats = cf;
      _todayCalories = ccal;
      // planned = total for the day (consumed + planned)
      _plannedProtein = cp + pp;
      _plannedCarbs = cc + pc;
      _plannedFats = cf + pf;
      _plannedCalories = ccal + pcal;
    });
  }

  Future<void> _refreshSelectedDay() => _fetchAndApplyDailyLogs();

  Future<void> _loadTargets() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;

      final data = await _client
          .from('user_targets')
          .select('calories_target, protein_target, fat_target, carbs_target')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (!mounted) return;
      _setStatePostFrame(() {
        final p = data?['protein_target'];
        final c = data?['carbs_target'];
        final f = data?['fat_target'];
        final cal = data?['calories_target'];

        _targetProtein = p is num ? p.toDouble() : null;
        _targetCarbs = c is num ? c.toDouble() : null;
        _targetFats = f is num ? f.toDouble() : null;
        _targetCalories = cal is num ? cal.toInt() : null;
      });
    } catch (_) {
      // Targets are optional; allow screen to run without them.
    }
  }

  double get _safeTargetProtein =>
      (_targetProtein != null && _targetProtein! > 0) ? _targetProtein! : 100.0;
  double get _safeTargetCarbs =>
      (_targetCarbs != null && _targetCarbs! > 0) ? _targetCarbs! : 50.0;
  double get _safeTargetFats =>
      (_targetFats != null && _targetFats! > 0) ? _targetFats! : 150.0;
  int get _safeTargetCalories =>
      (_targetCalories != null && _targetCalories! > 0)
      ? _targetCalories!
      : 2000;

  // grams prompt moved into _FoodLogSheet to keep dialog lifecycle isolated.

  Future<void> _deleteLog(String id, {bool removedWasPlanned = false}) async {
    const cyan = Color(0xFF00F3FF);
    setState(() {
      _dailyRecords = _dailyRecords
          .where((r) => r.id != id)
          .toList(growable: false);
    });
    await _calculateTotals();

    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.msgSignInDeleteLogs),
            backgroundColor: Colors.redAccent,
          ),
        );
        await _fetchFuelData();
        return;
      }
      await _client
          .from(_fuelLogsTable)
          .delete()
          .eq('id', id)
          .eq('user_id', uid);
      if (!mounted) return;
      await _fetchFuelData();
      if (mounted && removedWasPlanned) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.msgPlannedMealRemoved)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(supabaseWriteErrorMessage(e)),
          backgroundColor: Colors.black,
          showCloseIcon: true,
          closeIconColor: cyan,
        ),
      );
      await _fetchFuelData();
    }
  }

  Future<void> _planMealFlow(String mealType) async {
    // Keep this flow silent/non-intrusive: default to current time.
    final now = TimeOfDay.now();
    final day = _startOfSelectedDayLocal();
    final consumedLocal = DateTime(
      day.year,
      day.month,
      day.day,
      now.hour,
      now.minute,
    );

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF050510),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.95,
        child: _FoodLogSheet(
          logsTable: _fuelLogsTable,
          mealType: mealType,
          consumedAtIsoUtc: _isoUtc(consumedLocal),
          planOnly: true,
        ),
      ),
    );

    if (result == true && mounted) {
      await _fetchFuelData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.msgPlannedForMeal(
              localizedMealSectionTitle(context.l10n, mealType),
            ),
          ),
        ),
      );
    }
  }

  Future<void> _editMealFlow(_DailyRecord record) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF050510),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.95,
        child: _FoodLogSheet(
          logsTable: _fuelLogsTable,
          mealType: record.mealType,
          consumedAtIsoUtc: record.consumedAt,
          editingRecord: record,
        ),
      ),
    );

    if (result == true && mounted) {
      await _fetchFuelData();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.msgEntryUpdated)));
    }
  }

  Future<void> _takePlanned(_DailyRecord r) async {
    final recordId = r.id.trim();
    if (recordId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.msgEmptyRecordId)));
      return;
    }

    // 1) Optimistic local update so the UI reacts instantly.
    final nowIso = DateTime.now().toIso8601String();
    setState(() {
      _dailyRecords = _dailyRecords
          .map(
            (e) => e.id == recordId
                ? _DailyRecord(
                    id: e.id,
                    mealType: e.mealType,
                    consumedAt: nowIso,
                    scheduledAt: e.scheduledAt.trim().isNotEmpty
                        ? e.scheduledAt
                        : e.consumedAt,
                    consumedEventAt: nowIso,
                    reminderAt: e.reminderAt,
                    reminderOffsetMinutes: e.reminderOffsetMinutes,
                    amountGrams: e.amountGrams,
                    ingredientId: e.ingredientId,
                    recipeId: e.recipeId,
                    ingredient: e.ingredient,
                    recipe: e.recipe,
                    isConsumed: true,
                  )
                : e,
          )
          .toList(growable: false);
    });
    await _calculateTotals();

    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.msgSignInUpdateLogs),
            backgroundColor: Colors.redAccent,
          ),
        );
        await _fetchAndApplyDailyLogs();
        return;
      }
      // 2) Log and perform the minimal update against daily_logs.
      // ignore: avoid_print
      print('ATTEMPTING UPDATE ON TABLE daily_logs FOR ID: $recordId');

      final response = await _client
          .from('daily_logs')
          .update({
            'user_id': uid,
            'is_consumed': true,
            'consumed_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', recordId)
          .eq('user_id', uid)
          .select();

      // ignore: avoid_print
      print('RESPONSE AFTER UPDATE: $response');

      await _fetchAndApplyDailyLogs();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.msgMealMarkedConsumed)),
      );
    } catch (e) {
      // 2) Log DB error and surface via SnackBar.
      // ignore: avoid_print
      print('DB ERROR DURING TAKE: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(supabaseWriteErrorMessage(e)),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  /// Normalizes `meal_type` from Supabase so rows land under BREAKFAST / LUNCH / DINNER
  /// even when the DB stores different casing (e.g. "Breakfast", "breakfast").
  String _canonicalMealTypeKey(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'EXTRA:UNSORTED';
    if (t.toUpperCase().startsWith('EXTRA:')) {
      final suffix = t.substring(t.indexOf(':') + 1).trim();
      if (suffix.isEmpty) return 'EXTRA:UNSORTED';
      return 'EXTRA:$suffix'.toUpperCase();
    }
    switch (t.toUpperCase()) {
      case 'BREAKFAST':
      case 'BRUNCH':
        return 'BREAKFAST';
      case 'LUNCH':
        return 'LUNCH';
      case 'DINNER':
      case 'SUPPER':
        return 'DINNER';
      default:
        return t;
    }
  }

  Map<String, dynamic> _foodItemToMap(_DailyRecord e, AppLocalizations l10n) {
    final name = e.recipeId.isNotEmpty
        ? (e.recipe?.name ?? l10n.recipe)
        : (e.ingredient?.name ?? l10n.ingredient);
    final slot = e.scheduledAt.trim().isNotEmpty ? e.scheduledAt : e.consumedAt;
    final whenDone = e.consumedEventAt.trim().isNotEmpty
        ? e.consumedEventAt
        : e.consumedAt;
    return {
      'id': e.id,
      'name': name,
      'status': e.isConsumed ? 'consumed' : 'planned',
      'is_taken': e.isConsumed,
      'consumed_at': e.isConsumed ? whenDone : null,
      'slot_iso': slot,
      'amount_grams': e.amountGrams,
      'record': e,
    };
  }

  /// Single renderer for every meal section (Breakfast, Lunch, Dinner, Snack, …).
  Widget _buildFoodItemRow(BuildContext context, Map<String, dynamic> item) {
    final l10n = context.l10n;
    final record = item['record'] as _DailyRecord;
    final showTake = item['consumed_at'] == null;
    final slotIso = (item['slot_iso'] ?? record.consumedAt).toString();
    final consumedIso = item['consumed_at']?.toString();
    final timeLabel = showTake
        ? _fmtTime(slotIso)
        : _fmtTime(
            (consumedIso != null && consumedIso.isNotEmpty)
                ? consumedIso
                : slotIso,
          );
    final missed = () {
      if (!showTake) return false;
      try {
        final slot = DateTime.parse(slotIso).toLocal();
        return slot.isBefore(DateTime.now());
      } catch (_) {
        return false;
      }
    }();
    final grams = (item['amount_grams'] is num)
        ? (item['amount_grams'] as num).toDouble()
        : record.amountGrams;
    final name = item['name']?.toString() ?? '?';
    final showMacros = item['show_macros'] == true;

    final id = (item['id'] ?? '').toString();
    final rowKey = _rowKeys.putIfAbsent(id, () => GlobalKey());
    final highlight = (_highlightLogId ?? '').trim() == id.trim();

    final lineMac = _lineMacrosForDisplay(record);
    final macroLine = l10n.fuelMacrosLine(
      lineMac.p.toStringAsFixed(1),
      lineMac.c.toStringAsFixed(1),
      lineMac.f.toStringAsFixed(1),
      lineMac.cal.round().toString(),
    );

    return Container(
      key: rowKey,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: highlight ? const Color(0xFFFF3B30) : Colors.transparent,
          width: highlight ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            record.recipeId.isNotEmpty ? Icons.outdoor_grill : Icons.egg,
            color: const Color(0xFF00F3FF),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        showTake
                            ? '$timeLabel — ${l10n.planTag} $name (${grams.toStringAsFixed(0)}${l10n.gramsSuffix})'
                            : '$timeLabel — $name (${grams.toStringAsFixed(0)}${l10n.gramsSuffix})',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    if (missed) ...[
                      const SizedBox(width: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'ПРОПУСНАТО',
                          style: const TextStyle(
                            color: Colors.red,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                if (showMacros)
                  Text(
                    macroLine,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF757575),
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ),
          ),
          if (showTake) ...[
            ElevatedButton(
              onPressed: () async => _takePlanned(record),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF050510),
                foregroundColor: const Color(0xFF00F3FF),
                elevation: 0,
                side: const BorderSide(color: Color(0xFF00F3FF), width: 1),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                minimumSize: const Size(64, 40),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
              ),
              child: Text(
                l10n.take,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            IconButton(
              onPressed: () async => _editMealFlow(record),
              icon: const Icon(Icons.edit_outlined, size: 20),
              color: const Color(0xFF00F3FF),
              tooltip: l10n.edit,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
            ),
            IconButton(
              onPressed: () async =>
                  _deleteLog(record.id, removedWasPlanned: true),
              icon: const Icon(Icons.delete_outline, size: 20),
              color: const Color(0xFF00F3FF),
              tooltip: l10n.delete,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
            ),
          ] else
            IconButton(
              onPressed: () async =>
                  _deleteLog(record.id, removedWasPlanned: false),
              icon: const Icon(Icons.delete_outline),
              color: const Color(0xFF00F3FF),
              tooltip: l10n.delete,
            ),
        ],
      ),
    );
  }

  // Food list is fetched inside the full-screen picker now.

  String _dayLabel(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }

  Future<void> _shiftDay(int deltaDays) async {
    setState(() {
      _selectedDay = _selectedDay.add(Duration(days: deltaDays));
    });
    await _fetchAndApplyDailyLogs();
    _subscribeIfToday();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked == null) return;
    if (!mounted) return;
    setState(() {
      _selectedDay = DateTime(picked.year, picked.month, picked.day);
    });
    await _fetchAndApplyDailyLogs();
    _subscribeIfToday();
  }

  Map<String, List<_DailyRecord>> _groupedByMeal() {
    final groups = <String, List<_DailyRecord>>{
      'BREAKFAST': [],
      'LUNCH': [],
      'DINNER': [],
    };

    for (final r in _dailyRecords) {
      final meal = _canonicalMealTypeKey(r.mealType);
      groups.putIfAbsent(meal, () => []);
      groups[meal]!.add(r);
    }
    return groups;
  }

  List<String> _extraMealsForSelectedDate() {
    // IMPORTANT: extras must ONLY come from the currently fetched logs.
    // Since _fetchDailyLogs is date-filtered, this prevents "date bleeding".
    final fromLogs = _dailyRecords
        .map((r) => _canonicalMealTypeKey(r.mealType))
        .where((m) => m.startsWith('EXTRA:'))
        .toSet();
    final merged = fromLogs.toList()..sort();
    return merged;
  }

  String _fmtTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '--:--';
    final local = dt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    final l10n = AppLocalizations.of(context)!;

    final grouped = _groupedByMeal();
    final extras = _extraMealsForSelectedDate();

    final displayTargetProtein = _targetProtein;
    final displayTargetCarbs = _targetCarbs;
    final displayTargetFats = _targetFats;
    final displayTargetCalories = _targetCalories;
    final effectiveTargetProtein = _safeTargetProtein;
    final effectiveTargetCarbs = _safeTargetCarbs;
    final effectiveTargetFats = _safeTargetFats;
    final effectiveTargetCalories = _safeTargetCalories;

    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(l10n.screenFuelLog),
        actions: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _autoRefreshingTargets
                ? const Padding(
                    key: ValueKey('refreshing'),
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    key: const ValueKey('refresh'),
                    onPressed: _refreshSelectedDay,
                    tooltip: l10n.refresh,
                    icon: const Icon(Icons.refresh),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  _error!,
                  style: const TextStyle(color: cyan),
                ),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                        minHeight: constraints.maxHeight,
                      ),
                      child: Column(
                  children: [
                    Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: cyan, width: 2)),
                    ),
                    child: DefaultTextStyle(
                      style: const TextStyle(
                        color: cyan,
                        fontFamily: 'monospace',
                        letterSpacing: 0.6,
                        fontSize: 13,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                onPressed: () => _shiftDay(-1),
                                icon: const Icon(Icons.chevron_left),
                                color: cyan,
                                tooltip: l10n.prevDay,
                              ),
                              Expanded(
                                child: Center(
                                  child: TextButton(
                                    onPressed: _pickDate,
                                    style: TextButton.styleFrom(
                                      foregroundColor: cyan,
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.zero,
                                      ),
                                    ),
                                    child: Text(
                                      _dayLabel(_selectedDay),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.2,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => _shiftDay(1),
                                icon: const Icon(Icons.chevron_right),
                                color: cyan,
                                tooltip: l10n.nextDay,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.nutritionDailyProgress,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                              color: cyan.withValues(alpha: 0.9),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _DualMacroBar(
                            label: l10n.nutritionProtein,
                            consumed: _todayProtein,
                            prognostic: _plannedProtein,
                            target:
                                displayTargetProtein ?? effectiveTargetProtein,
                            unit: l10n.gramsSuffix,
                            decimals: 1,
                          ),
                          const SizedBox(height: 8),
                          _DualMacroBar(
                            label: l10n.nutritionCarbs,
                            consumed: _todayCarbs,
                            prognostic: _plannedCarbs,
                            target: displayTargetCarbs ?? effectiveTargetCarbs,
                            unit: l10n.gramsSuffix,
                            decimals: 1,
                          ),
                          const SizedBox(height: 8),
                          _DualMacroBar(
                            label: l10n.nutritionFats,
                            consumed: _todayFats,
                            prognostic: _plannedFats,
                            target: displayTargetFats ?? effectiveTargetFats,
                            unit: l10n.gramsSuffix,
                            decimals: 1,
                          ),
                          const SizedBox(height: 8),
                          _DualMacroBar(
                            label: l10n.nutritionCal,
                            consumed: _todayCalories.toDouble(),
                            prognostic: _plannedCalories.toDouble(),
                            target:
                                (displayTargetCalories ??
                                        effectiveTargetCalories)
                                    .toDouble(),
                            unit: '',
                            decimals: 0,
                          ),
                        ],
                      ),
                    ),
                  ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                        if (_dailyRecords.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              _isSelectedDayToday()
                                  ? l10n.fuelNoMealsToday
                                  : l10n.fuelNoMealsForDay(
                                      _dayLabel(_selectedDay),
                                    ),
                              style: const TextStyle(
                                color: Color(0x8800F3FF),
                                fontFamily: 'monospace',
                                fontSize: 11,
                                height: 1.35,
                              ),
                            ),
                          ),
                        for (final meal in <String>[
                          'BREAKFAST',
                          'LUNCH',
                          'DINNER',
                          ...extras,
                        ])
                          _MealLogSection(
                            title: localizedMealSectionTitle(l10n, meal),
                            entries: () {
                              final dailyLogs =
                                  grouped[meal] ?? const <_DailyRecord>[];
                              final sortedLogs = List<_DailyRecord>.from(
                                dailyLogs,
                              );
                              sortedLogs.sort(
                                (a, b) => a.consumedAt.compareTo(b.consumedAt),
                              );
                              return sortedLogs;
                            }(),
                            onPlanMeal: () => _planMealFlow(meal),
                            toItemMap: (e) => _foodItemToMap(e, l10n),
                            buildFoodItemRow: _buildFoodItemRow,
                          ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: () async {
                            // Global quick-add for snacks / extras.
                            const mt = 'EXTRA:SNACK';
                            await _planMealFlow(mt);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: cyan,
                            side: const BorderSide(color: cyan, width: 1),
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero,
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 8,
                            ),
                          ),
                          child: Text(
                            l10n.actionAddExtra,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
        },
      ),
      ),
    );
  }
}

class _MealLogSection extends StatefulWidget {
  final String title;
  final List<_DailyRecord> entries;
  final VoidCallback onPlanMeal;
  final Map<String, dynamic> Function(_DailyRecord e) toItemMap;
  final Widget Function(BuildContext context, Map<String, dynamic> item)
  buildFoodItemRow;

  const _MealLogSection({
    required this.title,
    required this.entries,
    required this.onPlanMeal,
    required this.toItemMap,
    required this.buildFoodItemRow,
  });

  static void _accumulateLineMacros(_DailyRecord e, List<double> out) {
    double p = 0, c = 0, f = 0, cal = 0;
    if (e.ingredient != null && e.amountGrams > 0) {
      final factor = e.amountGrams / 100.0;
      p += e.ingredient!.proteinPer100g * factor;
      c += e.ingredient!.carbsPer100g * factor;
      f += e.ingredient!.fatPer100g * factor;
      cal += e.ingredient!.caloriesPer100g * factor;
    } else if (e.recipe != null && e.amountGrams > 0) {
      double totalWeight = 0.0;
      double rp = 0.0, rc = 0.0, rf = 0.0, rcal = 0.0;
      for (final ri in e.recipe!.recipeIngredients) {
        final ing = ri.ingredient;
        if (ing == null) continue;
        final g = ri.amountGrams;
        if (g <= 0) continue;
        totalWeight += g;
        final factor = g / 100.0;
        rp += ing.proteinPer100g * factor;
        rc += ing.carbsPer100g * factor;
        rf += ing.fatPer100g * factor;
        rcal += ing.caloriesPer100g * factor;
      }
      if (totalWeight > 0) {
        final perGramP = rp / totalWeight;
        final perGramC = rc / totalWeight;
        final perGramF = rf / totalWeight;
        final perGramCal = rcal / totalWeight;
        p += perGramP * e.amountGrams;
        c += perGramC * e.amountGrams;
        f += perGramF * e.amountGrams;
        cal += perGramCal * e.amountGrams;
      }
    }
    out[0] += p;
    out[1] += c;
    out[2] += f;
    out[3] += cal;
  }

  @override
  State<_MealLogSection> createState() => _MealLogSectionState();
}

class _NotchedFramePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double notchWidth;
  final double notchCenterX;

  _NotchedFramePainter({
    required this.color,
    required this.strokeWidth,
    required this.notchWidth,
    required this.notchCenterX,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final r = Rect.fromLTWH(0, 0, size.width, size.height);
    final leftNotch = (notchCenterX - notchWidth / 2).clamp(
      6.0,
      size.width - 6.0,
    );
    final rightNotch = (notchCenterX + notchWidth / 2).clamp(
      6.0,
      size.width - 6.0,
    );

    // Top border (split around notch). Draw at y=0, leave the notch gap.
    canvas.drawLine(const Offset(0, 0), Offset(leftNotch, 0), p);
    canvas.drawLine(Offset(rightNotch, 0), Offset(size.width, 0), p);

    // Remaining borders
    canvas.drawLine(const Offset(0, 0), Offset(0, size.height), p);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, size.height), p);
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), p);

    // Subtle inner glow
    final glow = Paint()
      ..color = color.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;
    canvas.drawRect(r.deflate(1.0), glow);
  }

  @override
  bool shouldRepaint(covariant _NotchedFramePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.notchWidth != notchWidth ||
        oldDelegate.notchCenterX != notchCenterX;
  }
}

class _MealLogSectionState extends State<_MealLogSection> {
  bool _detailed = false;

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    final l10n = context.l10n;

    final entries = widget.entries;
    final toItemMap = widget.toItemMap;
    final buildFoodItemRow = widget.buildFoodItemRow;
    final onPlanMeal = widget.onPlanMeal;
    final title = widget.title;

    final planned =
        entries.where((e) => toItemMap(e)['consumed_at'] == null).toList()
          ..sort((a, b) => a.consumedAt.compareTo(b.consumedAt));
    final consumed =
        entries.where((e) => toItemMap(e)['consumed_at'] != null).toList()
          ..sort((a, b) => a.consumedAt.compareTo(b.consumedAt));

    final subAll = <double>[0, 0, 0, 0];
    for (final e in entries) {
      _MealLogSection._accumulateLineMacros(e, subAll);
    }
    final subPlanned = <double>[0, 0, 0, 0];
    for (final e in planned) {
      _MealLogSection._accumulateLineMacros(e, subPlanned);
    }
    final subConsumed = <double>[0, 0, 0, 0];
    for (final e in consumed) {
      _MealLogSection._accumulateLineMacros(e, subConsumed);
    }

    const titleNeon = Color(0xFF00FFFF);
    final titleStyle = const TextStyle(
      color: titleNeon,
      fontFamily: 'monospace',
      fontWeight: FontWeight.bold,
      letterSpacing: 1.4,
      fontSize: 16,
    );
    final tp = TextPainter(
      text: TextSpan(text: title.toUpperCase(), style: titleStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    // notch includes title + detail-toggle icon spacing (48px tap target)
    final notchW = tp.width + 26 + 52;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onPlanMeal,
        splashColor: const Color(0x2200F3FF),
        highlightColor: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final notchCenterX = w / 2;
            return CustomPaint(
              painter: _NotchedFramePainter(
                color: cyan,
                strokeWidth: 1,
                notchWidth: notchW.clamp(80.0, w - 16),
                notchCenterX: notchCenterX,
              ),
              child: Container(
                color: bg,
                // More top padding so header notch content never clips.
                padding: const EdgeInsets.fromLTRB(12, 26, 12, 12),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Title embedded in top border notch.
                    Positioned(
                      left: 0,
                      right: 0,
                      top: -24,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          color: bg,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(title.toUpperCase(), style: titleStyle),
                              const SizedBox(width: 6),
                              IconButton(
                                onPressed: () =>
                                    setState(() => _detailed = !_detailed),
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(52, 52),
                                  padding: const EdgeInsets.all(13),
                                  tapTargetSize:
                                      MaterialTapTargetSize.padded,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 52,
                                  minHeight: 52,
                                ),
                                iconSize: 26,
                                icon: Icon(
                                  _detailed
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  size: 26,
                                  color: _detailed
                                      ? AppColors.cyberGold
                                          .withValues(alpha: 0.75)
                                      : AppColors.cyberGold,
                                ),
                                tooltip: _detailed
                                    ? 'Hide details'
                                    : 'Show details',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    DefaultTextStyle(
                      style: const TextStyle(
                        color: cyan,
                        fontFamily: 'monospace',
                        letterSpacing: 0.4,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          if (_detailed) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${l10n.subtotal}  ${l10n.fuelMacrosLine(subAll[0].toStringAsFixed(1), subAll[1].toStringAsFixed(1), subAll[2].toStringAsFixed(1), subAll[3].round().toString())}',
                              style: const TextStyle(
                                fontSize: 12,
                                letterSpacing: 0.6,
                              ),
                            ),
                            if (planned.isNotEmpty || consumed.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                l10n.formatMacroCompare(
                                  subConsumed,
                                  subPlanned,
                                ),
                                style: const TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 0.4,
                                  color: Color(0x8800F3FF),
                                ),
                              ),
                            ],
                          ],

                          const SizedBox(height: 10),
                          if (entries.isEmpty)
                            Text(
                              l10n.fuelNoItemsBlock,
                              style: const TextStyle(
                                color: Color(0x8800F3FF),
                                fontFamily: 'monospace',
                                fontSize: 11,
                                height: 1.3,
                              ),
                            )
                          else ...[
                            if (planned.isNotEmpty) ...[
                              Text(
                                l10n.plannedUpper,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0,
                                  color: Color(0xFF88CCFF),
                                ),
                              ),
                              const SizedBox(height: 6),
                              for (final e in planned)
                                buildFoodItemRow(context, {
                                  ...toItemMap(e),
                                  'show_macros': _detailed,
                                }),
                              if (consumed.isNotEmpty)
                                const SizedBox(height: 8),
                            ],
                            if (consumed.isNotEmpty) ...[
                              Text(
                                l10n.consumedUpper,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 6),
                              for (final e in consumed)
                                buildFoodItemRow(context, {
                                  ...toItemMap(e),
                                  'show_macros': _detailed,
                                }),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Grams prompt for food logging — controller lifecycle tied to this route.
class _FuelGramsDialog extends StatefulWidget {
  final String foodLabel;
  final LogIntakeTab initialTab;

  const _FuelGramsDialog({
    required this.foodLabel,
    required this.initialTab,
  });

  @override
  State<_FuelGramsDialog> createState() => _FuelGramsDialogState();
}

enum LogIntakeTab { logNow, plan }

class _FuelGramsDialogState extends State<_FuelGramsDialog> {
  late final TextEditingController _controller;
  late final TextEditingController _timeController;
  ReminderState _reminder = const ReminderState.disabled();
  LogIntakeTab _selectedTab = LogIntakeTab.logNow;
  String _selectedBlock = 'MORNING';
  ScheduleSelection _schedule = const ScheduleSelection();
  late List<String> _units;
  late String _unit;

  static const _blocks = <String>['MORNING', 'AFTERNOON', 'EVENING', 'NIGHT'];
  static String _fmtNowHhmm() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _timeController = TextEditingController(text: _fmtNowHhmm());
    _selectedTab = widget.initialTab;
    final sys = MeasurementSettings.system.value;
    _units = UnitOptions.forContext(UnitContext.food, sys);
    _unit = UnitOptions.defaultUnit(UnitContext.food, sys);
  }

  @override
  void dispose() {
    _controller.dispose();
    _timeController.dispose();
    super.dispose();
  }

  static TimeOfDay _parseHhmm(String hhmm) {
    final parts = hhmm.trim().split(':');
    if (parts.length != 2) return const TimeOfDay(hour: 8, minute: 0);
    final h = int.tryParse(parts[0]) ?? 8;
    final m = int.tryParse(parts[1]) ?? 0;
    return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    final loc = context.l10n;

    final timeLabel = loc.intakeTimeAt(_timeController.text);
    return AlertDialog(
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      title: Text(
        loc.fuelLogIntakeTitle,
        style: const TextStyle(color: cyan, fontFamily: 'monospace'),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<LogIntakeTab>(
                segments: [
                  ButtonSegment<LogIntakeTab>(
                    value: LogIntakeTab.logNow,
                    label: Text(
                      loc.intakeAddModeLogNow,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  ButtonSegment<LogIntakeTab>(
                    value: LogIntakeTab.plan,
                    label: Text(
                      loc.intakeAddModePlan,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
                selected: {_selectedTab},
                onSelectionChanged: (newSelection) {
                  setState(() => _selectedTab = newSelection.first);
                },
                style: ButtonStyle(
                  foregroundColor: WidgetStateProperty.all(cyan),
                  side: WidgetStateProperty.all(
                    const BorderSide(color: cyan, width: 1),
                  ),
                  shape: WidgetStateProperty.all(
                    const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  ),
                ),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 8),
              Text(
                'DEBUG: CURRENT TAB IS $_selectedTab',
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text(
                    'Block',
                    style: TextStyle(
                      color: cyan,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButton<String>(
                      value: _selectedBlock,
                      dropdownColor: bg,
                      isExpanded: true,
                      underline: Container(height: 1, color: cyan),
                      items: _blocks
                          .map(
                            (b) => DropdownMenuItem(
                              value: b,
                              child: Text(
                                localizedTimeBlock(loc, b),
                                style: const TextStyle(
                                  color: cyan,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (String? val) {
                        if (val == null) return;
                        setState(() {
                          _selectedBlock = val;
                          if (val == 'MORNING') {
                            _timeController.text = '08:00';
                          } else if (val == 'AFTERNOON') {
                            _timeController.text = '13:00';
                          } else if (val == 'EVENING') {
                            _timeController.text = '19:00';
                          } else if (val == 'NIGHT') {
                            _timeController.text = '22:00';
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _timeController,
                readOnly: true,
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _parseHhmm(_timeController.text),
                  );
                  if (picked == null) return;
                  if (!mounted) return;
                  setState(() {
                    _timeController.text =
                        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                  });
                },
                style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  labelText: timeLabel,
                  enabledBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: cyan, width: 1),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: cyan, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: const TextStyle(
                        color: cyan,
                        fontFamily: 'monospace',
                      ),
                      decoration: InputDecoration(
                        labelText: widget.foodLabel,
                        enabledBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide: BorderSide(color: cyan, width: 1),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide: BorderSide(color: cyan, width: 1.5),
                        ),
                      ),
                      autofocus: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 120,
                    child: DropdownButtonFormField<String>(
                      initialValue: _unit,
                      dropdownColor: bg,
                      decoration: InputDecoration(
                        labelText: loc.unit,
                        enabledBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide: BorderSide(color: cyan, width: 1),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide: BorderSide(color: cyan, width: 1.5),
                        ),
                      ),
                      items: _units
                          .map(
                            (u) => DropdownMenuItem(
                              value: u,
                              child: Text(
                                u,
                                style: const TextStyle(
                                  color: cyan,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (v) => setState(() => _unit = v ?? _unit),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ReminderSection(
                state: _reminder,
                onChanged: (s) => setState(() => _reminder = s),
              ),
              const SizedBox(height: 12),
              if (_selectedTab == LogIntakeTab.plan)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.cyberGold, width: 2),
                  ),
                  child: ScheduleSelector(
                    selection: _schedule,
                    onChanged: (s) => setState(() => _schedule = s),
                    baseDate: DateTime.now(),
                  ),
                )
              else
                const SizedBox.shrink(),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop<
                ({
                  String grams,
                  ReminderState reminder,
                  String unit,
                  LogIntakeTab tab,
                  String block,
                  String timeText,
                  ScheduleSelection schedule,
                })?
              >(null),
          child: Text(loc.cancel),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop((
              grams: _controller.text.trim(),
              reminder: _reminder,
              unit: _unit,
              tab: _selectedTab,
              block: _selectedBlock,
              timeText: _timeController.text.trim(),
              schedule: _schedule,
            ));
          },
          child: Text(loc.ok),
        ),
      ],
    );
  }
}

class _FoodLogSheet extends StatefulWidget {
  final String logsTable;
  final String mealType;
  final String consumedAtIsoUtc;
  final bool planOnly;
  final _DailyRecord? editingRecord;

  const _FoodLogSheet({
    required this.logsTable,
    required this.mealType,
    required this.consumedAtIsoUtc,
    this.planOnly = false,
    this.editingRecord,
  });

  @override
  State<_FoodLogSheet> createState() => _FoodLogSheetState();
}

class _FoodLogSheetState extends State<_FoodLogSheet> {
  final _client = Supabase.instance.client;
  final _controller = TextEditingController();

  String _q = '';
  bool _loading = true;
  Object? _error;
  List<_FoodPick> _all = const [];
  List<_FoodPick> _results = const [];
  int _requestId = 0;
  TextEditingController? _gramsEditCtrl;
  DateTime? _editConsumedAtLocal;
  _EditReminderMode _editReminderMode = _EditReminderMode.none;
  TimeOfDay? _editSpecificReminder;
  final _editMinutesBeforeCtrl = TextEditingController(text: '5');
  int _editMinutesBefore = 5;

  @override
  void initState() {
    super.initState();
    final edit = widget.editingRecord;
    if (edit != null) {
      final g = edit.amountGrams;
      final text = g == g.roundToDouble()
          ? g.toInt().toString()
          : g.toStringAsFixed(1);
      _gramsEditCtrl = TextEditingController(text: text);
      _editConsumedAtLocal =
          DateTime.tryParse(edit.consumedAt)?.toLocal() ?? DateTime.now();
      final existingReminder = DateTime.tryParse(edit.reminderAt)?.toLocal();
      final existingOffset = edit.reminderOffsetMinutes;
      if (existingOffset != null && existingOffset > 0) {
        _editReminderMode = _EditReminderMode.minutesBefore;
        _editMinutesBefore = existingOffset;
        _editMinutesBeforeCtrl.text = existingOffset.toString();
      } else if (existingReminder != null) {
        _editReminderMode = _EditReminderMode.specific;
        _editSpecificReminder = TimeOfDay.fromDateTime(existingReminder);
      } else {
        _editReminderMode = _EditReminderMode.none;
        _editMinutesBefore = 30;
        _editMinutesBeforeCtrl.text = '30';
      }
      _loading = false;
    } else {
      _loadAll();
    }
  }

  @override
  void dispose() {
    _gramsEditCtrl?.dispose();
    _editMinutesBeforeCtrl.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openBarcodeFlow() async {
    if (!mounted) return;
    final res = await BarcodeScannerScreen.pushForResult(
      context,
      pickCodeOnly: true,
    );
    final barcode = (res?['barcode'] ?? '').toString().trim();
    if (barcode.isEmpty || !mounted) return;

    try {
      final prod = await _fetchOpenFoodFacts(barcode);
      if (prod == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Product not found. Please enter manually.'),
          ),
        );
        return;
      }

      if (!mounted) return;
      final created = await showDialog<_FoodPick?>(
        context: context,
        builder: (_) => _OffAddIngredientDialog(product: prod),
      );
      if (created == null) return;

      // Update local list and focus search.
      await _loadAll();
      if (!mounted) return;
      _controller.text = created.name;
      _applyFilter(created.name);

      // Immediately continue into the normal grams/reminder flow.
      await _handleFoodPickTap(created);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Barcode lookup failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<_OffProduct?> _fetchOpenFoodFacts(String barcode) async {
    final uri = Uri.parse(
      'https://world.openfoodfacts.org/api/v2/product/$barcode.json',
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;
    final json = jsonDecode(res.body);
    if (json is! Map<String, dynamic>) return null;
    final status = json['status'];
    if (status is num && status.toInt() != 1) return null;
    if (status is String && status.trim() != '1') return null;
    final product = json['product'];
    if (product is! Map<String, dynamic>) return null;

    String s(dynamic v) => (v ?? '').toString().trim();
    double d(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    final name = s(product['product_name']).isNotEmpty
        ? s(product['product_name'])
        : s(product['generic_name']);
    if (name.trim().isEmpty) return null;
    final nutr = product['nutriments'];
    final nutriments = (nutr is Map<String, dynamic>)
        ? nutr
        : const <String, dynamic>{};

    final kcal = d(nutriments['energy-kcal_100g']);
    final p = d(nutriments['proteins_100g']);
    final c = d(nutriments['carbohydrates_100g']);
    final f = d(nutriments['fat_100g']);

    return _OffProduct(
      barcode: barcode,
      name: name.trim(),
      caloriesPer100g: kcal,
      proteinPer100g: p,
      carbsPer100g: c,
      fatPer100g: f,
    );
  }

  Future<void> _handleFoodPickTap(_FoodPick item) async {
    final picked = await _promptGrams(
      item.name,
      initialTab: widget.planOnly ? LogIntakeTab.plan : LogIntakeTab.logNow,
    );
    if (picked == null) return;
    final grams = picked.grams;
    final unit = picked.unit;

    final base = DateTime.tryParse(widget.consumedAtIsoUtc)?.toLocal();
    final local = base ?? DateTime.now();

    final logNow = picked.tab == LogIntakeTab.logNow;
    final intakeTod = picked.intakeTime;
    final intakeLocal = DateTime(
      local.year,
      local.month,
      local.day,
      intakeTod.hour,
      intakeTod.minute,
    );

    DateTime? reminderLocal;
    int? reminderOffsetMinutes;
    if (picked.reminder.enabled) {
      if (picked.reminder.mode == ReminderMode.atConsumptionTime) {
        reminderLocal = intakeLocal;
        reminderOffsetMinutes = 0;
      } else {
        final off = picked.reminder.offsetMinutes;
        reminderLocal = intakeLocal.subtract(Duration(minutes: off));
        reminderOffsetMinutes = off;
      }
    }

    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.msgSignInLogFood),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final rows = <Map<String, dynamic>>[];
      final reminderLocals = <DateTime?>[];

      final dates = logNow ? <DateTime>[picked.targetDates.first] : picked.targetDates;
      for (var i = 0; i < dates.length; i++) {
        final d = dates[i];
        final intakeI = DateTime(
          d.year,
          d.month,
          d.day,
          intakeTod.hour,
          intakeTod.minute,
        );
        final reminderI = reminderLocal == null
            ? null
            : DateTime(
                d.year,
                d.month,
                d.day,
                reminderLocal.hour,
                reminderLocal.minute,
              );
        final isConsumedI = logNow;

        final extraI = reminderI == null
            ? const <String, dynamic>{}
            : <String, dynamic>{
                'reminder_at': reminderI.toUtc().toIso8601String(),
                'reminder_offset_minutes': reminderOffsetMinutes,
              };

        final payload = <String, dynamic>{
          'user_id': uid,
          'created_at': intakeI.toUtc().toIso8601String(),
          'scheduled_at': intakeI.toUtc().toIso8601String(),
          if (item.type == _FoodType.ingredient)
            'ingredient_id': item.id
          else
            'recipe_id': item.id,
          'amount_grams': grams,
          'unit': unit,
          'meal_type': widget.mealType,
          'consumed_at': intakeI.toUtc().toIso8601String(),
          'is_consumed': isConsumedI,
          ...extraI,
        };
        rows.add(payload);
        reminderLocals.add(reminderI);
      }

      final inserted = await _client
          .from(widget.logsTable)
          .insert(rows)
          .select('id');
      final insertedList = (inserted as List).cast<Map<String, dynamic>>();

      if (!mounted) return;

      for (var i = 0; i < insertedList.length; i++) {
        final newId = (insertedList[i]['id'] ?? '').toString().trim();
        final rLocal = (i < reminderLocals.length) ? reminderLocals[i] : null;
        if (rLocal != null && newId.isNotEmpty) {
          if (!mounted) return;
          final target = (i < dates.length) ? dates[i] : DateTime.now();
          await NotificationService.scheduleByKey(
            key: 'daily_logs:$newId',
            title: context.l10n.reminderTitleMeal(item.name),
            body: context.l10n.reminderBody,
            whenLocal: rLocal,
            payload: {
              'item_type': 'food',
              'item_id': newId,
              'target_date':
                  '${target.year.toString().padLeft(4, '0')}-${target.month.toString().padLeft(2, '0')}-${target.day.toString().padLeft(2, '0')}',
            },
          );
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, st) {
      // ignore: avoid_print
      print('FOOD LOG FLOW ERROR: $e');
      // ignore: avoid_print
      print('STACKTRACE: $st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(supabaseWriteErrorMessage(e)),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _loadAll() async {
    final rid = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final ingredientsData = await _client
          .from('ingredients')
          .select()
          .order('name')
          .limit(500);
      final recipesData = await _client
          .from('recipes')
          .select('id,name')
          .order('name')
          .limit(500);
      if (!mounted || rid != _requestId) return;

      final ingredientRows = (ingredientsData as List)
          .cast<Map<String, dynamic>>();
      final recipeRows = (recipesData as List).cast<Map<String, dynamic>>();

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

      bool asBool(dynamic v) {
        if (v == null) return false;
        if (v is bool) return v;
        final s = v.toString().trim().toLowerCase();
        return s == 'true' || s == 't' || s == '1' || s == 'yes';
      }

      final picks = <_FoodPick>[
        ...ingredientRows.map(
          (r) => _FoodPick(
            id: (r['id'] ?? '').toString(),
            name: (r['name'] ?? '').toString(),
            type: _FoodType.ingredient,
            proteinPer100g: asDouble(r['protein_per_100g']),
            carbsPer100g: asDouble(r['carbs_per_100g']),
            fatPer100g: asDouble(r['fat_per_100g']),
            caloriesPer100g: asDouble(r['calories_per_100g']),
            isGlutenFree: asBool(r['is_gluten_free']),
            glycemicIndex: asIntOrNull(r['glycemic_index']),
            allergenLevel: Ingredient.parseAllergenLevel(r['allergen_level']),
          ),
        ),
        ...recipeRows.map(
          (r) => _FoodPick(
            id: (r['id'] ?? '').toString(),
            name: (r['name'] ?? '').toString(),
            type: _FoodType.recipe,
          ),
        ),
      ];

      final sorted = List<_FoodPick>.from(picks);
      sorted.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      setState(() {
        _all = sorted;
        _results = _all;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || rid != _requestId) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _applyFilter(String q) {
    final trimmed = q.trim().toLowerCase();
    setState(() {
      _q = q;
      if (trimmed.isEmpty) {
        _results = _all;
      } else {
        _results = _all
            .where((i) => i.name.toLowerCase().contains(trimmed))
            .toList(growable: false);
      }
    });
  }

  DateTime? _computeEditReminderAtLocal() {
    final base = _editConsumedAtLocal;
    if (base == null) return null;
    switch (_editReminderMode) {
      case _EditReminderMode.none:
        return null;
      case _EditReminderMode.specific:
        final t = _editSpecificReminder;
        if (t == null) return null;
        return DateTime(base.year, base.month, base.day, t.hour, t.minute);
      case _EditReminderMode.minutesBefore:
        final mins = _editMinutesBefore;
        if (mins <= 0) return null;
        return base.subtract(Duration(minutes: mins));
    }
  }

  List<TextSpan> _highlight(String text, String q) {
    const cyan = Color(0xFF00F3FF);
    final query = q.trim();
    if (query.isEmpty) {
      return [const TextSpan(text: '', children: [])]
        ..clear()
        ..add(TextSpan(text: text));
    }
    final lower = text.toLowerCase();
    final ql = query.toLowerCase();
    final idx = lower.indexOf(ql);
    if (idx < 0) return [TextSpan(text: text)];

    return [
      TextSpan(text: text.substring(0, idx)),
      TextSpan(
        text: text.substring(idx, idx + query.length),
        style: const TextStyle(color: cyan, fontWeight: FontWeight.w800),
      ),
      TextSpan(text: text.substring(idx + query.length)),
    ];
  }

  Future<void> _saveEdit() async {
    const cyan = Color(0xFF00F3FF);
    final e = widget.editingRecord;
    final ctrl = _gramsEditCtrl;
    if (e == null || ctrl == null) return;
    final raw = ctrl.text.trim().replaceAll(',', '.');
    final v = double.tryParse(raw);
    if (v == null || v <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.msgValidAmountGrams)));
      return;
    }
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.msgSignInUpdateLogs),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
      final consumedLocal = _editConsumedAtLocal ?? DateTime.now();
      final reminderLocal = _computeEditReminderAtLocal();
      await _client
          .from(widget.logsTable)
          .update({
            'user_id': uid,
            'amount_grams': v,
            'consumed_at': consumedLocal.toUtc().toIso8601String(),
            'scheduled_at': consumedLocal.toUtc().toIso8601String(),
            'created_at': consumedLocal.toUtc().toIso8601String(),
            'reminder_at': reminderLocal?.toUtc().toIso8601String(),
            'reminder_offset_minutes':
                _editReminderMode == _EditReminderMode.minutesBefore
                ? _editMinutesBefore
                : (_editReminderMode == _EditReminderMode.none ? null : 0),
          })
          .eq('id', e.id)
          .eq('user_id', uid);

      if (!mounted) return;
      await NotificationService.cancelByKey('daily_logs:${e.id}');
      if (!mounted) return;
      if (reminderLocal != null) {
        final name = e.recipeId.isNotEmpty
            ? (e.recipe?.name ?? context.l10n.recipe)
            : (e.ingredient?.name ?? context.l10n.ingredient);
        await NotificationService.scheduleByKey(
          key: 'daily_logs:${e.id}',
          title: context.l10n.reminderTitleMeal(name),
          body: context.l10n.reminderBody,
          whenLocal: reminderLocal,
          payload: {
            'item_type': 'food',
            'item_id': e.id,
            'target_date':
                '${consumedLocal.year.toString().padLeft(4, '0')}-${consumedLocal.month.toString().padLeft(2, '0')}-${consumedLocal.day.toString().padLeft(2, '0')}',
          },
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(supabaseWriteErrorMessage(err)),
          backgroundColor: Colors.redAccent,
          showCloseIcon: true,
          closeIconColor: cyan,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    final loc = context.l10n;

    final edit = widget.editingRecord;
    if (edit != null) {
      final name = edit.recipeId.isNotEmpty
          ? (edit.recipe?.name ?? loc.recipe)
          : (edit.ingredient?.name ?? loc.ingredient);
      final typeLabel = edit.recipeId.isNotEmpty ? loc.recipe : loc.ingredient;

      return Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: cyan, width: 2)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      color: cyan,
                      tooltip: loc.close,
                    ),
                    Expanded(
                      child: Text(
                        loc.fuelEditEntryTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: cyan,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      typeLabel.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0x8800F3FF),
                        fontFamily: 'monospace',
                        fontSize: 11,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      name,
                      style: const TextStyle(
                        color: cyan,
                        fontFamily: 'monospace',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final base = _editConsumedAtLocal ?? DateTime.now();
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(base),
                        );
                        if (picked == null) return;
                        if (!mounted) return;
                        setState(() {
                          _editConsumedAtLocal = DateTime(
                            base.year,
                            base.month,
                            base.day,
                            picked.hour,
                            picked.minute,
                          );
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cyan,
                        side: const BorderSide(color: cyan, width: 1),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                      ),
                      icon: const Icon(Icons.schedule),
                      label: Text(
                        () {
                          final base = _editConsumedAtLocal ?? DateTime.now();
                          final hh = base.hour.toString().padLeft(2, '0');
                          final mm = base.minute.toString().padLeft(2, '0');
                          return loc.fuelConsumptionTimeAt('$hh:$mm');
                        }(),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _gramsEditCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        color: cyan,
                        fontFamily: 'monospace',
                      ),
                      decoration: InputDecoration(
                        labelText: loc.fuelAmountGrams,
                        enabledBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide: BorderSide(color: cyan, width: 1),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide: BorderSide(color: cyan, width: 1.5),
                        ),
                      ),
                      autofocus: true,
                    ),
                    const SizedBox(height: 24),
                    _EditReminderSection(
                      mode: _editReminderMode,
                      onModeChanged: (m) =>
                          setState(() => _editReminderMode = m),
                      specificTime: _editSpecificReminder,
                      onPickSpecific: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _editSpecificReminder ?? TimeOfDay.now(),
                        );
                        if (picked == null) return;
                        if (!mounted) return;
                        setState(() => _editSpecificReminder = picked);
                      },
                      minutesBeforeController: _editMinutesBeforeCtrl,
                      onMinutesChanged: (mins) {
                        // Prevent crashes / weirdness on empty: keep last valid.
                        if (mins <= 0) return;
                        setState(() => _editMinutesBefore = mins);
                      },
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _saveEdit,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cyan,
                        side: const BorderSide(color: cyan, width: 1),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        loc.save,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            ),
          ),
        ),
      );
    }

    final planBanner = widget.planOnly
        ? Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0x2288CCFF),
            child: Text(
              loc.fuelPlanningSaved,
              style: const TextStyle(
                color: Color(0xFF88CCFF),
                fontFamily: 'monospace',
                fontSize: 11,
                letterSpacing: 0.8,
              ),
            ),
          )
        : const SizedBox.shrink();

    return Scaffold(
      backgroundColor: bg,
      body: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: cyan, width: 2)),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  color: cyan,
                  tooltip: loc.close,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onChanged: _applyFilter,
                    style: const TextStyle(
                      color: cyan,
                      fontFamily: 'monospace',
                    ),
                    decoration: InputDecoration(
                      hintText: loc.searchHint,
                      hintStyle: const TextStyle(
                        color: Color(0xFF757575),
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(Icons.search),
                      enabledBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: cyan, width: 1),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: cyan, width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Scan barcode',
                  onPressed: _openBarcodeFlow,
                  icon: const Icon(Icons.qr_code_scanner),
                  color: AppColors.cyberGold,
                ),
              ],
            ),
          ),
          planBanner,
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      _error.toString(),
                      style: const TextStyle(color: cyan),
                    ),
                  )
                : _results.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            loc.noItemsFound,
                            style: const TextStyle(
                              color: cyan,
                              fontFamily: 'monospace',
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final item = _results[index];
                      return ListTile(
                        leading: Icon(
                          item.type == _FoodType.ingredient
                              ? Icons.egg
                              : Icons.outdoor_grill,
                          color: cyan,
                        ),
                        title: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              color: Color(0xAA00F3FF),
                              fontFamily: 'monospace',
                              letterSpacing: 0.6,
                            ),
                            children: _highlight(item.name, _q),
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.listMacroSubtitle(loc),
                              style: const TextStyle(
                                color: Color(0xFF757575),
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                            if (item.showsDietBadges) ...[
                              const SizedBox(height: 4),
                              DietIndicatorBadges(
                                isGlutenFree: item.isGlutenFree,
                                glycemicIndex: item.glycemicIndex,
                                allergenLevel: item.allergenLevel,
                              ),
                            ],
                          ],
                        ),
                        onTap: () async => _handleFoodPickTap(item),
                      );
                    },
                  ),
          ),
          ],
        ),
      ),
    );
  }

  Future<
    ({
      double grams,
      ReminderState reminder,
      String unit,
      LogIntakeTab tab,
      String block,
      TimeOfDay intakeTime,
      List<DateTime> targetDates,
    })?
  >
  _promptGrams(String label, {required LogIntakeTab initialTab}) async {
    final res =
        await showDialog<
          ({
            String grams,
            ReminderState reminder,
            String unit,
            LogIntakeTab tab,
            String block,
            String timeText,
            ScheduleSelection schedule,
          })?
        >(
          context: context,
          builder: (context) => _FuelGramsDialog(
            foodLabel: label,
            initialTab: initialTab,
          ),
        );
    if (res == null) return null;
    final raw = res.grams.trim();
    if (raw.isEmpty) return null;
    final v = double.tryParse(raw.replaceAll(',', '.'));
    if (v == null || v <= 0) return null;

    // Store metric, display local:
    // - DB `amount_grams` stays grams (metric).
    // - If user logs in imperial, convert to grams for macro math + storage.
    double gramsMetric;
    switch (res.unit) {
      case 'oz':
        gramsMetric = UnitConverter.ozToG(v);
        break;
      case 'g':
        gramsMetric = v;
        break;
      case 'ml':
        // We store the metric numeric in the grams column across the app today.
        // For liquids this is an approximation (1ml ~= 1g) unless we add density later.
        gramsMetric = v;
        break;
      case 'fl oz':
        gramsMetric = UnitConverter.flOzToMl(v);
        break;
      default:
        gramsMetric = v;
        break;
    }

    final intakeTime = _FuelGramsDialogState._parseHhmm(res.timeText);
    final baseDate = DateTime.now();
    final baseDateOnly = DateTime(baseDate.year, baseDate.month, baseDate.day);
    final targetDates = res.tab == LogIntakeTab.plan
        ? res.schedule.resolveDates(baseDateOnly)
        : <DateTime>[baseDateOnly];

    return (
      grams: gramsMetric,
      reminder: res.reminder,
      unit: res.unit,
      tab: res.tab,
      block: res.block,
      intakeTime: intakeTime,
      targetDates: targetDates,
    );
  }
}

// (legacy picker removed; logging happens inside _FoodLogSheet)
class _DailyRecord {
  final String id;
  final String mealType;

  /// Sort key / legacy slot; prefer [scheduledAt] and [consumedEventAt] for display.
  final String consumedAt;

  /// Planned time (`scheduled_at` or fallback to slot in `consumed_at`).
  final String scheduledAt;

  /// Actual consumption instant when [isConsumed] (from `consumed_at`).
  final String consumedEventAt;
  final String reminderAt;
  final int? reminderOffsetMinutes;
  final double amountGrams;
  final String ingredientId;
  final String recipeId;
  final Ingredient? ingredient;
  final _Recipe? recipe;
  final bool isConsumed;

  const _DailyRecord({
    required this.id,
    required this.mealType,
    required this.consumedAt,
    this.scheduledAt = '',
    this.consumedEventAt = '',
    required this.reminderAt,
    required this.reminderOffsetMinutes,
    required this.amountGrams,
    required this.ingredientId,
    required this.recipeId,
    required this.ingredient,
    required this.recipe,
    this.isConsumed = true,
  });
}

class _Recipe {
  final String id;
  final String name;
  final double? calories;
  final double? protein;
  final double? carbs;
  final double? fats;
  final List<_RecipeIngredient> recipeIngredients;

  const _Recipe({
    required this.id,
    required this.name,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fats,
    required this.recipeIngredients,
  });

  const _Recipe.empty()
    : id = '',
      name = '',
      calories = null,
      protein = null,
      carbs = null,
      fats = null,
      recipeIngredients = const [];

  factory _Recipe.fromJson(Map<String, dynamic> json) {
    double? asD(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    // Try a few common column names for manual macros.
    final calories =
        asD(json['calories']) ??
        asD(json['calories_kcal']) ??
        asD(json['calories_total']);
    final protein =
        asD(json['protein']) ??
        asD(json['protein_g']) ??
        asD(json['protein_total']);
    final carbs =
        asD(json['carbs']) ?? asD(json['carbs_g']) ?? asD(json['carbs_total']);
    final fats =
        asD(json['fats']) ??
        asD(json['fat']) ??
        asD(json['fat_g']) ??
        asD(json['fats_total']);

    final riRaw = json['recipe_ingredients'];
    final ri = <_RecipeIngredient>[];
    if (riRaw is List) {
      for (final x in riRaw) {
        if (x is Map<String, dynamic>) {
          ri.add(_RecipeIngredient.fromJson(x));
        }
      }
    }

    return _Recipe(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      calories: calories,
      protein: protein,
      carbs: carbs,
      fats: fats,
      recipeIngredients: ri,
    );
  }

  _Totals? get manualTotals {
    if (calories == null && protein == null && carbs == null && fats == null) {
      return null;
    }
    return _Totals(
      protein: protein ?? 0.0,
      carbs: carbs ?? 0.0,
      fats: fats ?? 0.0,
      calories: (calories ?? 0.0).round(),
    );
  }

  _Totals? get computedTotalsFromIngredients {
    if (recipeIngredients.isEmpty) return null;
    double p = 0, c = 0, f = 0;
    double cal = 0;
    for (final ri in recipeIngredients) {
      final ing = ri.ingredient;
      if (ing == null) continue;
      final factor = ri.amountGrams <= 0 ? 0.0 : (ri.amountGrams / 100.0);
      p += ing.proteinPer100g * factor;
      c += ing.carbsPer100g * factor;
      f += ing.fatPer100g * factor;
      cal += ing.caloriesPer100g * factor;
    }
    return _Totals(protein: p, carbs: c, fats: f, calories: cal.round());
  }
}

class _RecipeIngredient {
  final String ingredientId;
  final double amountGrams;
  final Ingredient? ingredient;

  const _RecipeIngredient({
    required this.ingredientId,
    required this.amountGrams,
    required this.ingredient,
  });

  factory _RecipeIngredient.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    final ing = json['ingredients'];
    return _RecipeIngredient(
      ingredientId: (json['ingredient_id'] ?? '').toString(),
      amountGrams: asDouble(json['amount_grams']),
      ingredient: ing is Map<String, dynamic> ? Ingredient.fromJson(ing) : null,
    );
  }
}

enum _FoodType { ingredient, recipe }

class _FoodPick {
  final String id;
  final String name;
  final _FoodType type;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;
  final double caloriesPer100g;
  final bool isGlutenFree;
  final int? glycemicIndex;
  final int allergenLevel;

  const _FoodPick({
    required this.id,
    required this.name,
    required this.type,
    this.proteinPer100g = 0,
    this.carbsPer100g = 0,
    this.fatPer100g = 0,
    this.caloriesPer100g = 0,
    this.isGlutenFree = false,
    this.glycemicIndex,
    this.allergenLevel = 1,
  });

  bool get showsDietBadges => type == _FoodType.ingredient;

  /// Macro line for ingredient rows; recipes use plain label.
  String listMacroSubtitle(AppLocalizations l10n) => type == _FoodType.recipe
      ? l10n.recipe
      : MacroDisplay.macroLine(
          proteinPer100g,
          carbsPer100g,
          fatPer100g,
          caloriesPer100g,
        );
}

class _Totals {
  final double protein;
  final double carbs;
  final double fats;
  final int calories;

  const _Totals({
    required this.protein,
    required this.carbs,
    required this.fats,
    required this.calories,
  });
}

class _OffProduct {
  final String barcode;
  final String name;
  final double caloriesPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;

  const _OffProduct({
    required this.barcode,
    required this.name,
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
  });
}

class _OffAddIngredientDialog extends StatefulWidget {
  final _OffProduct product;

  const _OffAddIngredientDialog({required this.product});

  @override
  State<_OffAddIngredientDialog> createState() =>
      _OffAddIngredientDialogState();
}

class _OffAddIngredientDialogState extends State<_OffAddIngredientDialog> {
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _kcal;
  late final TextEditingController _p;
  late final TextEditingController _c;
  late final TextEditingController _f;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name = TextEditingController(text: p.name);
    _kcal = TextEditingController(
      text: p.caloriesPer100g == p.caloriesPer100g.roundToDouble()
          ? p.caloriesPer100g.toInt().toString()
          : p.caloriesPer100g.toStringAsFixed(1),
    );
    _p = TextEditingController(text: p.proteinPer100g.toStringAsFixed(1));
    _c = TextEditingController(text: p.carbsPer100g.toStringAsFixed(1));
    _f = TextEditingController(text: p.fatPer100g.toStringAsFixed(1));
  }

  @override
  void dispose() {
    _name.dispose();
    _kcal.dispose();
    _p.dispose();
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  double _d(String v) => double.tryParse(v.trim().replaceAll(',', '.')) ?? 0.0;

  Future<void> _save() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    if (_saving) return;
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.msgSignInSave)));
      return;
    }

    final displayName = _name.text.trim();
    if (!mounted) return;
    final add = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        const bg = Color(0xFF050510);
        const cyan = Color(0xFF00F3FF);
        const gold = AppColors.cyberGold;
        return AlertDialog(
          backgroundColor: bg,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: Text(
            'ADD TO LIBRARY?',
            style: TextStyle(color: gold, fontFamily: 'monospace'),
          ),
          content: Text(
            'Item Found: $displayName\n\nAdd this ingredient to your library?',
            style: const TextStyle(
              color: cyan,
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.35,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text(
                'CANCEL',
                style: TextStyle(
                  color: Color(0xFF88CCFF),
                  fontFamily: 'monospace',
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(
                'ADD',
                style: TextStyle(
                  color: gold,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );
    if (add != true) return;

    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'name': _name.text.trim(),
        'calories_per_100g': _d(_kcal.text),
        'protein_per_100g': _d(_p.text),
        'carbs_per_100g': _d(_c.text),
        'fat_per_100g': _d(_f.text),
        'is_gluten_free': false,
        'glycemic_index': null,
        'allergen_level': 1,
        'user_id': uid,
      };

      final inserted = await _client
          .from('ingredients')
          .insert(payload)
          .select(
            'id,name,calories_per_100g,protein_per_100g,carbs_per_100g,fat_per_100g',
          );
      final rows = (inserted as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) {
        throw Exception('Insert returned no rows');
      }
      final r = rows.first;
      final id = (r['id'] ?? '').toString().trim();
      final name = (r['name'] ?? '').toString().trim();
      if (id.isEmpty || name.isEmpty) {
        throw Exception('Insert failed');
      }

      double asDouble(dynamic v) {
        if (v == null) return 0.0;
        if (v is num) return v.toDouble();
        return double.tryParse(v.toString()) ?? 0.0;
      }

      if (!mounted) return;
      Navigator.of(context).pop(
        _FoodPick(
          id: id,
          name: name,
          type: _FoodType.ingredient,
          caloriesPer100g: asDouble(r['calories_per_100g']),
          proteinPer100g: asDouble(r['protein_per_100g']),
          carbsPer100g: asDouble(r['carbs_per_100g']),
          fatPer100g: asDouble(r['fat_per_100g']),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(supabaseWriteErrorMessage(e)),
          backgroundColor: Colors.redAccent,
          showCloseIcon: true,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _dec(String label, Color accent) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: accent, fontFamily: 'monospace'),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: accent, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    const gold = AppColors.cyberGold;
    final accent = gold;

    return AlertDialog(
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      title: Text(
        'ADD FOOD (BARCODE)',
        style: TextStyle(color: accent, fontFamily: 'monospace'),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Barcode: ${widget.product.barcode}',
                style: const TextStyle(
                  color: Color(0x8800F3FF),
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _name,
                style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                decoration: _dec('Product name', accent),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              Text(
                'Per 100g',
                style: TextStyle(
                  color: cyan.withValues(alpha: 0.9),
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _kcal,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                decoration: _dec('Energy (kcal)', accent),
                validator: (v) =>
                    double.tryParse((v ?? '').trim().replaceAll(',', '.')) ==
                        null
                    ? 'Number'
                    : null,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _p,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: const TextStyle(
                        color: cyan,
                        fontFamily: 'monospace',
                      ),
                      decoration: _dec('Protein (g)', accent),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _c,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: const TextStyle(
                        color: cyan,
                        fontFamily: 'monospace',
                      ),
                      decoration: _dec('Carbs (g)', accent),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _f,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                decoration: _dec('Fats (g)', accent),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(null),
          child: Text(context.l10n.cancel.toUpperCase()),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: Text(context.l10n.save.toUpperCase()),
        ),
      ],
    );
  }
}

enum _EditReminderMode { none, specific, minutesBefore }

class _EditReminderSection extends StatelessWidget {
  final _EditReminderMode mode;
  final ValueChanged<_EditReminderMode> onModeChanged;
  final TimeOfDay? specificTime;
  final VoidCallback onPickSpecific;
  final TextEditingController minutesBeforeController;
  final ValueChanged<int> onMinutesChanged;

  const _EditReminderSection({
    required this.mode,
    required this.onModeChanged,
    required this.specificTime,
    required this.onPickSpecific,
    required this.minutesBeforeController,
    required this.onMinutesChanged,
  });

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF00F3FF);
    final loc = context.l10n;
    const quickOffsets = [5, 15, 30, 60];
    final specificLabel = specificTime == null
        ? loc.pickTime
        : '${specificTime!.hour.toString().padLeft(2, '0')}:${specificTime!.minute.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          loc.reminder,
          style: const TextStyle(
            color: Color(0x8800F3FF),
            fontFamily: 'monospace',
            fontSize: 11,
            letterSpacing: 1.0,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        SegmentedButton<_EditReminderMode>(
          segments: [
            ButtonSegment(value: _EditReminderMode.none, label: Text(loc.none)),
            ButtonSegment(
              value: _EditReminderMode.specific,
              label: Text(loc.specific),
            ),
            ButtonSegment(
              value: _EditReminderMode.minutesBefore,
              label: Text(loc.minutesBefore),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (s) {
            if (s.isEmpty) return;
            onModeChanged(s.first);
          },
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.all(cyan),
            textStyle: WidgetStateProperty.all(
              const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
            side: WidgetStateProperty.all(
              const BorderSide(color: cyan, width: 1),
            ),
            shape: WidgetStateProperty.all(
              const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
          ),
          showSelectedIcon: false,
        ),
        const SizedBox(height: 10),
        if (mode == _EditReminderMode.specific)
          Row(
            children: [
              Expanded(
                child: Text(
                  loc.specificTime,
                  style: const TextStyle(
                    color: cyan,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: onPickSpecific,
                style: OutlinedButton.styleFrom(
                  foregroundColor: cyan,
                  side: const BorderSide(color: cyan, width: 1),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                child: Text(
                  specificLabel,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ],
          ),
        if (mode == _EditReminderMode.minutesBefore) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  loc.minutes,
                  style: const TextStyle(
                    color: cyan,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: minutesBeforeController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.left,
                  style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                  onChanged: (v) {
                    final t = v.trim();
                    if (t.isEmpty) {
                      // Prevent crashes: treat empty as 0 (caller can decide fallback).
                      onMinutesChanged(0);
                      return;
                    }
                    final mins = int.tryParse(t);
                    if (mins != null) onMinutesChanged(mins);
                  },
                  decoration: const InputDecoration(
                    hintText: '30',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final m in quickOffsets)
                ActionChip(
                  label: Text(
                    '$m',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: cyan,
                      fontSize: 11,
                    ),
                  ),
                  backgroundColor: const Color(0xFF050510),
                  side: const BorderSide(color: cyan, width: 1),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                  onPressed: () {
                    minutesBeforeController.text = '$m';
                    onMinutesChanged(m);
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One bar: full width = daily target; solid = consumed; dashed/ghost = planned slice;
/// gold strip at trailing edge = goal marker.
class _UnifiedMacroBarPainter extends CustomPainter {
  final double consumed;
  final double prognostic;
  final double target;

  _UnifiedMacroBarPainter({
    required this.consumed,
    required this.prognostic,
    required this.target,
  });

  static void _dottedHorizontal(
    Canvas canvas,
    double x0,
    double x1,
    double y,
    Paint paint,
  ) {
    final step = (paint.strokeWidth <= 1.0) ? 5.0 : 6.0;
    final r = math.max(0.9, paint.strokeWidth * 0.9);
    for (var x = x0; x <= x1; x += step) {
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  static void _dottedVertical(
    Canvas canvas,
    double x,
    double y0,
    double y1,
    Paint paint,
  ) {
    final step = (paint.strokeWidth <= 1.0) ? 4.5 : 5.5;
    final r = math.max(0.9, paint.strokeWidth * 0.9);
    for (var y = y0; y <= y1; y += step) {
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final t = target > 0 ? target : 1.0;
    var consPx = (consumed / t) * w;
    var progPx = (prognostic / t) * w;
    if (!consPx.isFinite) consPx = 0;
    if (!progPx.isFinite) progPx = 0;
    consPx = consPx.clamp(0.0, w);
    progPx = progPx.clamp(0.0, w);
    if (progPx < consPx) progPx = consPx;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0x2200F3FF),
    );

    final extW = progPx - consPx;
    if (extW > 0) {
      canvas.drawRect(
        Rect.fromLTWH(consPx, 0, extW, h),
        Paint()..color = const Color(0x1588CCFF),
      );
      final edge = Paint()
        ..color = const Color(0xAA88CCFF)
        ..strokeWidth = 1.1
        ..style = PaintingStyle.fill;
      _dottedHorizontal(canvas, consPx, progPx, 0.9, edge);
      _dottedHorizontal(canvas, consPx, progPx, h - 0.9, edge);
      _dottedVertical(canvas, progPx.clamp(1.0, w - 1), 0.8, h - 0.8, edge);
    }

    if (consPx > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, consPx, h),
        Paint()..color = const Color(0xFF00F3FF),
      );
    }

    canvas.drawRect(
      Rect.fromLTWH(w - 2, 0, 2, h),
      Paint()..color = AppColors.cyberGold,
    );
  }

  @override
  bool shouldRepaint(covariant _UnifiedMacroBarPainter oldDelegate) {
    return oldDelegate.consumed != consumed ||
        oldDelegate.prognostic != prognostic ||
        oldDelegate.target != target;
  }
}

class _DualMacroBar extends StatelessWidget {
  final String label;
  final double consumed;
  final double prognostic;
  final double target;
  final String unit;
  final int decimals;

  const _DualMacroBar({
    required this.label,
    required this.consumed,
    required this.prognostic,
    required this.target,
    required this.unit,
    required this.decimals,
  });

  String _fmt(double v) {
    if (decimals <= 0) return v.round().toString();
    return v.toStringAsFixed(decimals);
  }

  String _shortLabel(String raw) {
    final t = raw.trim().toLowerCase();
    if (t.startsWith('protein')) return 'PRO';
    if (t.contains('carb') || t.contains('въг')) return 'CHO';
    if (t.contains('fat') || t.contains('маз')) return 'FAT';
    if (t.contains('cal')) return 'KCAL';
    return raw.length > 6
        ? raw.substring(0, 6).toUpperCase()
        : raw.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = target > 0 ? target : 1.0;
    final u = unit.isEmpty ? '' : unit;
    final plannedPending = math.max(0.0, prognostic - consumed);
    final short = _shortLabel(label);
    final overlayText =
        '$short: C: ${_fmt(consumed)}$u / T: ${_fmt(target)}$u (P: ${_fmt(plannedPending)}$u)';

    return LayoutBuilder(
      builder: (context, c) {
        final fw = c.maxWidth;
        if (fw <= 0) return const SizedBox(height: 18);
        return SizedBox(
          height: 18,
          width: fw,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              CustomPaint(
                size: Size(fw, 18),
                painter: _UnifiedMacroBarPainter(
                  consumed: consumed,
                  prognostic: prognostic,
                  target: t,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  overlayText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.cyberGold,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 0.2,
                    shadows: [
                      Shadow(
                        color: Color(0xCC000000),
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Collapsible UI for a single food log row.
///
/// Collapsed: name + calories.
/// Expanded: macros row + [TAKE] [EDIT] [DELETE] actions.
