import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bio_cyber_os/l10n/app_localizations.dart';
import 'package:bio_cyber_os/l10n/context_l10n.dart';
import 'package:bio_cyber_os/l10n/meal_labels.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/notifications/vitality_notification_copy.dart';
import '../../../core/supabase_error_message.dart';
import '../../../core/supabase_log_date.dart';
import '../../../core/widgets/library_search_sheet.dart';
import '../../../core/widgets/reminder_section.dart';
import '../../../core/widgets/schedule_selector.dart';
import '../../../core/settings/measurement_settings.dart';
import '../../../core/settings/unit_options.dart';

class MedicationsScreen extends StatefulWidget {
  final String? focusLogId;
  final DateTime? focusDate;
  final bool embedded;

  const MedicationsScreen({
    super.key,
    this.focusLogId,
    this.focusDate,
    this.embedded = false,
  });

  @override
  State<MedicationsScreen> createState() => _MedicationsScreenState();
}

class _MedicationsScreenState extends State<MedicationsScreen>
    with WidgetsBindingObserver {
  final _client = Supabase.instance.client;

  static const _medsTable = 'medications';
  static const _logsTable = 'medication_logs';

  RealtimeChannel? _logsChannel;

  DateTime selectedDate = DateTime.now();
  bool _loading = true;
  String? _workingMedicationId;
  String? _workingLogId;

  List<Map<String, dynamic>> libraryMeds = [];
  List<Map<String, dynamic>> medLogs = [];

  String? _highlightLogId;
  final Map<String, GlobalKey> _rowKeys = {};

  Timer? _refreshTimer;

  static const _blocks = <String>['MORNING', 'AFTERNOON', 'EVENING', 'NIGHT'];

  String _canonicalBlock(dynamic raw) {
    final s = (raw ?? '').toString().trim().toUpperCase();
    if (s.isEmpty) return 'MORNING';
    if (_blocks.contains(s)) return s;
    return 'MORNING';
  }

  Map<String, List<Map<String, dynamic>>> _groupedByBlock() {
    final map = <String, List<Map<String, dynamic>>>{
      for (final b in _blocks) b: <Map<String, dynamic>>[],
    };
    for (final row in medLogs) {
      final b = _canonicalBlock(row['schedule_block']);
      map[b]!.add(row);
    }
    return map;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (t) {
      if (mounted) setState(() {});
    });
    _fetchData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fetchData();
      _subscribeMedLogsIfNeeded();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _logsChannel?.unsubscribe();
    _logsChannel = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) setState(() {});
      _fetchData();
    }
  }

  void _subscribeMedLogsIfNeeded() {
    _logsChannel?.unsubscribe();
    _logsChannel = null;
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    _logsChannel = _client.channel('medication_logs_$uid');
    _logsChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: _logsTable,
          callback: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _fetchData();
            });
          },
        )
        .subscribe();
  }

  @override
  void didUpdateWidget(covariant MedicationsScreen oldWidget) {
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

  bool _isViewingToday() {
    final now = DateTime.now();
    final s = selectedDate;
    return now.year == s.year && now.month == s.month && now.day == s.day;
  }

  String _isoUtc(DateTime dtLocal) => dtLocal.toUtc().toIso8601String();

  DateTime _takenAtLocalForNewLog() {
    final s = selectedDate;
    if (_isViewingToday()) return DateTime.now();
    return DateTime(s.year, s.month, s.day, 12, 0);
  }

  String _emptyLogsMessage(AppLocalizations l10n) => _isViewingToday()
      ? l10n.medsEmptyToday
      : l10n.medsEmptyForDay(_dayLabel(selectedDate));

  Future<void> _fetchData() async {
    setState(() => _loading = true);

    List<Map<String, dynamic>> nextLogs = medLogs;
    List<Map<String, dynamic>> nextLib = libraryMeds;
    Object? logsErr;
    Object? libErr;

    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        nextLogs = [];
      } else {
        final bounds = supabaseLocalDayUtcBounds(selectedDate);
        const sel = '*, medications(*)';
        final byId = <String, Map<String, dynamic>>{};
        Future<void> mergeFrom(String column) async {
          final chunk = await _client
              .from(_logsTable)
              .select(sel)
              .eq('user_id', uid)
              .gte(column, bounds.gte)
              .lt(column, bounds.lt)
              .order('scheduled_at', ascending: true);
          for (final row in (chunk as List).cast<Map<String, dynamic>>()) {
            final id = row['id']?.toString();
            if (id != null && id.isNotEmpty) byId[id] = row;
          }
        }

        await mergeFrom('created_at');
        await mergeFrom('scheduled_at');
        nextLogs = byId.values.toList()
          ..sort((a, b) {
            final sa = (a['scheduled_at'] ?? a['created_at'] ?? '').toString();
            final sb = (b['scheduled_at'] ?? b['created_at'] ?? '').toString();
            return sa.compareTo(sb);
          });
      }
    } catch (e) {
      logsErr = e;
      nextLogs = [];
    }

    try {
      final uid = _client.auth.currentUser?.id;
      var q = _client.from(_medsTable).select();
      if (uid != null) {
        q = q.or('user_id.eq.$uid,user_id.is.null');
      }
      final libData = await q.order('name');
      nextLib = (libData as List).cast<Map<String, dynamic>>();
    } catch (e) {
      libErr = e;
    }

    if (!mounted) return;
    setState(() {
      medLogs = nextLogs;
      if (libErr == null || nextLib.isNotEmpty) {
        libraryMeds = nextLib;
      }
      _loading = false;
    });

    if (logsErr != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.logsError('$logsErr'))),
      );
    } else if (libErr != null && nextLib.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.libraryError('$libErr'))),
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

  Future<void> _addMedicationToLibrary() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => const _MedicationLibraryDialog(),
    );
    if (changed == true && mounted) await _fetchData();
  }

  String _hhmmFromIso(dynamic iso) {
    try {
      final dt = DateTime.parse(iso.toString()).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '--:--';
    }
  }

  bool _isTaken(Map<String, dynamic> log) {
    final v = log['is_taken'];
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = (v ?? '').toString().trim().toLowerCase();
    if (s == 'true' || s == 't' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == 'f' || s == '0' || s == 'no') return false;
    // Back-compat: older rows used `taken_at` always.
    final ta = (log['taken_at'] ?? '').toString().trim();
    if (ta.isNotEmpty) return true;
    return false;
  }

  DateTime? _scheduledAtLocal(Map<String, dynamic> log) {
    final raw = log['scheduled_at'] ?? log['created_at'];
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
    final raw = log['taken_at'];
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

    setState(() {
      _workingLogId = id;
      medLogs = medLogs
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
          .from(_logsTable)
          .update({
            'is_taken': true,
            'taken_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id)
          .eq('user_id', uid);

      await NotificationService.cancelByKey('medication_logs:$id');
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

  double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  Future<void> _editLog(Map<String, dynamic> log) async {
    final id = (log['id'] ?? '').toString().trim();
    if (id.isEmpty) return;
    if (_workingLogId != null) return;

    final med = log['medications'];
    final name = (med is Map<String, dynamic>)
        ? (med['name'] ?? context.l10n.defaultMedicationName).toString()
        : context.l10n.defaultMedicationName;

    final existingAmount = _asDouble(log['dose_amount']);
    final existingUnit = (log['unit_type'] ?? '').toString().trim().isEmpty
        ? 'pcs'
        : (log['unit_type'] ?? '').toString().trim();

    final isTaken = _isTaken(log);
    final baseLocal =
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
      builder: (dialogCtx) => _EditMedLogDialog(
        logId: id,
        medicationName: name.isEmpty
            ? dialogCtx.l10n.defaultMedicationName
            : name,
        isTaken: isTaken,
        existingAmount: existingAmount > 0 ? existingAmount : null,
        existingUnit: existingUnit,
        existingNotes: (log['notes'] ?? '').toString(),
        existingScheduledAtLocal: baseLocal,
        existingReminderAtLocal: reminderAtLocal,
        existingReminderOffsetMinutes: existingOffset,
        onRefresh: () async {
          if (!mounted) return;
          await _fetchData();
        },
      ),
    );
  }

  Future<void> _insertMedicationLog(
    Map<String, dynamic> med, {
    required String scheduleBlock,
  }) async {
    final mid = (med['id'] ?? '').toString();
    if (mid.isEmpty) return;
    if (_workingMedicationId != null) return;

    final name = (med['name'] ?? '').toString();
    final picked = await showDialog<_MedIntakePick?>(
      context: context,
      builder: (dialogCtx) => _LogMedIntakeDialog(
        medicationName: name.isEmpty
            ? dialogCtx.l10n.defaultMedicationName
            : name,
        baseDate: _takenAtLocalForNewLog(),
        initialScheduleBlock: _canonicalBlock(scheduleBlock),
      ),
    );
    if (picked == null) return;
    if (!mounted) return;
    final l10n = context.l10n;
    final medLabel =
        name.isEmpty ? l10n.defaultMedicationName : name;

    if (_client.auth.currentUser == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.msgSignInLogMeds),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    final userId = _client.auth.currentUser!.id;

    setState(() => _workingMedicationId = mid);
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
          'user_id': userId,
          // Explicit created_at so medication_logs rows match Reports/PDF UTC day filters.
          'created_at': _isoUtc(scheduledI),
          'medication_id': mid,
          'scheduled_at': _isoUtc(scheduledI),
          'dose_amount': picked.amount,
          'unit_type': picked.unit,
          'notes': picked.notes,
          'schedule_block': _canonicalBlock(picked.scheduleBlock),
          'is_taken': logNow,
          if (logNow) 'taken_at': _isoUtc(scheduledI),
        };
        if (reminderI != null) {
          payload['reminder_at'] = _isoUtc(reminderI);
          payload['reminder_offset_minutes'] = reminderOffsetMinutes;
        }
        rows.add(payload);
        scheduledLocals.add(scheduledI);
        reminderLocals.add(reminderI);
      }

      final inserted = await _client.from(_logsTable).insert(rows).select('id');
      final insertedList = (inserted as List).cast<Map<String, dynamic>>();
      for (var i = 0; i < insertedList.length; i++) {
        final newId = (insertedList[i]['id'] ?? '').toString().trim();
        final rLocal = (i < reminderLocals.length) ? reminderLocals[i] : null;
        final schedLocal = (i < scheduledLocals.length)
            ? scheduledLocals[i]
            : null;
        if (rLocal != null && newId.isNotEmpty && schedLocal != null) {
          await NotificationService.scheduleByKey(
            key: 'medication_logs:$newId',
            title: VitalityNotificationCopy.buildTitle(
              VitalityCalendarCategory.medications,
            ),
            body: VitalityNotificationCopy.buildBody(
              category: VitalityCalendarCategory.medications,
              itemName: medLabel,
              amount: picked.amount,
              unit: picked.unit,
            ),
            whenLocal: rLocal,
            payload: {
              'item_type': 'medication',
              'item_id': newId,
              'target_date':
                  '${schedLocal.year.toString().padLeft(4, '0')}-${schedLocal.month.toString().padLeft(2, '0')}-${schedLocal.day.toString().padLeft(2, '0')}',
            },
            alarmItemName: medLabel,
            alarmAmount:
                VitalityNotificationCopy.formatAmountForDisplay(picked.amount),
            alarmUnit: picked.unit,
          );
        }
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(supabaseWriteErrorMessage(e)),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _workingMedicationId = null);
    }
  }

  Future<void> _deleteLog(Map<String, dynamic> log) async {
    final id = (log['id'] ?? '').toString();
    if (id.isEmpty) return;
    if (_workingLogId != null) return;
    setState(() => _workingLogId = id);
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
      await _client.from(_logsTable).delete().eq('id', id).eq('user_id', uid);
      if (!mounted) return;
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

  Future<void> _pickMedicationFromLibrary({
    required String scheduleBlock,
  }) async {
    final uid = _client.auth.currentUser?.id;
    final loc = context.l10n;
    await LibrarySearchSheet.show(
      context,
      title: loc.logMedicationBlock(
        localizedTimeBlock(loc, _canonicalBlock(scheduleBlock)),
      ),
      table: 'medications',
      emptyMessage: loc.noItemsFound,
      addNewLabel: loc.libraryAddNew,
      accessOrFilter: uid != null ? 'user_id.eq.$uid,user_id.is.null' : null,
      onAddNew: () async {
        await _addMedicationToLibrary();
      },
      getName: (row) => (row['name'] ?? '').toString(),
      getSubtitle: (row) {
        final rawDose = row['daily_dosage'];
        final rawUnit = row['unit_type'];
        final dose = (rawDose is num)
            ? rawDose.toDouble()
            : double.tryParse('$rawDose') ?? 0;
        final unit = (rawUnit ?? '').toString().trim();
        if (dose <= 0) return loc.libraryNoDefaultDose;
        return loc.libraryDefaultDose('$dose', unit.isEmpty ? 'pcs' : unit);
      },
      getIcon: (_) => Icons.medication_liquid_outlined,
      onPick: (row) => _insertMedicationLog(row, scheduleBlock: scheduleBlock),
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
                l10n.screenMeds,
                style: const TextStyle(
                  color: AppColors.cyberGold,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
              foregroundColor: gold,
              actions: [
                IconButton(
                  tooltip: l10n.addMedicationToLibrary,
                  onPressed: _addMedicationToLibrary,
                  icon: const Icon(Icons.playlist_add),
                ),
                IconButton(
                  tooltip: l10n.refresh,
                  onPressed: _fetchData,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
      body: LayoutBuilder(
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
                    tooltip: l10n.nextDay,
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
                      if (medLogs.isEmpty)
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
                          addLabel: l10n.medsAddBlockMed(
                            localizedTimeBlock(l10n, block),
                          ),
                          entries: _groupedByBlock()[block]!,
                          onAdd: () =>
                              _pickMedicationFromLibrary(scheduleBlock: block),
                          buildRow: (log) {
                            final med = log['medications'];
                            final name = (med is Map<String, dynamic>)
                                ? (med['name'] ?? l10n.unknown).toString()
                                : l10n.unknown;
                            final doseAmount = (log['dose_amount'] is num)
                                ? (log['dose_amount'] as num).toDouble()
                                : double.tryParse(
                                    (log['dose_amount'] ?? '').toString(),
                                  );
                            final unit = (log['unit_type'] ?? '').toString();
                            final isTakenRow = _isTaken(log);
                            final time = _hhmmFromIso(
                              isTakenRow
                                  ? log['taken_at']
                                  : log['scheduled_at'],
                            );
                            final doseLine =
                                (doseAmount == null || doseAmount <= 0)
                                ? ''
                                : '${doseAmount == doseAmount.roundToDouble() ? doseAmount.toInt() : doseAmount} $unit'
                                      .trim();
                            final note = (log['notes'] ?? '').toString().trim();
                            final reminder = log['reminder_at'];
                            final reminderLabel =
                                (reminder == null ||
                                    reminder.toString().trim().isEmpty)
                                ? ''
                                : l10n.reminderAtTime(_hhmmFromIso(reminder));
                            final id = (log['id'] ?? '').toString();
                            final isMissed = _isMissed(log);
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
                                      : (isTakenRow
                                            ? const Color(0x2200F3FF)
                                            : const Color(0x6600F3FF)),
                                  width: highlight ? 2 : 1,
                                ),
                              ),
                              child: Opacity(
                                opacity: isTakenRow ? 1.0 : 0.72,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      isTakenRow
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
                                                  '$time — $name ${doseLine.isEmpty ? '' : '($doseLine)'}'
                                                      .trim(),
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
                                          if (reminderLabel.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              reminderLabel,
                                              style: const TextStyle(
                                                color: AppColors.cyberGoldMuted,
                                                fontFamily: 'monospace',
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
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
                                          if (!isTakenRow) ...[
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
                                          : () => _deleteLog(log),
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
        },
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

class _MedIntakePick {
  final double amount;
  final String unit;
  final TimeOfDay intakeTime;
  final ReminderState reminder;
  final String notes;
  final LogIntakeTab tab;
  final String scheduleBlock;

  /// Resolved list of date-only (local) dates; one row will be inserted per
  /// entry. Always non-empty (defaults to the base date).
  final List<DateTime> targetDates;

  const _MedIntakePick({
    required this.amount,
    required this.unit,
    required this.intakeTime,
    required this.reminder,
    required this.notes,
    required this.tab,
    required this.scheduleBlock,
    required this.targetDates,
  });
}

enum LogIntakeTab { logNow, plan }

class _LogMedIntakeDialog extends StatefulWidget {
  final String medicationName;
  final DateTime baseDate;
  final String initialScheduleBlock;

  const _LogMedIntakeDialog({
    required this.medicationName,
    required this.baseDate,
    required this.initialScheduleBlock,
  });

  @override
  State<_LogMedIntakeDialog> createState() => _LogMedIntakeDialogState();
}

class _LogMedIntakeDialogState extends State<_LogMedIntakeDialog> {
  late final TextEditingController _amountCtrl;
  final _notesCtrl = TextEditingController();
  late final TextEditingController _timeController;
  late List<String> _units;
  late String _unit;

  LogIntakeTab _selectedTab = LogIntakeTab.logNow;
  late String _selectedBlock;

  ReminderState _reminder = const ReminderState.disabled();
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
    _units = UnitOptions.forContext(UnitContext.medication, sys);
    _unit = UnitOptions.defaultUnit(UnitContext.medication, sys);
    _amountCtrl = TextEditingController(text: '1');
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    _timeController.dispose();
    super.dispose();
  }

  double? _parseAmount() {
    final raw = _amountCtrl.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
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
        loc.medsLogIntakeTitle,
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
                widget.medicationName,
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
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _parseHhmm(_timeController.text),
                  );
                  if (picked == null) return;
                  if (!mounted) return;
                  setState(() => _timeController.text = _fmtHhmm(picked));
                },
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
                autofocus: true,
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
              TextField(
                controller: _notesCtrl,
                maxLines: 3,
                style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  labelText: loc.notes,
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
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop<_MedIntakePick?>(null),
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
              _MedIntakePick(
                amount: amt,
                unit: _unit,
                intakeTime: intakeTime,
                reminder: _reminder,
                notes: _notesCtrl.text,
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

class _EditMedLogDialog extends StatefulWidget {
  final String logId;
  final String medicationName;
  final bool isTaken;
  final double? existingAmount;
  final String existingUnit;
  final String existingNotes;
  final DateTime existingScheduledAtLocal;
  final DateTime? existingReminderAtLocal;
  final int? existingReminderOffsetMinutes;
  final Future<void> Function() onRefresh;

  const _EditMedLogDialog({
    required this.logId,
    required this.medicationName,
    required this.isTaken,
    required this.existingAmount,
    required this.existingUnit,
    required this.existingNotes,
    required this.existingScheduledAtLocal,
    required this.existingReminderAtLocal,
    required this.existingReminderOffsetMinutes,
    required this.onRefresh,
  });

  @override
  State<_EditMedLogDialog> createState() => _EditMedLogDialogState();
}

class _EditMedLogDialogState extends State<_EditMedLogDialog> {
  final _client = Supabase.instance.client;
  late final TextEditingController _amountCtrl;
  final _notesCtrl = TextEditingController();
  late String _unit;
  late TimeOfDay _time;
  late ReminderState _reminder;
  bool _saving = false;

  static const _units = <String>['mg', 'g', 'ml', 'pcs', 'drops', 'capsules'];

  @override
  void initState() {
    super.initState();
    final amt = widget.existingAmount ?? 1.0;
    _amountCtrl = TextEditingController(
      text: amt == amt.roundToDouble()
          ? amt.toInt().toString()
          : amt.toString(),
    );
    _notesCtrl.text = widget.existingNotes;
    _unit = widget.existingUnit.trim().isEmpty ? 'pcs' : widget.existingUnit;
    _time = TimeOfDay.fromDateTime(widget.existingScheduledAtLocal);

    final existingOffset = widget.existingReminderOffsetMinutes;
    if (widget.existingReminderAtLocal != null) {
      if (existingOffset != null && existingOffset > 0) {
        _reminder = ReminderState(
          enabled: true,
          mode: ReminderMode.minutesBefore,
          offsetMinutes: existingOffset,
        );
      } else {
        _reminder = const ReminderState(
          enabled: true,
          mode: ReminderMode.atConsumptionTime,
          offsetMinutes: 0,
        );
      }
    } else {
      _reminder = const ReminderState.disabled();
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double? _parseAmount() {
    final raw = _amountCtrl.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked == null) return;
    if (!mounted) return;
    setState(() => _time = picked);
  }

  DateTime _scheduledAtLocal() {
    final base = widget.existingScheduledAtLocal;
    return DateTime(base.year, base.month, base.day, _time.hour, _time.minute);
  }

  DateTime? _computeReminderAtLocal(DateTime scheduledAtLocal) {
    if (!_reminder.enabled) return null;
    if (_reminder.mode == ReminderMode.atConsumptionTime) {
      return scheduledAtLocal;
    }
    return scheduledAtLocal.subtract(
      Duration(minutes: _reminder.offsetMinutes),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.msgSignInSave),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final amt = _parseAmount();
      if (amt == null || amt <= 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.msgValidDose)));
        return;
      }

      final scheduledLocal = _scheduledAtLocal();
      final reminderLocal = _computeReminderAtLocal(scheduledLocal);
      final reminderOffsetMinutes = !_reminder.enabled
          ? null
          : (_reminder.mode == ReminderMode.minutesBefore
                ? _reminder.offsetMinutes
                : 0);

      final update = <String, dynamic>{
        'user_id': uid,
        'dose_amount': amt,
        'unit_type': _unit,
        'notes': _notesCtrl.text,
        'created_at': scheduledLocal.toUtc().toIso8601String(),
        'scheduled_at': scheduledLocal.toUtc().toIso8601String(),
        if (widget.isTaken)
          'taken_at': scheduledLocal.toUtc().toIso8601String(),
        'reminder_at': reminderLocal?.toUtc().toIso8601String(),
        'reminder_offset_minutes': reminderOffsetMinutes,
      };
      await _client
          .from('medication_logs')
          .update(update)
          .eq('id', widget.logId)
          .eq('user_id', uid);

      await NotificationService.cancelByKey('medication_logs:${widget.logId}');
      if (reminderLocal != null) {
        if (!mounted) return;
        await NotificationService.scheduleByKey(
          key: 'medication_logs:${widget.logId}',
          title: VitalityNotificationCopy.buildTitle(
            VitalityCalendarCategory.medications,
          ),
          body: VitalityNotificationCopy.buildBody(
            category: VitalityCalendarCategory.medications,
            itemName: widget.medicationName,
            amount: amt,
            unit: _unit,
          ),
          whenLocal: reminderLocal,
          payload: {
            'item_type': 'medication',
            'item_id': widget.logId,
            'target_date':
                '${scheduledLocal.year.toString().padLeft(4, '0')}-${scheduledLocal.month.toString().padLeft(2, '0')}-${scheduledLocal.day.toString().padLeft(2, '0')}',
          },
          alarmItemName: widget.medicationName,
          alarmAmount: VitalityNotificationCopy.formatAmountForDisplay(amt),
          alarmUnit: _unit,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.onRefresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
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
    final timeLabel = loc.timeAt(
      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
    );

    return AlertDialog(
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      title: Text(
        loc.medsEditLogTitle,
        style: const TextStyle(color: cyan, fontFamily: 'monospace'),
      ),
      content: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth.isFinite && constraints.maxWidth > 0
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final contentW = maxW.clamp(280.0, 520.0);
          return SizedBox(
            width: contentW,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.medicationName,
                    style: const TextStyle(
                      color: cyan,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, inner) {
                      if (inner.maxWidth < 360) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _amountCtrl,
                              keyboardType: TextInputType.number,
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
                                  borderSide:
                                      BorderSide(color: cyan, width: 1.5),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              initialValue:
                                  _units.contains(_unit) ? _unit : 'pcs',
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
                                  borderSide:
                                      BorderSide(color: cyan, width: 1.5),
                                ),
                              ),
                              dropdownColor: bg,
                              isExpanded: true,
                              items: _units
                                  .map(
                                    (u) => DropdownMenuItem(
                                      value: u,
                                      child: Text(
                                        u,
                                        style: const TextStyle(
                                          color: cyan,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: (v) =>
                                  setState(() => _unit = v ?? 'pcs'),
                            ),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _amountCtrl,
                              keyboardType: TextInputType.number,
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
                                  borderSide:
                                      BorderSide(color: cyan, width: 1.5),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 150,
                            child: DropdownButtonFormField<String>(
                              initialValue:
                                  _units.contains(_unit) ? _unit : 'pcs',
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
                                  borderSide:
                                      BorderSide(color: cyan, width: 1.5),
                                ),
                              ),
                              dropdownColor: bg,
                              items: _units
                                  .map(
                                    (u) => DropdownMenuItem(
                                      value: u,
                                      child: Text(
                                        u,
                                        style: const TextStyle(
                                          color: cyan,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: (v) =>
                                  setState(() => _unit = v ?? 'pcs'),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.schedule),
              label: Text(
                timeLabel,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: cyan,
                side: const BorderSide(color: cyan, width: 1),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ReminderSection(
              state: _reminder,
              onChanged: (s) => setState(() => _reminder = s),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
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
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(loc.cancel),
        ),
        TextButton(onPressed: _saving ? null : _save, child: Text(loc.save)),
      ],
    );
  }
}

class _MedicationLibraryDialog extends StatefulWidget {
  const _MedicationLibraryDialog();

  @override
  State<_MedicationLibraryDialog> createState() =>
      _MedicationLibraryDialogState();
}

class _MedicationLibraryDialogState extends State<_MedicationLibraryDialog> {
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
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.msgSignInAddMeds),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _client.from('medications').insert({'name': name, 'user_id': uid});
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(supabaseWriteErrorMessage(e))));
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
        loc.medsNewMedicationTitle,
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
        TextButton(onPressed: _saving ? null : _save, child: Text(loc.save)),
      ],
    );
  }
}
