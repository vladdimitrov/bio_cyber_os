import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bio_cyber_os/l10n/app_localizations.dart';
import 'package:bio_cyber_os/l10n/context_l10n.dart';
import 'package:bio_cyber_os/l10n/meal_labels.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/supabase_error_message.dart';
import '../../../core/supabase_log_date.dart';
import '../../../core/widgets/library_search_sheet.dart';
import '../../../core/widgets/reminder_section.dart';
import '../../../core/widgets/schedule_selector.dart';
import '../../../core/settings/measurement_settings.dart';
import '../../../core/settings/unit_options.dart';
import '../../../core/theme/app_colors.dart';

class SupplementsScreen extends StatefulWidget {
  final String? focusLogId;
  final DateTime? focusDate;
  final bool embedded;

  const SupplementsScreen({
    super.key,
    this.focusLogId,
    this.focusDate,
    this.embedded = false,
  });

  @override
  State<SupplementsScreen> createState() => _SupplementsScreenState();
}

class _SupplementsScreenState extends State<SupplementsScreen>
    with WidgetsBindingObserver {
  final _client = Supabase.instance.client;

  static const _dailyLogsTable = 'daily_logs';
  static const _mealTypeSupplement = 'SUPPLEMENT';

  DateTime selectedDate = DateTime.now();
  bool _loading = true;
  String? _workingSupplementId;
  String? _workingLogId;

  /// Library items for the + picker.
  List<Map<String, dynamic>> librarySupplements = [];

  /// `daily_logs` rows with `supplement_id` set for the selected day.
  List<Map<String, dynamic>> dailyLogs = [];

  String? _highlightLogId;
  final Map<String, GlobalKey> _rowKeys = {};

  Timer? _refreshTimer;

  static const _blocks = <String>['MORNING', 'AFTERNOON', 'EVENING', 'NIGHT'];

  String _canonicalBlock(dynamic raw) {
    final s = (raw ?? '').toString().trim().toUpperCase();
    if (s.isEmpty) return 'MORNING';
    if (_blocks.contains(s)) return s;
    // tolerate inputs like "Morning"
    final normalized = s.replaceAll(RegExp(r'\s+'), '');
    for (final b in _blocks) {
      if (b.replaceAll(' ', '') == normalized) return b;
    }
    return 'MORNING';
  }

  Map<String, List<Map<String, dynamic>>> _groupedByBlock() {
    final map = <String, List<Map<String, dynamic>>>{
      for (final b in _blocks) b: <Map<String, dynamic>>[],
    };
    for (final row in dailyLogs) {
      final b = _canonicalBlock(row['schedule_block']);
      map[b]!.add(row);
    }
    return map;
  }

  static const _allowedUnits = <String>[
    'g',
    'mg',
    'ml',
    'drops',
    'capsules',
    'pcs',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (t) {
      if (mounted) setState(() {});
    });
    _fetchData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SupplementsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusDate != null &&
        widget.focusDate != oldWidget.focusDate &&
        mounted) {
      final d = widget.focusDate!;
      selectedDate = DateTime(d.year, d.month, d.day);
      _fetchData().then((_) {
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

  String _dayLabel(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }

  String _sanitizeUnit(String raw) {
    var u = raw.trim();
    if (u == 'гр' || u == 'гр.') u = 'g';
    if (u == 'мл') u = 'ml';
    if (u == 'капки') u = 'drops';
    if (u == 'капсули' || u == 'табл') u = 'capsules';
    if (!_allowedUnits.contains(u)) u = 'g';
    return u;
  }

  String _displayUnit(dynamic raw) => _sanitizeUnit((raw ?? '').toString());

  String _hhmmFromIso(dynamic createdAt) {
    try {
      final dt = DateTime.parse(createdAt.toString()).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '--:--';
    }
  }

  double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  /// Timestamp stored on new `daily_logs` rows (now if viewing today, else noon local on selected day).
  bool _isViewingToday() {
    final now = DateTime.now();
    final s = selectedDate;
    return now.year == s.year && now.month == s.month && now.day == s.day;
  }

  DateTime _consumedAtLocalForNewLog() {
    final s = selectedDate;
    if (_isViewingToday()) return DateTime.now();
    return DateTime(s.year, s.month, s.day, 12, 0);
  }

  String _emptyLogsMessage(AppLocalizations l10n) => _isViewingToday()
      ? l10n.supsEmptyToday
      : l10n.supsEmptyForDay(_dayLabel(selectedDate));

  Future<void> _fetchData() async {
    setState(() => _loading = true);

    List<Map<String, dynamic>> nextLogs = dailyLogs;
    List<Map<String, dynamic>> nextLib = librarySupplements;
    Object? logsError;
    Object? libError;

    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        nextLogs = [];
      } else {
        final dayStr = supabaseDateOnly(selectedDate);
        final logsData = await _client
            .from(_dailyLogsTable)
            .select('*, supplements(*)')
            .eq('user_id', uid)
            .gte('created_at', supabaseCreatedAtDayGte(dayStr))
            .lte('created_at', supabaseCreatedAtDayLte(dayStr))
            .order('scheduled_at', ascending: true);

        final raw = (logsData as List).cast<Map<String, dynamic>>();
        nextLogs = raw
            .where((row) {
              final sid = row['supplement_id'];
              return sid != null && sid.toString().trim().isNotEmpty;
            })
            .toList(growable: false);
      }
    } catch (e) {
      logsError = e;
      nextLogs = [];
    }

    try {
      final libData = await _client.from('supplements').select().order('name');
      nextLib = (libData as List).cast<Map<String, dynamic>>();
    } catch (e) {
      libError = e;
      // Keep any previously loaded library instead of falsely showing "empty".
    }

    if (!mounted) return;
    setState(() {
      dailyLogs = nextLogs;
      librarySupplements = nextLib;
      _loading = false;
    });

    if (logsError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.logsError('$logsError'))),
      );
    } else if (libError != null && nextLib.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.libraryError('$libError'))),
      );
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked == null) return;
    setState(() {
      selectedDate = DateTime(picked.year, picked.month, picked.day);
    });
    await _fetchData();
  }

  Future<void> _shiftDay(int deltaDays) async {
    setState(() {
      selectedDate = selectedDate.add(Duration(days: deltaDays));
    });
    await _fetchData();
  }

  Future<void> _insertDailyLogForSupplement(
    Map<String, dynamic> supplement, {
    required String scheduleBlock,
  }) async {
    final sid = (supplement['id'] ?? '').toString();
    if (sid.isEmpty) return;
    if (_workingSupplementId != null) return;

    final name = (supplement['name'] ?? '').toString();
    final libraryDosage = _asDouble(supplement['daily_dosage']);
    final libraryUnit = _displayUnit(supplement['unit_type']);

    final picked = await showDialog<_IntakePick?>(
      context: context,
      builder: (dialogCtx) => _LogIntakeDialog(
        title: dialogCtx.l10n.supsLogIntakeTitle,
        itemName: name.isEmpty ? dialogCtx.l10n.defaultSupplementName : name,
        amountPrefill: libraryDosage > 0 ? libraryDosage : null,
        unitPrefill: libraryUnit.isNotEmpty ? libraryUnit : 'pcs',
        showSaveAsDefault: libraryDosage <= 0,
        baseDate: _consumedAtLocalForNewLog(),
        initialScheduleBlock: _canonicalBlock(scheduleBlock),
      ),
    );
    if (picked == null) return;

    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.msgSignInLogSupps),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _workingSupplementId = sid);
    try {
      int? reminderOffsetMinutes;
      if (picked.reminder.enabled) {
        reminderOffsetMinutes =
            picked.reminder.mode == ReminderMode.atConsumptionTime
            ? 0
            : picked.reminder.offsetMinutes;
      }

      final logNow = picked.tab == LogIntakeTab.logNow;
      final targetDates = logNow
          ? <DateTime>[picked.targetDates.first]
          : picked.targetDates;

      final rows = <Map<String, dynamic>>[];
      final scheduledLocals = <DateTime>[];
      final reminderLocals = <DateTime?>[];
      for (final d in targetDates) {
        final scheduledI = DateTime(
          d.year,
          d.month,
          d.day,
          picked.intakeTime.hour,
          picked.intakeTime.minute,
        );
        DateTime? reminderI;
        if (reminderOffsetMinutes != null) {
          reminderI = reminderOffsetMinutes == 0
              ? scheduledI
              : scheduledI.subtract(Duration(minutes: reminderOffsetMinutes));
        }
        final payload = <String, dynamic>{
          'user_id': uid,
          'created_at': scheduledI.toUtc().toIso8601String(),
          'supplement_id': sid,
          'amount_grams': picked.amount,
          'meal_type': _mealTypeSupplement,
          'scheduled_at': scheduledI.toUtc().toIso8601String(),
          'is_taken': logNow,
          if (logNow) 'taken_at': scheduledI.toUtc().toIso8601String(),
          'unit': picked.unit,
          'schedule_block': _canonicalBlock(picked.scheduleBlock),
        };
        if (reminderI != null) {
          payload['reminder_at'] = reminderI.toUtc().toIso8601String();
          payload['reminder_offset_minutes'] = reminderOffsetMinutes;
        }
        rows.add(payload);
        scheduledLocals.add(scheduledI);
        reminderLocals.add(reminderI);
      }

      final inserted = await _client
          .from(_dailyLogsTable)
          .insert(rows)
          .select('id')
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;
      final l10n = context.l10n;
      final reminderTitle = l10n.notificationReminderSuppIntake(
        name.isEmpty ? l10n.defaultSupplementName : name,
      );
      final reminderBody = l10n.reminderBody;

      final insertedList = (inserted as List).cast<Map<String, dynamic>>();
      for (var i = 0; i < insertedList.length; i++) {
        final newId = (insertedList[i]['id'] ?? '').toString().trim();
        final rLocal = (i < reminderLocals.length) ? reminderLocals[i] : null;
        final schedLocal = (i < scheduledLocals.length)
            ? scheduledLocals[i]
            : null;
        if (rLocal != null && newId.isNotEmpty && schedLocal != null) {
          await NotificationService.scheduleByKey(
            key: 'daily_logs:$newId',
            title: reminderTitle,
            body: reminderBody,
            whenLocal: rLocal,
            payload: {
              'item_type': 'supplement',
              'item_id': newId,
              'target_date':
                  '${schedLocal.year.toString().padLeft(4, '0')}-${schedLocal.month.toString().padLeft(2, '0')}-${schedLocal.day.toString().padLeft(2, '0')}',
            },
          );
        }
      }

      if (picked.saveAsDefault == true) {
        await _client
            .from('supplements')
            .update({'daily_dosage': picked.amount, 'unit_type': picked.unit})
            .eq('id', sid);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.msgLogged),
          duration: const Duration(seconds: 2),
        ),
      );
      await _fetchData();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _workingSupplementId = null;
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(supabaseWriteErrorMessage(e)),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _workingSupplementId = null);
    }
  }

  Future<void> _undoDelete(Map<String, dynamic> log) async {
    final id = log['id'];
    if (id == null) return;
    if (_workingLogId != null) return;
    setState(() => _workingLogId = id.toString());
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
        return;
      }
      await _client
          .from(_dailyLogsTable)
          .delete()
          .eq('id', id)
          .eq('user_id', uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.msgLogDeleted),
          duration: const Duration(seconds: 2),
        ),
      );
      await _fetchData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(supabaseWriteErrorMessage(e)),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _workingLogId = null);
    }
  }

  bool _isTaken(Map<String, dynamic> log) {
    final v = log['is_taken'];
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = (v ?? '').toString().trim().toLowerCase();
    if (s == 'true' || s == 't' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == 'f' || s == '0' || s == 'no') return false;
    // Back-compat: older rows used `consumed_at` + `is_consumed`.
    final ca = (log['consumed_at'] ?? '').toString().trim();
    final ia = (log['is_consumed'] ?? '').toString().trim().toLowerCase();
    if (ca.isNotEmpty) return true;
    if (ia == 'true' || ia == 't' || ia == '1') return true;
    return false;
  }

  DateTime? _scheduledAtLocal(Map<String, dynamic> log) {
    final raw = log['scheduled_at'] ?? log['slot_iso'] ?? log['consumed_at'];
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    try {
      return DateTime.parse(s).toLocal();
    } catch (_) {
      return null;
    }
  }

  DateTime? _takenAtLocal(Map<String, dynamic> log) {
    final raw = log['taken_at'] ?? log['consumed_at'];
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    try {
      return DateTime.parse(s).toLocal();
    } catch (_) {
      return null;
    }
  }

  bool _isMissed(Map<String, dynamic> log) {
    if (_isTaken(log)) return false;
    final scheduled = _scheduledAtLocal(log);
    if (scheduled == null) return false;
    return scheduled.isBefore(DateTime.now());
  }

  Future<void> _takePlanned(Map<String, dynamic> log) async {
    final id = (log['id'] ?? '').toString().trim();
    if (id.isEmpty) return;
    if (_workingLogId != null) return;

    final nowIsoLocal = DateTime.now().toIso8601String();

    // 1) Optimistic UI update.
    setState(() {
      _workingLogId = id;
      dailyLogs = dailyLogs
          .map(
            (e) => (e['id'] ?? '').toString() == id
                ? {...e, 'is_taken': true, 'taken_at': nowIsoLocal}
                : e,
          )
          .toList(growable: false);
      _highlightLogId = id;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _ensureHighlightVisible(),
    );

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
        await _fetchData();
        return;
      }
      await _client
          .from(_dailyLogsTable)
          .update({
            'is_taken': true,
            'taken_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id)
          .eq('user_id', uid);

      await NotificationService.cancelByKey('daily_logs:$id');
      await _fetchData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(supabaseWriteErrorMessage(e)),
          backgroundColor: Colors.redAccent,
        ),
      );
      await _fetchData();
    } finally {
      if (mounted) setState(() => _workingLogId = null);
    }
  }

  Future<void> _editLog(Map<String, dynamic> log) async {
    final logId = (log['id'] ?? '').toString();
    if (logId.isEmpty) return;
    if (_workingLogId != null) return;
    final supplements = log['supplements'];
    final name = (supplements is Map<String, dynamic>)
        ? (supplements['name'] ?? '').toString()
        : '';
    final existingAmount = _asDouble(log['amount_grams']);
    final existingUnit = _displayUnit(
      (log['unit'] ??
              (supplements is Map<String, dynamic>
                  ? supplements['unit_type']
                  : ''))
          .toString(),
    );
    final consumedAtLocal =
        _takenAtLocal(log) ?? _scheduledAtLocal(log) ?? DateTime.now();
    DateTime? reminderAtLocal;
    try {
      final r = (log['reminder_at'] ?? '').toString();
      if (r.trim().isNotEmpty) reminderAtLocal = DateTime.parse(r).toLocal();
    } catch (_) {
      reminderAtLocal = null;
    }
    final existingOffset = () {
      final v = log['reminder_offset_minutes'];
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }();
    await showDialog<void>(
      context: context,
      builder: (_) => _EditSuppLogDialog(
        logId: logId,
        supplementName: name.isEmpty ? 'Supplement' : name,
        isTaken: _isTaken(log),
        existingAmount: existingAmount > 0 ? existingAmount : null,
        existingUnit: existingUnit.isNotEmpty ? existingUnit : 'pcs',
        existingNote: (log['notes'] ?? '').toString(),
        existingConsumedAtLocal: consumedAtLocal,
        existingReminderAtLocal: reminderAtLocal,
        existingReminderOffsetMinutes: existingOffset,
        onRefresh: () async {
          if (!mounted) return;
          await _fetchData();
        },
      ),
    );
  }

  Future<void> _pickSupplementFromLibrary({
    required String scheduleBlock,
  }) async {
    final loc = context.l10n;
    await LibrarySearchSheet.show(
      context,
      title: loc.logSupplementBlock(
        localizedTimeBlock(loc, _canonicalBlock(scheduleBlock)),
      ),
      table: 'supplements',
      emptyMessage: loc.noItemsFound,
      addNewLabel: loc.libraryAddNew,
      onAddNew: () async {
        final changed = await showDialog<bool>(
          context: context,
          builder: (_) => const _NewSupplementDialog(),
        );
        if (changed == true && mounted) await _fetchData();
      },
      getName: (row) => (row['name'] ?? '').toString(),
      getSubtitle: (row) {
        final dose = _asDouble(row['daily_dosage']);
        final unit = _displayUnit(row['unit_type']);
        return dose > 0
            ? loc.libraryDefaultDose('$dose', unit)
            : loc.libraryNoDefaultDose;
      },
      getIcon: (_) => Icons.medication_outlined,
      onPick: (row) =>
          _insertDailyLogForSupplement(row, scheduleBlock: scheduleBlock),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    const gold = AppColors.cyberGold;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: bg,
      appBar: widget.embedded
          ? null
          : AppBar(
              title: Text(
                l10n.screenSupps,
                style: const TextStyle(
                  color: AppColors.cyberGold,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
              foregroundColor: gold,
              actions: [
                IconButton(
                  tooltip: l10n.addSupplementToLibrary,
                  onPressed: () async {
                    final changed = await showDialog<bool>(
                      context: context,
                      builder: (_) => const _NewSupplementDialog(),
                    );
                    if (changed == true && mounted) await _fetchData();
                  },
                  icon: const Icon(Icons.playlist_add),
                ),
                IconButton(
                  onPressed: _fetchData,
                  tooltip: l10n.refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
      body: SingleChildScrollView(
        child: Column(
          children: [
          // TOP: Date Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: cyan, width: 2)),
            ),
            child: DefaultTextStyle(
              style: const TextStyle(
                color: AppColors.cyberGold,
                fontFamily: 'monospace',
                letterSpacing: 0.6,
                fontSize: 13,
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => _shiftDay(-1),
                    icon: const Icon(Icons.chevron_left),
                    color: gold,
                    tooltip: l10n.prevDay,
                  ),
                  Expanded(
                    child: Center(
                      child: TextButton(
                        onPressed: _pickDate,
                        style: TextButton.styleFrom(
                          foregroundColor: gold,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                        ),
                        child: Text(
                          _dayLabel(selectedDate),
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
                    color: gold,
                    tooltip: 'Next day',
                  ),
                ],
              ),
            ),
          ),

          _loading
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      if (dailyLogs.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 14),
                          child: Text(
                            _emptyLogsMessage(l10n),
                            textAlign: TextAlign.left,
                            style: const TextStyle(
                              color: AppColors.cyberGoldMuted,
                              fontFamily: 'monospace',
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ),
                      for (final block in _blocks)
                        _BlockSection(
                          title: localizedTimeBlock(l10n, block),
                          addLabel: l10n.supsAddBlockSupp(
                            localizedTimeBlock(l10n, block),
                          ),
                          entries: _groupedByBlock()[block]!,
                          onAdd: () =>
                              _pickSupplementFromLibrary(scheduleBlock: block),
                          buildRow: (log) {
                            final supplements = log['supplements'];
                            final joinedName =
                                (supplements is Map<String, dynamic>)
                                ? (supplements['name'] ?? '').toString()
                                : '';
                            final name = joinedName.isNotEmpty
                                ? joinedName
                                : l10n.unknown;
                            final amount = _asDouble(log['amount_grams']);
                            final unit = _displayUnit(
                              (log['unit'] ??
                                      (supplements is Map<String, dynamic>
                                          ? supplements['unit_type']
                                          : ''))
                                  .toString(),
                            );
                            final isTaken = _isTaken(log);
                            final time = _hhmmFromIso(
                              isTaken
                                  ? (log['taken_at'] ?? log['consumed_at'])
                                  : (log['scheduled_at'] ?? log['consumed_at']),
                            );
                            final isMissed = _isMissed(log);
                            final line =
                                '$time — $name (${amount.toString()} $unit)'
                                    .trim();
                            final note = (log['notes'] ?? '').toString().trim();
                            final id = (log['id'] ?? '').toString();
                            final rowKey = _rowKeys.putIfAbsent(
                              id,
                              () => GlobalKey(),
                            );
                            final highlight =
                                (_highlightLogId ?? '').trim() == id.trim();

                            return Container(
                              key: rowKey,
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: highlight
                                      ? const Color(0xFFFF3B30)
                                      : (isTaken
                                            ? const Color(0x2200F3FF)
                                            : const Color(0x6600F3FF)),
                                  width: highlight ? 2 : 1,
                                ),
                              ),
                              child: Opacity(
                                opacity: isTaken ? 1.0 : 0.72,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      isTaken
                                          ? Icons.check_circle
                                          : Icons.radio_button_unchecked,
                                      color: isMissed ? Colors.red : gold,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  line,
                                                  style: const TextStyle(
                                                    color: AppColors.cyberGold,
                                                    fontFamily: 'monospace',
                                                    letterSpacing: 0.6,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                              if (isMissed) ...[
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
                                          if (note.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              note,
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontFamily: 'monospace',
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                          if (!isTaken) ...[
                                            const SizedBox(height: 8),
                                            OutlinedButton(
                                              onPressed: (_workingLogId == id)
                                                  ? null
                                                  : () => _takePlanned(log),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: gold,
                                                side: const BorderSide(
                                                  color: cyan,
                                                  width: 1,
                                                ),
                                                shape:
                                                    const RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.zero,
                                                    ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 8,
                                                    ),
                                                minimumSize: Size.zero,
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ),
                                              child: Text(
                                                l10n.take,
                                                style: const TextStyle(
                                                  fontFamily: 'monospace',
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 1.0,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    IconButton(
                                      tooltip: l10n.editLog,
                                      onPressed: (_workingLogId == id)
                                          ? null
                                          : () => _editLog(log),
                                      icon: Icon(Icons.edit, color: gold),
                                      constraints: const BoxConstraints(
                                        minWidth: 36,
                                        minHeight: 36,
                                      ),
                                      padding: EdgeInsets.zero,
                                    ),
                                    IconButton(
                                      tooltip: l10n.deleteLog,
                                      onPressed: (_workingLogId == id)
                                          ? null
                                          : () => _undoDelete(log),
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                      ),
                                      constraints: const BoxConstraints(
                                        minWidth: 36,
                                        minHeight: 36,
                                      ),
                                      padding: EdgeInsets.zero,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _BlockSection extends StatelessWidget {
  final String title;
  final String addLabel;
  final List<Map<String, dynamic>> entries;
  final VoidCallback onAdd;
  final Widget Function(Map<String, dynamic> log) buildRow;

  const _BlockSection({
    required this.title,
    required this.addLabel,
    required this.entries,
    required this.onAdd,
    required this.buildRow,
  });

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: cyan, width: 1),
        boxShadow: const [BoxShadow(color: Color(0x2200F3FF), blurRadius: 8)],
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: AppColors.cyberGold,
          fontFamily: 'monospace',
          letterSpacing: 0.4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onAdd,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.cyberGold.withValues(
                      alpha: 0.88,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add, size: 14),
                      const SizedBox(width: 2),
                      Text(addLabel, style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (entries.isEmpty)
              const Text('—', style: TextStyle(color: AppColors.cyberGoldMuted))
            else
              for (final e in entries) buildRow(e),
          ],
        ),
      ),
    );
  }
}

class _IntakePick {
  final double amount;
  final String unit;
  final TimeOfDay intakeTime;
  final ReminderState reminder;
  final bool? saveAsDefault;
  final LogIntakeTab tab;
  final String scheduleBlock;

  /// Resolved list of date-only (local) dates; one row will be inserted per
  /// entry. Always non-empty (defaults to the base date).
  final List<DateTime> targetDates;

  const _IntakePick({
    required this.amount,
    required this.unit,
    required this.intakeTime,
    required this.reminder,
    required this.saveAsDefault,
    required this.tab,
    required this.scheduleBlock,
    required this.targetDates,
  });
}

enum LogIntakeTab { logNow, plan }

class _LogIntakeDialog extends StatefulWidget {
  final String title;
  final String itemName;
  final double? amountPrefill;
  final String unitPrefill;
  final bool showSaveAsDefault;
  final DateTime baseDate;
  final String initialScheduleBlock;

  const _LogIntakeDialog({
    required this.title,
    required this.itemName,
    required this.amountPrefill,
    required this.unitPrefill,
    required this.showSaveAsDefault,
    required this.baseDate,
    required this.initialScheduleBlock,
  });

  @override
  State<_LogIntakeDialog> createState() => _LogIntakeDialogState();
}

class _LogIntakeDialogState extends State<_LogIntakeDialog> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _timeController;
  late List<String> _units;
  late String _unit;

  LogIntakeTab _selectedTab = LogIntakeTab.logNow;
  late String _selectedBlock;

  ReminderState _reminder = const ReminderState.disabled();
  bool _saveDefault = false;
  ScheduleSelection _schedule = const ScheduleSelection();

  static const _dialogBlocks = <String>[
    'MORNING',
    'AFTERNOON',
    'EVENING',
    'NIGHT',
  ];

  static String _fmtNowHhmm() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  static String _fmtHhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static TimeOfDay _parseHhmm(String hhmm) {
    final parts = hhmm.trim().split(':');
    if (parts.length != 2) return const TimeOfDay(hour: 8, minute: 0);
    final h = int.tryParse(parts[0]) ?? 8;
    final m = int.tryParse(parts[1]) ?? 0;
    return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
  }

  @override
  void initState() {
    super.initState();
    _selectedBlock = widget.initialScheduleBlock;
    _timeController = TextEditingController(
      text: _fmtNowHhmm(),
    );

    final sys = MeasurementSettings.system.value;
    _units = UnitOptions.forContext(UnitContext.supplement, sys);
    final pre = widget.amountPrefill;
    _amountCtrl = TextEditingController(
      text: pre != null && pre > 0
          ? (pre == pre.roundToDouble()
                ? pre.toInt().toString()
                : pre.toString())
          : '',
    );
    final pref = widget.unitPrefill.trim();
    final def = UnitOptions.defaultUnit(UnitContext.supplement, sys);
    _unit = _units.contains(pref) ? pref : def;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _timeController.dispose();
    super.dispose();
  }

  double? _parseAmount() {
    final raw = _amountCtrl.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  Future<void> _pickIntakeTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _parseHhmm(_timeController.text),
    );
    if (picked == null) return;
    if (!mounted) return;
    setState(() => _timeController.text = _fmtHhmm(picked));
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    final loc = context.l10n;

    final intakeLabel = loc.intakeTimeAt(_timeController.text);

    return AlertDialog(
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      title: Text(
        widget.title,
        style: const TextStyle(color: cyan, fontFamily: 'monospace'),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.itemName,
                style: const TextStyle(
                  color: cyan,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 14),
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
                  setState(() {
                    _selectedTab = newSelection.first;
                  });
                },
                style: ButtonStyle(
                  foregroundColor: WidgetStateProperty.all(cyan),
                  textStyle: WidgetStateProperty.all(
                    const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                  side: WidgetStateProperty.all(
                    const BorderSide(color: cyan, width: 1),
                  ),
                  shape: WidgetStateProperty.all(
                    const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                ),
                showSelectedIcon: false,
              ),
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
                      items: _dialogBlocks
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
                onTap: _pickIntakeTime,
                style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  labelText: intakeLabel,
                  labelStyle: const TextStyle(
                    color: cyan,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    fontSize: 11,
                  ),
                  enabledBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: cyan, width: 1),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: cyan, width: 1.5),
                  ),
                  suffixIcon: const Icon(Icons.schedule, color: cyan),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amountCtrl,
                autofocus:
                    widget.amountPrefill == null || widget.amountPrefill! <= 0,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  labelText: loc.amountTaken,
                  labelStyle: const TextStyle(
                    color: cyan,
                    fontFamily: 'monospace',
                  ),
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
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _unit,
                dropdownColor: bg,
                decoration: InputDecoration(
                  labelText: loc.unit,
                  labelStyle: const TextStyle(
                    color: cyan,
                    fontFamily: 'monospace',
                  ),
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
              const SizedBox(height: 12),
              ReminderSection(
                state: _reminder,
                onChanged: (s) => setState(() => _reminder = s),
              ),
              Column(
                children: [
                  if (_selectedTab == LogIntakeTab.plan) ...[
                    ScheduleSelector(
                      selection: _schedule,
                      onChanged: (s) => setState(() => _schedule = s),
                      baseDate: widget.baseDate,
                    ),
                  ] else
                    const SizedBox.shrink(),
                ],
              ),
              if (widget.showSaveAsDefault) ...[
                const SizedBox(height: 10),
                CheckboxListTile(
                  value: _saveDefault,
                  onChanged: (v) => setState(() => _saveDefault = v == true),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    loc.saveAsDefaultDoseLibrary,
                    style: const TextStyle(
                      color: Color(0xAA00F3FF),
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop<_IntakePick?>(null),
          child: Text(loc.cancel),
        ),
        TextButton(
          onPressed: () {
            final amt = _parseAmount();
            if (amt == null || amt <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(loc.msgValidAmount)),
              );
              return;
            }
            final intakeTime = _parseHhmm(_timeController.text);
            final base = DateTime(
              widget.baseDate.year,
              widget.baseDate.month,
              widget.baseDate.day,
            );
            final targetDates = _selectedTab == LogIntakeTab.plan
                ? _schedule.resolveDates(widget.baseDate)
                : <DateTime>[base];
            Navigator.of(context).pop(
              _IntakePick(
                amount: amt,
                unit: _unit,
                intakeTime: intakeTime,
                reminder: _reminder,
                saveAsDefault: widget.showSaveAsDefault ? _saveDefault : null,
                tab: _selectedTab,
                scheduleBlock: _selectedBlock,
                targetDates: targetDates,
              ),
            );
          },
          child: Text(loc.logVerb),
        ),
      ],
    );
  }
}

class _EditSuppLogDialog extends StatefulWidget {
  final String logId;
  final String supplementName;
  final bool isTaken;
  final double? existingAmount;
  final String existingUnit;
  final String existingNote;
  final DateTime existingConsumedAtLocal;
  final DateTime? existingReminderAtLocal;
  final int? existingReminderOffsetMinutes;
  final Future<void> Function() onRefresh;

  const _EditSuppLogDialog({
    required this.logId,
    required this.supplementName,
    required this.isTaken,
    required this.existingAmount,
    required this.existingUnit,
    required this.existingNote,
    required this.existingConsumedAtLocal,
    required this.existingReminderAtLocal,
    required this.existingReminderOffsetMinutes,
    required this.onRefresh,
  });

  @override
  State<_EditSuppLogDialog> createState() => _EditSuppLogDialogState();
}

class _EditSuppLogDialogState extends State<_EditSuppLogDialog> {
  final _client = Supabase.instance.client;
  late final TextEditingController _amountController;
  final _noteController = TextEditingController();
  late String _unit;
  late DateTime _consumedAtLocal;
  _ReminderMode _reminderMode = _ReminderMode.none;
  TimeOfDay? _specificReminder;
  final _minutesBeforeCtrl = TextEditingController(text: '30');
  int _minutesBefore = 30;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = widget.existingAmount;
    _amountController = TextEditingController(
      text: a == null
          ? ''
          : (a == a.roundToDouble() ? a.toInt().toString() : a.toString()),
    );
    _noteController.text = widget.existingNote;
    _unit = widget.existingUnit;
    _consumedAtLocal = widget.existingConsumedAtLocal;

    final existingOffset = widget.existingReminderOffsetMinutes;
    if (existingOffset != null && existingOffset > 0) {
      _reminderMode = _ReminderMode.minutesBefore;
      _minutesBefore = existingOffset;
      _minutesBeforeCtrl.text = existingOffset.toString();
    } else if (widget.existingReminderAtLocal != null) {
      _reminderMode = _ReminderMode.specific;
      _specificReminder = TimeOfDay.fromDateTime(
        widget.existingReminderAtLocal!,
      );
    } else {
      _reminderMode = _ReminderMode.none;
      _minutesBefore = 30;
      _minutesBeforeCtrl.text = '30';
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _minutesBeforeCtrl.dispose();
    super.dispose();
  }

  double? _parseAmount() {
    final raw = _amountController.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  DateTime? _computeReminderAtLocalOrNull() {
    switch (_reminderMode) {
      case _ReminderMode.none:
        return null;
      case _ReminderMode.specific:
        final t = _specificReminder;
        if (t == null) return null;
        return DateTime(
          _consumedAtLocal.year,
          _consumedAtLocal.month,
          _consumedAtLocal.day,
          t.hour,
          t.minute,
        );
      case _ReminderMode.minutesBefore:
        final mins = _minutesBefore;
        if (mins <= 0) return null;
        return _consumedAtLocal.subtract(Duration(minutes: mins));
    }
  }

  String? _computeReminderAtUtcIsoOrNull() {
    final local = _computeReminderAtLocalOrNull();
    if (local == null) return null;
    return local.toUtc().toIso8601String();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final amt = _parseAmount();
      if (amt == null || amt <= 0) {
        messenger.showSnackBar(
          SnackBar(content: Text(context.l10n.msgValidAmount)),
        );
        return;
      }
      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(context.l10n.msgSignInSave),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
      final loc = context.l10n;
      final reminderTitle = loc.notificationReminderSuppIntake(
        widget.supplementName,
      );
      final reminderDefaultBody = loc.reminderBody;
      final logUpdatedMsg = loc.msgLogUpdated;
      await _client
          .from('daily_logs')
          .update({
            'user_id': uid,
            'amount_grams': amt,
            'unit': _unit,
            'notes': _noteController.text,
            'created_at': _consumedAtLocal.toUtc().toIso8601String(),
            'scheduled_at': _consumedAtLocal.toUtc().toIso8601String(),
            if (widget.isTaken)
              'taken_at': _consumedAtLocal.toUtc().toIso8601String(),
            'reminder_at': _computeReminderAtUtcIsoOrNull(),
            'reminder_offset_minutes':
                _reminderMode == _ReminderMode.minutesBefore
                ? _minutesBefore
                : (_reminderMode == _ReminderMode.none ? null : 0),
          })
          .eq('id', widget.logId)
          .eq('user_id', uid);

      await NotificationService.cancelByKey('daily_logs:${widget.logId}');
      final reminderLocal = _computeReminderAtLocalOrNull();
      if (reminderLocal != null) {
        await NotificationService.scheduleByKey(
          key: 'daily_logs:${widget.logId}',
          title: reminderTitle,
          body: _noteController.text.trim().isEmpty
              ? reminderDefaultBody
              : _noteController.text.trim(),
          whenLocal: reminderLocal,
          payload: {
            'item_type': 'supplement',
            'item_id': widget.logId,
            'target_date':
                '${_consumedAtLocal.year.toString().padLeft(4, '0')}-${_consumedAtLocal.month.toString().padLeft(2, '0')}-${_consumedAtLocal.day.toString().padLeft(2, '0')}',
          },
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
      widget.onRefresh().then((_) {
        messenger.showSnackBar(SnackBar(content: Text(logUpdatedMsg)));
      });
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(supabaseWriteErrorMessage(e)),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    final loc = context.l10n;
    return AlertDialog(
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      title: Text(
        loc.supsEditLogTitle,
        style: const TextStyle(color: cyan, fontFamily: 'monospace'),
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.supplementName,
              style: const TextStyle(
                color: cyan,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(_consumedAtLocal),
                );
                if (picked == null) return;
                if (!mounted) return;
                setState(() {
                  _consumedAtLocal = DateTime(
                    _consumedAtLocal.year,
                    _consumedAtLocal.month,
                    _consumedAtLocal.day,
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
                loc.fuelConsumptionTimeAt(
                  '${_consumedAtLocal.hour.toString().padLeft(2, '0')}:${_consumedAtLocal.minute.toString().padLeft(2, '0')}',
                ),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(
                      color: cyan,
                      fontFamily: 'monospace',
                    ),
                    decoration: InputDecoration(
                      labelText: loc.amountLabelShort,
                      labelStyle: const TextStyle(
                        color: cyan,
                        fontFamily: 'monospace',
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: cyan, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: cyan, width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 140,
                  child: DropdownButtonFormField<String>(
                    initialValue: _unit,
                    dropdownColor: bg,
                    decoration: InputDecoration(
                      labelText: loc.unit,
                      labelStyle: const TextStyle(
                        color: cyan,
                        fontFamily: 'monospace',
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: cyan, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: cyan, width: 1.5),
                      ),
                    ),
                    items: const ['g', 'mg', 'ml', 'drops', 'capsules', 'pcs']
                        .map(
                          (u) => DropdownMenuItem(
                            value: u,
                            child: Text(
                              u,
                              style: TextStyle(
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
            const SizedBox(height: 10),
            _ReminderSection(
              mode: _reminderMode,
              onModeChanged: (m) => setState(() => _reminderMode = m),
              specificTime: _specificReminder,
              onPickSpecific: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _specificReminder ?? TimeOfDay.now(),
                );
                if (picked == null) return;
                if (!mounted) return;
                setState(() => _specificReminder = picked);
              },
              minutesBeforeController: _minutesBeforeCtrl,
              onMinutesChanged: (mins) => setState(() => _minutesBefore = mins),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteController,
              maxLines: 3,
              style: const TextStyle(color: cyan, fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: loc.notes,
                labelStyle: const TextStyle(
                  color: cyan,
                  fontFamily: 'monospace',
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: cyan, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: cyan, width: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(loc.cancel),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: _saving ? Text(loc.dialogSaving) : Text(loc.save),
        ),
      ],
    );
  }
}

enum _ReminderMode { none, specific, minutesBefore }

class _ReminderSection extends StatelessWidget {
  final _ReminderMode mode;
  final ValueChanged<_ReminderMode> onModeChanged;
  final TimeOfDay? specificTime;
  final VoidCallback onPickSpecific;
  final TextEditingController minutesBeforeController;
  final ValueChanged<int> onMinutesChanged;

  const _ReminderSection({
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
        SegmentedButton<_ReminderMode>(
          segments: [
            ButtonSegment(value: _ReminderMode.none, label: Text(loc.none)),
            ButtonSegment(
              value: _ReminderMode.specific,
              label: Text(loc.specific),
            ),
            ButtonSegment(
              value: _ReminderMode.minutesBefore,
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
        if (mode == _ReminderMode.specific)
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
        if (mode == _ReminderMode.minutesBefore)
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
                  style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                  onChanged: (v) {
                    final mins = int.tryParse(v.trim());
                    if (mins != null) onMinutesChanged(mins);
                  },
                  decoration: const InputDecoration(
                    hintText: '30',
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: cyan, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: cyan, width: 1.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _NewSupplementDialog extends StatefulWidget {
  const _NewSupplementDialog();

  @override
  State<_NewSupplementDialog> createState() => _NewSupplementDialogState();
}

class _NewSupplementDialogState extends State<_NewSupplementDialog> {
  final _client = Supabase.instance.client;
  final _nameCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      final uid = _client.auth.currentUser?.id;
      await _client.from('supplements').insert({'name': name, 'user_id': uid});
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    final loc = context.l10n;

    return AlertDialog(
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      title: Text(
        loc.addSupplementTitle,
        style: const TextStyle(color: cyan, fontFamily: 'monospace'),
      ),
      content: TextField(
        controller: _nameCtrl,
        autofocus: true,
        style: const TextStyle(color: cyan, fontFamily: 'monospace'),
        decoration: InputDecoration(
          labelText: loc.medsMedicationName,
          labelStyle: const TextStyle(color: cyan, fontFamily: 'monospace'),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: cyan, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: cyan, width: 1.5),
          ),
        ),
        onSubmitted: (_) => _saving ? null : _save(),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(loc.cancel),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: _saving ? Text(loc.dialogSaving) : Text(loc.save),
        ),
      ],
    );
  }
}
