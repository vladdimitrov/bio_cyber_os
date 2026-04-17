import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bio_cyber_os/l10n/app_localizations.dart';
import 'package:bio_cyber_os/l10n/context_l10n.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/services/open_food_facts_service.dart';
import '../../../core/supabase_error_message.dart';
import '../../../core/supabase_log_date.dart';
import '../../../core/widgets/reminder_section.dart';
import '../../food/screens/barcode_scanner_screen.dart';

enum _IntakeType { supplement, medication }

class DailyIntakeScreen extends StatefulWidget {
  final int initialTabIndex; // legacy; ignored (kept for AppShell callers)
  final String? focusSuppLogId; // legacy; ignored (kept for AppShell callers)
  final DateTime? focusSuppDate;
  final String? focusMedLogId; // legacy; ignored (kept for AppShell callers)
  final DateTime? focusMedDate;

  const DailyIntakeScreen({
    super.key,
    this.initialTabIndex = 0,
    this.focusSuppLogId,
    this.focusSuppDate,
    this.focusMedLogId,
    this.focusMedDate,
  });

  @override
  State<DailyIntakeScreen> createState() => _DailyIntakeScreenState();
}

class _DailyIntakeScreenState extends State<DailyIntakeScreen> {
  final _client = Supabase.instance.client;

  DateTime _selectedDay = DateTime.now();
  bool _loading = true;
  Object? _error;

  List<_IntakeEntry> _entries = const [];
  StreamSubscription<AuthState>? _sub;

  @override
  void initState() {
    super.initState();
    _selectedDay = widget.focusSuppDate ?? widget.focusMedDate ?? DateTime.now();
    _selectedDay = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
    _fetch();

    // Best-effort: refresh on auth/session changes (e.g., after quick add).
    _sub = _client.auth.onAuthStateChange.listen((_) {
      if (!mounted) return;
      _fetch();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked == null) return;
    setState(() => _selectedDay = DateTime(picked.year, picked.month, picked.day));
    await _fetch();
  }

  Future<void> _shiftDay(int deltaDays) async {
    setState(() => _selectedDay = _selectedDay.add(Duration(days: deltaDays)));
    await _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        setState(() {
          _entries = const [];
          _loading = false;
        });
        return;
      }

      final suppFuture = _fetchSupplementLogs(uid);
      final medsFuture = _fetchMedicationLogs(uid);
      final results = await Future.wait([suppFuture, medsFuture]);
      final supp = results[0];
      final meds = results[1];
      final merged = [...supp, ...meds]
        ..sort((a, b) => a.sortIsoUtc.compareTo(b.sortIsoUtc));

      if (!mounted) return;
      setState(() {
        _entries = merged;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _entries = const [];
        _loading = false;
      });
    }
  }

  Future<List<_IntakeEntry>> _fetchSupplementLogs(String uid) async {
    final dayStr = supabaseDateOnly(_selectedDay);
    final data = await _client
        .from('daily_logs')
        .select('id,created_at,scheduled_at,taken_at,is_taken,amount_grams,unit,schedule_block,notes,supplement_id,supplements(name)')
        .eq('user_id', uid)
        .gte('created_at', supabaseCreatedAtDayGte(dayStr))
        .lte('created_at', supabaseCreatedAtDayLte(dayStr))
        .order('scheduled_at', ascending: true);
    final rows = (data as List).cast<Map<String, dynamic>>();
    final out = <_IntakeEntry>[];
    for (final r in rows) {
      final sid = r['supplement_id'];
      if (sid == null || sid.toString().trim().isEmpty) continue;
      final joined = r['supplements'];
      final name = (joined is Map<String, dynamic>)
          ? (joined['name'] ?? '').toString()
          : '';
      out.add(
        _IntakeEntry(
          type: _IntakeType.supplement,
          id: (r['id'] ?? '').toString(),
          name: name.isNotEmpty ? name : 'Supplement',
          scheduleBlock: (r['schedule_block'] ?? 'MORNING').toString(),
          unit: (r['unit'] ?? '').toString(),
          amount: (r['amount_grams'] is num) ? (r['amount_grams'] as num).toDouble() : 0.0,
          notes: (r['notes'] ?? '').toString(),
          scheduledIsoUtc: (r['scheduled_at'] ?? r['created_at'] ?? '').toString(),
          takenIsoUtc: (r['taken_at'] ?? '').toString(),
          isTaken: _asBool(r['is_taken']),
          sortIsoUtc: (r['scheduled_at'] ?? r['created_at'] ?? '').toString(),
        ),
      );
    }
    return out;
  }

  Future<List<_IntakeEntry>> _fetchMedicationLogs(String uid) async {
    final bounds = supabaseLocalDayUtcBounds(_selectedDay);
    const sel = 'id,created_at,scheduled_at,taken_at,is_taken,dose_amount,unit_type,schedule_block,notes,medication_id,medications(name)';
    final byId = <String, Map<String, dynamic>>{};

    Future<void> mergeFrom(String column) async {
      final chunk = await _client
          .from('medication_logs')
          .select(sel)
          .eq('user_id', uid)
          .gte(column, bounds.gte)
          .lt(column, bounds.lt)
          .order('scheduled_at', ascending: true);
      for (final row in (chunk as List).cast<Map<String, dynamic>>()) {
        final id = (row['id'] ?? '').toString();
        if (id.isNotEmpty) byId[id] = row;
      }
    }

    await mergeFrom('created_at');
    await mergeFrom('scheduled_at');
    final rows = byId.values.toList()
      ..sort((a, b) {
        final sa = (a['scheduled_at'] ?? a['created_at'] ?? '').toString();
        final sb = (b['scheduled_at'] ?? b['created_at'] ?? '').toString();
        return sa.compareTo(sb);
      });

    final out = <_IntakeEntry>[];
    for (final r in rows) {
      final joined = r['medications'];
      final name = (joined is Map<String, dynamic>)
          ? (joined['name'] ?? '').toString()
          : '';
      out.add(
        _IntakeEntry(
          type: _IntakeType.medication,
          id: (r['id'] ?? '').toString(),
          name: name.isNotEmpty ? name : 'Medication',
          scheduleBlock: (r['schedule_block'] ?? 'MORNING').toString(),
          unit: (r['unit_type'] ?? '').toString(),
          amount: (r['dose_amount'] is num) ? (r['dose_amount'] as num).toDouble() : 0.0,
          notes: (r['notes'] ?? '').toString(),
          scheduledIsoUtc: (r['scheduled_at'] ?? r['created_at'] ?? '').toString(),
          takenIsoUtc: (r['taken_at'] ?? '').toString(),
          isTaken: _asBool(r['is_taken']),
          sortIsoUtc: (r['scheduled_at'] ?? r['created_at'] ?? '').toString(),
        ),
      );
    }
    return out;
  }

  Future<void> _toggleTaken(_IntakeEntry e, bool next) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;

    final markIsoUtc = next
        ? DateTime.now().toUtc().toIso8601String()
        : '';
    setState(() {
      _entries = _entries
          .map((x) => x.id == e.id
              ? x.copyWith(
                  isTaken: next,
                  takenIsoUtc: markIsoUtc,
                )
              : x)
          .toList(growable: false);
    });

    if (next) {
      final key = e.type == _IntakeType.supplement
          ? 'daily_logs:${e.id}'
          : 'medication_logs:${e.id}';
      await NotificationService.cancelByKey(key);
    }

    try {
      if (e.type == _IntakeType.supplement) {
        await _client.from('daily_logs').update({
          'is_taken': next,
          'taken_at': next ? markIsoUtc : null,
        }).eq('id', e.id).eq('user_id', uid);
      } else {
        await _client.from('medication_logs').update({
          'is_taken': next,
          'taken_at': next ? markIsoUtc : null,
        }).eq('id', e.id).eq('user_id', uid);
      }
    } catch (_) {
      // revert with best-effort reload
      if (mounted) await _fetch();
    }
  }

  Future<void> _deleteWithUndo(_IntakeEntry e) async {
    if (!mounted) return;
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    final messenger = ScaffoldMessenger.of(context);

    final idx = _entries.indexWhere((x) => x.id == e.id);
    if (idx < 0) return;
    final removed = e;

    setState(() {
      final next = _entries.toList(growable: true);
      next.removeAt(idx);
      _entries = next;
    });

    var undone = false;
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text('Deleted "${e.name}".'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () {
            undone = true;
            if (!mounted) return;
            setState(() {
              final next = _entries.toList(growable: true);
              final insertAt = idx.clamp(0, next.length);
              next.insert(insertAt, removed);
              _entries = next;
            });
          },
        ),
      ),
    );

    final reason = await controller.closed;
    if (!mounted) return;
    if (undone || reason == SnackBarClosedReason.action) return;

    try {
      if (removed.type == _IntakeType.supplement) {
        await _client
            .from('daily_logs')
            .delete()
            .eq('id', removed.id)
            .eq('user_id', uid);
        await NotificationService.cancelByKey('daily_logs:${removed.id}');
      } else {
        await _client
            .from('medication_logs')
            .delete()
            .eq('id', removed.id)
            .eq('user_id', uid);
        await NotificationService.cancelByKey('medication_logs:${removed.id}');
      }
    } catch (err) {
      // Restore row if delete failed.
      if (!mounted) return;
      setState(() {
        final next = _entries.toList(growable: true);
        final insertAt = idx.clamp(0, next.length);
        next.insert(insertAt, removed);
        _entries = next;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(supabaseWriteErrorMessage(err)),
          backgroundColor: Colors.redAccent,
          showCloseIcon: true,
        ),
      );
    }
  }

  Future<void> _editEntry(_IntakeEntry e) async {
    final picked = await showDialog<_EditPick?>(
      context: context,
      builder: (_) => _EditPickDialog(entry: e),
    );
    if (picked == null) return;

    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;

    final day = _selectedDay;
    final scheduledLocal = DateTime(
      day.year,
      day.month,
      day.day,
      picked.time.hour,
      picked.time.minute,
    );
    final scheduledIsoUtc = scheduledLocal.toUtc().toIso8601String();

    // Optimistic local update.
    setState(() {
      _entries = _entries
          .map(
            (x) => x.id == e.id
                ? x.copyWith(
                    amount: picked.amount,
                    unit: picked.unit,
                    scheduleBlock: picked.block,
                    notes: picked.notes,
                    scheduledIsoUtc: scheduledIsoUtc,
                    sortIsoUtc: scheduledIsoUtc,
                  )
                : x,
          )
          .toList(growable: false);
    });

    try {
      if (e.type == _IntakeType.supplement) {
        final payload = <String, dynamic>{
          'user_id': uid,
          'amount_grams': picked.amount,
          'unit': picked.unit,
          'schedule_block': picked.block,
          'notes': picked.notes,
          'scheduled_at': scheduledIsoUtc,
          'created_at': scheduledIsoUtc,
        };
        await _client
            .from('daily_logs')
            .update(payload)
            .eq('id', e.id)
            .eq('user_id', uid);
      } else {
        final payload = <String, dynamic>{
          'user_id': uid,
          'dose_amount': picked.amount,
          'unit_type': picked.unit,
          'schedule_block': picked.block,
          'notes': picked.notes,
          'scheduled_at': scheduledIsoUtc,
          'created_at': scheduledIsoUtc,
        };
        await _client
            .from('medication_logs')
            .update(payload)
            .eq('id', e.id)
            .eq('user_id', uid);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Updated entry.')),
      );
      await _fetch();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(supabaseWriteErrorMessage(err)),
          backgroundColor: Colors.redAccent,
          showCloseIcon: true,
        ),
      );
      await _fetch(); // revert optimistic update
    }
  }

  Future<void> _openAddFlow() async {
    await _CombinedLibrarySheet.show(
      context,
      selectedDay: _selectedDay,
      onLogged: _fetch,
    );
  }

  String _dayLabel(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }

  String _blockKey(String raw) {
    final k = raw.trim().toUpperCase();
    if (k.contains('MORN')) return 'MORNING';
    if (k.contains('NOON') || k.contains('LUNCH')) return 'AFTERNOON';
    if (k.contains('EVE')) return 'EVENING';
    if (k.contains('NIGHT') || k.contains('BED')) return 'NIGHT';
    return 'OTHER';
  }

  Map<String, List<_IntakeEntry>> _entriesByBlock() {
    const order = ['MORNING', 'AFTERNOON', 'EVENING', 'NIGHT', 'OTHER'];
    final m = {for (final k in order) k: <_IntakeEntry>[]};
    for (final e in _entries) {
      m[_blockKey(e.scheduleBlock)]!.add(e);
    }
    for (final list in m.values) {
      list.sort((a, b) => a.sortIsoUtc.compareTo(b.sortIsoUtc));
    }
    return m;
  }

  ({int taken, int total}) _subsetStats(bool Function(_IntakeEntry) pred) {
    final sub = _entries.where(pred).toList();
    final taken = sub.where((e) => e.isTaken).length;
    return (taken: taken, total: sub.length);
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    final l10n = AppLocalizations.of(context)!;
    final grouped = _entriesByBlock();
    final all = _subsetStats((_) => true);
    final sup = _subsetStats((e) => e.type == _IntakeType.supplement);
    final med = _subsetStats((e) => e.type == _IntakeType.medication);

    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('DAILY INTAKE'),
        actions: [
          IconButton(
            tooltip: l10n.refresh,
            onPressed: _fetch,
            icon: const Icon(Icons.refresh),
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
                      _error.toString(),
                      style: const TextStyle(color: cyan),
                    ),
                  )
                : Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: cyan, width: 2),
                          ),
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
                                'INTAKE ADHERENCE',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0,
                                  color: cyan.withValues(alpha: 0.9),
                                ),
                              ),
                              const SizedBox(height: 10),
                              _IntakeDualMacroBar(
                                label: 'ALL',
                                consumed: all.taken.toDouble(),
                                prognostic: all.total.toDouble(),
                                target: (all.total > 0 ? all.total : 1).toDouble(),
                                unit: '',
                                decimals: 0,
                              ),
                              const SizedBox(height: 8),
                              _IntakeDualMacroBar(
                                label: 'SUPP',
                                consumed: sup.taken.toDouble(),
                                prognostic: sup.total.toDouble(),
                                target: (sup.total > 0 ? sup.total : 1).toDouble(),
                                unit: '',
                                decimals: 0,
                              ),
                              const SizedBox(height: 8),
                              _IntakeDualMacroBar(
                                label: 'MED',
                                consumed: med.taken.toDouble(),
                                prognostic: med.total.toDouble(),
                                target: (med.total > 0 ? med.total : 1).toDouble(),
                                unit: '',
                                decimals: 0,
                              ),
                              const SizedBox(height: 8),
                              _IntakeDualMacroBar(
                                label: 'OPEN',
                                consumed: 0,
                                prognostic: _entries
                                    .where((e) => !e.isTaken)
                                    .length
                                    .toDouble(),
                                target: (all.total > 0 ? all.total : 1).toDouble(),
                                unit: '',
                                decimals: 0,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                          children: [
                            if (_entries.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                  'No intake entries for ${_dayLabel(_selectedDay)}.',
                                  style: const TextStyle(
                                    color: Color(0x8800F3FF),
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            for (final slot in const [
                              'MORNING',
                              'AFTERNOON',
                              'EVENING',
                              'NIGHT',
                              'OTHER',
                            ])
                              _IntakeSlotSection(
                                title: slot,
                                entries: grouped[slot] ?? const [],
                                onPlanSlot: _openAddFlow,
                                buildRow: (ctx, entry, detailed) {
                                  return _IntakeItemRow(
                                    entry: entry,
                                    showDetails: detailed,
                                    onToggleTaken: (v) => _toggleTaken(entry, v),
                                    onTake: () => _toggleTaken(entry, true),
                                    onEdit: () => _editEntry(entry),
                                    onDelete: () => _deleteWithUndo(entry),
                                  );
                                },
                              ),
                            const SizedBox(height: 8),
                            OutlinedButton(
                              onPressed: _openAddFlow,
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
                              child: const Text(
                                'ADD ENTRY',
                                textAlign: TextAlign.center,
                                style: TextStyle(
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
  }
}

class _IntakeEntry {
  final _IntakeType type;
  final String id;
  final String name;
  final String scheduleBlock;
  final double amount;
  final String unit;
  final String notes;
  final String scheduledIsoUtc;
  final String takenIsoUtc;
  final bool isTaken;
  final String sortIsoUtc;

  const _IntakeEntry({
    required this.type,
    required this.id,
    required this.name,
    required this.scheduleBlock,
    required this.amount,
    required this.unit,
    required this.notes,
    required this.scheduledIsoUtc,
    required this.takenIsoUtc,
    required this.isTaken,
    required this.sortIsoUtc,
  });

  _IntakeEntry copyWith({
    bool? isTaken,
    String? takenIsoUtc,
    double? amount,
    String? unit,
    String? scheduleBlock,
    String? notes,
    String? scheduledIsoUtc,
    String? sortIsoUtc,
  }) {
    return _IntakeEntry(
      type: type,
      id: id,
      name: name,
      scheduleBlock: scheduleBlock ?? this.scheduleBlock,
      amount: amount ?? this.amount,
      unit: unit ?? this.unit,
      notes: notes ?? this.notes,
      scheduledIsoUtc: scheduledIsoUtc ?? this.scheduledIsoUtc,
      takenIsoUtc: takenIsoUtc ?? this.takenIsoUtc,
      isTaken: isTaken ?? this.isTaken,
      sortIsoUtc: sortIsoUtc ?? this.sortIsoUtc,
    );
  }
}

typedef _IntakeRowBuilder = Widget Function(
  BuildContext context,
  _IntakeEntry entry,
  bool showDetails,
);

class _IntakeNotchedFramePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double notchWidth;
  final double notchCenterX;

  _IntakeNotchedFramePainter({
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
    final leftNotch =
        (notchCenterX - notchWidth / 2).clamp(6.0, size.width - 6.0);
    final rightNotch =
        (notchCenterX + notchWidth / 2).clamp(6.0, size.width - 6.0);

    canvas.drawLine(const Offset(0, 0), Offset(leftNotch, 0), p);
    canvas.drawLine(Offset(rightNotch, 0), Offset(size.width, 0), p);
    canvas.drawLine(const Offset(0, 0), Offset(0, size.height), p);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, size.height), p);
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), p);

    final glow = Paint()
      ..color = color.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;
    canvas.drawRect(r.deflate(1.0), glow);
  }

  @override
  bool shouldRepaint(covariant _IntakeNotchedFramePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.notchWidth != notchWidth ||
        oldDelegate.notchCenterX != notchCenterX;
  }
}

class _IntakeUnifiedMacroBarPainter extends CustomPainter {
  final double consumed;
  final double prognostic;
  final double target;

  _IntakeUnifiedMacroBarPainter({
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
      Paint()..color = const Color(0xFFFFC107),
    );
  }

  @override
  bool shouldRepaint(covariant _IntakeUnifiedMacroBarPainter oldDelegate) {
    return oldDelegate.consumed != consumed ||
        oldDelegate.prognostic != prognostic ||
        oldDelegate.target != target;
  }
}

class _IntakeDualMacroBar extends StatelessWidget {
  final String label;
  final double consumed;
  final double prognostic;
  final double target;
  final String unit;
  final int decimals;

  const _IntakeDualMacroBar({
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
    final t = raw.trim().toUpperCase();
    if (t.length > 6) return t.substring(0, 6).toUpperCase();
    return t.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFFFC107);
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
                painter: _IntakeUnifiedMacroBarPainter(
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
                    color: amber,
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

class _IntakeSlotSection extends StatefulWidget {
  final String title;
  final List<_IntakeEntry> entries;
  final VoidCallback onPlanSlot;
  final _IntakeRowBuilder buildRow;

  const _IntakeSlotSection({
    required this.title,
    required this.entries,
    required this.onPlanSlot,
    required this.buildRow,
  });

  @override
  State<_IntakeSlotSection> createState() => _IntakeSlotSectionState();
}

class _IntakeSlotSectionState extends State<_IntakeSlotSection> {
  bool _detailed = false;

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    final l10n = AppLocalizations.of(context)!;
    final entries = widget.entries;
    final planned = entries.where((e) => !e.isTaken).toList();
    final consumed = entries.where((e) => e.isTaken).toList();

    const titleNeon = Color(0xFF00FFFF);
    final titleStyle = const TextStyle(
      color: titleNeon,
      fontFamily: 'monospace',
      fontWeight: FontWeight.bold,
      letterSpacing: 1.4,
      fontSize: 16,
    );
    final tp = TextPainter(
      text: TextSpan(text: widget.title.toUpperCase(), style: titleStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final notchW = tp.width + 26 + 52;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: widget.onPlanSlot,
        splashColor: const Color(0x2200F3FF),
        highlightColor: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final notchCenterX = w / 2;
            return CustomPaint(
              painter: _IntakeNotchedFramePainter(
                color: cyan,
                strokeWidth: 1,
                notchWidth: notchW.clamp(80.0, w - 16),
                notchCenterX: notchCenterX,
              ),
              child: Container(
                color: bg,
                padding: const EdgeInsets.fromLTRB(12, 26, 12, 12),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
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
                              Text(
                                widget.title.toUpperCase(),
                                style: titleStyle,
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                onPressed: () =>
                                    setState(() => _detailed = !_detailed),
                                padding: const EdgeInsets.all(8),
                                iconSize: 28,
                                constraints: const BoxConstraints(
                                  minWidth: 48,
                                  minHeight: 48,
                                ),
                                icon: Icon(
                                  _detailed
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  size: 28,
                                  color: _detailed
                                      ? const Color(0xFF00F3FF)
                                      : const Color(0xFF88CCFF),
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
                              'Planned: ${planned.length}  |  Logged: ${consumed.length}',
                              style: const TextStyle(
                                fontSize: 12,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 4),
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
                                widget.buildRow(context, e, _detailed),
                              if (consumed.isNotEmpty) const SizedBox(height: 8),
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
                                widget.buildRow(context, e, _detailed),
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

class _IntakeItemRow extends StatelessWidget {
  final _IntakeEntry entry;
  final bool showDetails;
  final ValueChanged<bool> onToggleTaken;
  final VoidCallback onTake;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _IntakeItemRow({
    required this.entry,
    required this.showDetails,
    required this.onToggleTaken,
    required this.onTake,
    required this.onEdit,
    required this.onDelete,
  });

  String _hhmm(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '--:--';
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF00F3FF);
    const gold = Color(0xFFCBAB67);
    const ruby = Color(0xFFE91E63);
    final loc = context.l10n;

    final isMed = entry.type == _IntakeType.medication;
    final accent = isMed ? ruby : gold;
    final iconColor = isMed ? ruby : cyan;
    final icon = isMed ? Icons.medication_liquid : Icons.eco;
    final planned = !entry.isTaken;
    final slotIso = entry.scheduledIsoUtc;
    final takenIso = entry.takenIsoUtc.trim();
    final timeLabel = planned
        ? _hhmm(slotIso)
        : _hhmm(takenIso.isNotEmpty ? takenIso : slotIso);
    final amountStr = entry.amount > 0 ? entry.amount.toString() : '';
    final unitStr = entry.unit.trim();
    final dose = [amountStr, unitStr].where((x) => x.isNotEmpty).join(' ');

    final missed = () {
      if (!planned) return false;
      try {
        final slot = DateTime.parse(slotIso).toLocal();
        return DateTime.now().isAfter(slot.add(const Duration(minutes: 60)));
      } catch (_) {
        return false;
      }
    }();

    final titleLine = planned
        ? '$timeLabel — ${loc.planTag} ${entry.name}${dose.isNotEmpty ? ' ($dose)' : ''}'
        : '$timeLabel — ${entry.name}${dose.isNotEmpty ? ' ($dose)' : ''}';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.transparent, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        titleLine,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    if (missed) ...[
                      const SizedBox(width: 8),
                      Text(
                        loc.missed,
                        style: const TextStyle(
                          color: Colors.red,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
                if (showDetails) ...[
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _TagChip(
                        label: isMed ? 'MED' : 'SUPP',
                        color: accent,
                      ),
                      _TagChip(
                        label: entry.scheduleBlock.toUpperCase(),
                        color: const Color(0x8800F3FF),
                      ),
                      if (entry.notes.trim().isNotEmpty)
                        Text(
                          entry.notes.trim(),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF757575),
                            fontFamily: 'monospace',
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (planned) ...[
            ElevatedButton(
              onPressed: onTake,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF050510),
                foregroundColor: const Color(0xFF00F3FF),
                elevation: 0,
                side: const BorderSide(color: Color(0xFF00F3FF), width: 1),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(64, 40),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
              ),
              child: Text(
                loc.take,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 20),
              color: const Color(0xFF00F3FF),
              tooltip: loc.edit,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 20),
              color: const Color(0xFF00F3FF),
              tooltip: loc.delete,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
            ),
          ] else ...[
            IconButton(
              onPressed: () => onToggleTaken(false),
              icon: const Icon(Icons.undo_outlined, size: 20),
              color: const Color(0xFF88CCFF),
              tooltip: 'Mark not taken',
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
            ),
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 20),
              color: const Color(0xFF00F3FF),
              tooltip: loc.edit,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 20),
              color: const Color(0xFF00F3FF),
              tooltip: loc.delete,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
            ),
          ],
        ],
      ),
    );
  }
}

class _EditPick {
  final TimeOfDay time;
  final double amount;
  final String unit;
  final String block;
  final String notes;

  const _EditPick({
    required this.time,
    required this.amount,
    required this.unit,
    required this.block,
    required this.notes,
  });
}

class _EditPickDialog extends StatefulWidget {
  final _IntakeEntry entry;

  const _EditPickDialog({required this.entry});

  @override
  State<_EditPickDialog> createState() => _EditPickDialogState();
}

class _EditPickDialogState extends State<_EditPickDialog> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _notesCtrl;
  late TimeOfDay _time;
  late String _unit;
  late String _block;

  static const _blocks = ['MORNING', 'AFTERNOON', 'EVENING', 'NIGHT'];
  static const _suppUnits = ['g', 'mg', 'ml', 'drops', 'capsules', 'pcs'];
  static const _medUnits = ['mg', 'ml', 'pills', 'capsules', 'drops', 'pcs'];

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _amountCtrl = TextEditingController(
      text: e.amount <= 0 ? '' : (e.amount == e.amount.roundToDouble() ? e.amount.toInt().toString() : e.amount.toString()),
    );
    _notesCtrl = TextEditingController(text: e.notes);
    final dt = DateTime.tryParse(e.scheduledIsoUtc)?.toLocal() ?? DateTime.now();
    _time = TimeOfDay.fromDateTime(dt);
    _unit = e.unit.trim().isEmpty ? 'pcs' : e.unit.trim();
    _block = e.scheduleBlock.trim().isEmpty ? 'MORNING' : e.scheduleBlock.trim().toUpperCase();
    if (!_blocks.contains(_block)) _block = 'MORNING';
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double _d(String v) => double.tryParse(v.trim().replaceAll(',', '.')) ?? 0.0;

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    const gold = Color(0xFFCBAB67);
    final isMed = widget.entry.type == _IntakeType.medication;
    final accent = isMed ? gold : cyan;
    final units = isMed ? _medUnits : _suppUnits;
    final loc = context.l10n;

    return AlertDialog(
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      title: Text(
        'EDIT ENTRY',
        style: TextStyle(color: accent, fontFamily: 'monospace'),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.entry.name,
              style: const TextStyle(
                color: cyan,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _time,
                      );
                      if (picked == null) return;
                      if (!mounted) return;
                      setState(() => _time = picked);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent,
                      side: BorderSide(color: accent, width: 1),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                    child: Text(
                      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _block,
                    items: _blocks
                        .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                        .toList(growable: false),
                    onChanged: (v) => setState(() => _block = v ?? _block),
                    decoration: InputDecoration(
                      labelText: 'Block',
                      labelStyle: TextStyle(color: accent, fontFamily: 'monospace'),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: accent, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: accent, width: 1.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      labelStyle: TextStyle(color: accent, fontFamily: 'monospace'),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: accent, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: accent, width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _unit,
                    items: units
                        .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                        .toList(growable: false),
                    onChanged: (v) => setState(() => _unit = v ?? _unit),
                    decoration: InputDecoration(
                      labelText: 'Unit',
                      labelStyle: TextStyle(color: accent, fontFamily: 'monospace'),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: accent, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: accent, width: 1.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              style: const TextStyle(color: cyan, fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: 'Notes (optional)',
                labelStyle: TextStyle(color: accent, fontFamily: 'monospace'),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: accent, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: accent, width: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop<_EditPick?>(null),
          child: Text(loc.cancel.toUpperCase()),
        ),
        TextButton(
          onPressed: () {
            final amt = _d(_amountCtrl.text);
            if (amt <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(loc.msgValidAmount)),
              );
              return;
            }
            Navigator.of(context).pop(
              _EditPick(
                time: _time,
                amount: amt,
                unit: _unit,
                block: _block,
                notes: _notesCtrl.text.trim(),
              ),
            );
          },
          child: Text(loc.save.toUpperCase()),
        ),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final Color color;

  const _TagChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontFamily: 'monospace',
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.9,
        ),
      ),
    );
  }
}

bool _asBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = (v ?? '').toString().trim().toLowerCase();
  if (s == 'true' || s == 't' || s == '1' || s == 'yes') return true;
  if (s == 'false' || s == 'f' || s == '0' || s == 'no') return false;
  return false;
}

class _CombinedLibrarySheet extends StatefulWidget {
  final DateTime selectedDay;
  final VoidCallback onLogged;

  const _CombinedLibrarySheet({
    required this.selectedDay,
    required this.onLogged,
  });

  static Future<void> show(
    BuildContext context, {
    required DateTime selectedDay,
    required VoidCallback onLogged,
  }) {
    const bg = Color(0xFF050510);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.95,
        child: _CombinedLibrarySheet(
          selectedDay: selectedDay,
          onLogged: onLogged,
        ),
      ),
    );
  }

  @override
  State<_CombinedLibrarySheet> createState() => _CombinedLibrarySheetState();
}

class _CombinedLibrarySheetState extends State<_CombinedLibrarySheet> {
  final _client = Supabase.instance.client;
  final _controller = TextEditingController();
  String _q = '';
  bool _loading = true;
  Object? _error;
  List<_LibraryItem> _all = const [];
  List<_LibraryItem> _results = const [];
  int _requestId = 0;
  bool _barcodeBusy = false;
  String? _pendingBarcode;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final rid = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        setState(() {
          _all = const [];
          _results = const [];
          _loading = false;
        });
        return;
      }

      final suppFuture = _client
          .from('supplements')
          .select('id,name,user_id,daily_dosage,unit_type')
          .or('user_id.eq.$uid,user_id.is.null')
          .order('name')
          .limit(500);
      final medsFuture = _client
          .from('medications')
          .select('id,name,user_id')
          .or('user_id.eq.$uid,user_id.is.null')
          .order('name')
          .limit(500);
      final res = await Future.wait([suppFuture, medsFuture]);
      if (!mounted || rid != _requestId) return;
      final supp = (res[0] as List).cast<Map<String, dynamic>>();
      final meds = (res[1] as List).cast<Map<String, dynamic>>();
      final merged = <_LibraryItem>[
        ...supp.map((r) => _LibraryItem(type: _IntakeType.supplement, row: r)),
        ...meds.map((r) => _LibraryItem(type: _IntakeType.medication, row: r)),
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      setState(() {
        _all = merged;
        _results = merged;
        _loading = false;
      });
      _applyFilter(_q);
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
            .where((r) => r.name.toLowerCase().contains(trimmed))
            .toList(growable: false);
      }
    });
  }

  Future<void> _quickAdd(_IntakeType type) async {
    final name = _q.trim();
    if (name.isEmpty) return;
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      if (type == _IntakeType.supplement) {
        final payload = <String, dynamic>{
          'name': name,
          'user_id': uid,
          if ((_pendingBarcode ?? '').trim().isNotEmpty) 'barcode': _pendingBarcode,
        };
        await _client.from('supplements').insert(payload);
      } else {
        final payload = <String, dynamic>{
          'name': name,
          'user_id': uid,
          if ((_pendingBarcode ?? '').trim().isNotEmpty) 'barcode': _pendingBarcode,
        };
        await _client.from('medications').insert(payload);
      }
      if (!mounted) return;
      _pendingBarcode = null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added "$name" to ${type == _IntakeType.supplement ? 'Supplements' : 'Meds'}')),
      );
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _scanBarcode() async {
    if (_barcodeBusy) return;
    final res = await Navigator.of(context).push<Map<String, dynamic>?>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (res == null || !mounted) return;
    final code = (res['barcode'] ?? '').toString().trim();
    if (code.isEmpty) return;

    setState(() => _barcodeBusy = true);
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;

      _LibraryItem? localHit;

      Future<_LibraryItem?> tryLookupSupplement() async {
        try {
          final data = await _client
              .from('supplements')
              .select('id,name,user_id,daily_dosage,unit_type')
              .eq('barcode', code)
              .limit(1);
          final rows = (data as List).cast<Map<String, dynamic>>();
          if (rows.isEmpty) return null;
          return _LibraryItem(type: _IntakeType.supplement, row: rows.first);
        } catch (_) {
          return null;
        }
      }

      Future<_LibraryItem?> tryLookupMedication() async {
        try {
          final data = await _client
              .from('medications')
              .select('id,name,user_id')
              .eq('barcode', code)
              .limit(1);
          final rows = (data as List).cast<Map<String, dynamic>>();
          if (rows.isEmpty) return null;
          return _LibraryItem(type: _IntakeType.medication, row: rows.first);
        } catch (_) {
          return null;
        }
      }

      localHit = await tryLookupSupplement();
      localHit ??= await tryLookupMedication();

      if (localHit != null) {
        _pendingBarcode = null;
        _controller.text = localHit.name;
        _applyFilter(localHit.name);
        if (!mounted) return;
        await _logFromLibrary(localHit);
        return;
      }

      final off = await OpenFoodFactsService.fetchByBarcode(code);
      if (off != null) {
        final name = (off['name'] ?? '').toString().trim();
        if (name.isNotEmpty) {
          _pendingBarcode = code;
          _controller.text = name;
          _applyFilter(name);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Found "$name". Add it to your library to learn this barcode.')),
          );
          return;
        }
      }

      _pendingBarcode = code;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Product not found. Please enter manually.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _barcodeBusy = false);
    }
  }

  Future<void> _logFromLibrary(_LibraryItem item) async {
    final picked = await showDialog<_LogPick?>(
      context: context,
      builder: (_) => _LogPickDialog(
        title: item.type == _IntakeType.supplement ? 'Log supplement' : 'Log med',
        name: item.name,
        type: item.type,
        amountPrefill: item.type == _IntakeType.supplement ? item.defaultDose : null,
        unitPrefill: item.type == _IntakeType.supplement ? item.defaultUnit : null,
        day: widget.selectedDay,
      ),
    );
    if (picked == null) return;

    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    final nowDay = widget.selectedDay;
    final scheduledLocal = DateTime(
      nowDay.year,
      nowDay.month,
      nowDay.day,
      picked.time.hour,
      picked.time.minute,
    );
    final scheduledIsoUtc = scheduledLocal.toUtc().toIso8601String();
    final takenNow = !picked.planOnly;
    final takenAtIso =
        takenNow ? scheduledLocal.toUtc().toIso8601String() : null;

    DateTime? reminderLocal;
    int? reminderOffsetMinutes;
    if (picked.reminder.enabled) {
      if (picked.reminder.mode == ReminderMode.atConsumptionTime) {
        reminderLocal = scheduledLocal;
        reminderOffsetMinutes = 0;
      } else {
        final off = picked.reminder.offsetMinutes;
        reminderLocal = scheduledLocal.subtract(Duration(minutes: off));
        reminderOffsetMinutes = off;
      }
    }

    if (picked.reminder.enabled) {
      if (!mounted) return;
      await NotificationService.requestPermissionIfNeeded(context);
    }

    if (!mounted) return;
    final notifTitle = context.l10n.notificationTimeForIntake(item.name);
    final notifBody = context.l10n.reminderBody;
    final targetDateStr = supabaseDateOnly(nowDay);

    try {
      if (item.type == _IntakeType.supplement) {
        final payload = <String, dynamic>{
          'user_id': uid,
          'created_at': scheduledIsoUtc,
          'supplement_id': item.id,
          'amount_grams': picked.amount,
          'meal_type': 'SUPPLEMENT',
          'scheduled_at': scheduledIsoUtc,
          'is_taken': takenNow,
          'taken_at': takenAtIso,
          'unit': picked.unit,
          'schedule_block': picked.block,
          'notes': picked.notes,
        };
        if (reminderLocal != null) {
          payload['reminder_at'] = reminderLocal.toUtc().toIso8601String();
          payload['reminder_offset_minutes'] = reminderOffsetMinutes;
        }
        final inserted = await _client
            .from('daily_logs')
            .insert(payload)
            .select('id');
        final rowsIns = (inserted as List).cast<Map<String, dynamic>>();
        final newId = rowsIns.isEmpty
            ? ''
            : (rowsIns.first['id'] ?? '').toString().trim();
        if (reminderLocal != null && newId.isNotEmpty) {
          if (!mounted) return;
          await NotificationService.scheduleByKey(
            key: 'daily_logs:$newId',
            title: notifTitle,
            body: notifBody,
            whenLocal: reminderLocal,
            payload: {
              'item_type': 'supplement',
              'item_id': newId,
              'target_date': targetDateStr,
            },
          );
        }
      } else {
        final payload = <String, dynamic>{
          'user_id': uid,
          'created_at': scheduledIsoUtc,
          'medication_id': item.id,
          'scheduled_at': scheduledIsoUtc,
          'dose_amount': picked.amount,
          'unit_type': picked.unit,
          'notes': picked.notes,
          'schedule_block': picked.block,
          'is_taken': takenNow,
          'taken_at': takenAtIso,
        };
        if (reminderLocal != null) {
          payload['reminder_at'] = reminderLocal.toUtc().toIso8601String();
          payload['reminder_offset_minutes'] = reminderOffsetMinutes;
        }
        final inserted = await _client
            .from('medication_logs')
            .insert(payload)
            .select('id');
        final rowsMed = (inserted as List).cast<Map<String, dynamic>>();
        final newId = rowsMed.isEmpty
            ? ''
            : (rowsMed.first['id'] ?? '').toString().trim();
        if (reminderLocal != null && newId.isNotEmpty) {
          if (!mounted) return;
          await NotificationService.scheduleByKey(
            key: 'medication_logs:$newId',
            title: notifTitle,
            body: notifBody,
            whenLocal: reminderLocal,
            payload: {
              'item_type': 'medication',
              'item_id': newId,
              'target_date': targetDateStr,
            },
          );
        }
      }
      if (!mounted) return;
      widget.onLogged();
      Navigator.of(context).pop(); // close sheet
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(supabaseWriteErrorMessage(e)),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    const gold = Color(0xFFCBAB67);

    final hasResults = _results.isNotEmpty;
    final showQuickAdd = !hasResults && _q.trim().isNotEmpty && !_loading && _error == null;

    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
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
                  tooltip: 'Close',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onChanged: _applyFilter,
                    style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: 'Search supplements + meds...',
                      hintStyle: const TextStyle(
                        color: Color(0xFF757575),
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Scan barcode',
                            onPressed: _scanBarcode,
                            icon: const Icon(Icons.qr_code_scanner),
                            color: gold,
                          ),
                          if (_q.trim().isNotEmpty)
                            IconButton(
                              tooltip: 'Clear',
                              onPressed: () {
                                _controller.clear();
                                _applyFilter('');
                              },
                              icon: const Icon(Icons.clear),
                              color: cyan,
                            ),
                        ],
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
                ),
              ],
            ),
          ),
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
                    : ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          if (showQuickAdd) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(color: const Color(0x3300F3FF)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text(
                                    'Not found?',
                                    style: TextStyle(
                                      color: cyan,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                    onPressed: () => _quickAdd(_IntakeType.supplement),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: cyan,
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.zero,
                                      ),
                                      side: const BorderSide(color: cyan),
                                    ),
                                    icon: const Icon(Icons.eco_outlined),
                                    label: Text('Add "$_q" to Supplements'),
                                  ),
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    onPressed: () => _quickAdd(_IntakeType.medication),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: gold,
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.zero,
                                      ),
                                      side: const BorderSide(color: gold),
                                    ),
                                    icon: const Icon(Icons.medication_liquid_outlined),
                                    label: Text('Add "$_q" to Meds'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          for (final item in _results)
                            ListTile(
                              onTap: () => _logFromLibrary(item),
                              leading: Icon(
                                item.type == _IntakeType.medication
                                    ? Icons.medication_liquid_outlined
                                    : Icons.eco_outlined,
                                color: item.type == _IntakeType.medication ? gold : cyan,
                              ),
                              title: Text(
                                item.name,
                                style: const TextStyle(
                                  color: cyan,
                                  fontFamily: 'monospace',
                                  letterSpacing: 0.5,
                                ),
                              ),
                              trailing: _TagChip(
                                label: item.type == _IntakeType.medication ? 'MED' : 'SUPP',
                                color: item.type == _IntakeType.medication ? gold : cyan,
                              ),
                            ),
                        ],
                      ),
                  ),
        ],
      ),
            if (_barcodeBusy)
              const Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Color(0x66050510)),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LibraryItem {
  final _IntakeType type;
  final Map<String, dynamic> row;

  const _LibraryItem({required this.type, required this.row});

  String get id => (row['id'] ?? '').toString();
  String get name => (row['name'] ?? '').toString();

  double? get defaultDose {
    final v = row['daily_dosage'];
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  String? get defaultUnit {
    final u = (row['unit_type'] ?? '').toString().trim();
    return u.isEmpty ? null : u;
  }
}

class _LogPick {
  final TimeOfDay time;
  final double amount;
  final String unit;
  final String block;
  final String notes;
  /// When true, row is planned only (`is_taken` false) until user taps TAKE.
  final bool planOnly;
  final ReminderState reminder;

  const _LogPick({
    required this.time,
    required this.amount,
    required this.unit,
    required this.block,
    required this.notes,
    required this.planOnly,
    required this.reminder,
  });
}

class _LogPickDialog extends StatefulWidget {
  final String title;
  final String name;
  final _IntakeType type;
  final DateTime day;
  final double? amountPrefill;
  final String? unitPrefill;

  const _LogPickDialog({
    required this.title,
    required this.name,
    required this.type,
    required this.day,
    this.amountPrefill,
    this.unitPrefill,
  });

  @override
  State<_LogPickDialog> createState() => _LogPickDialogState();
}

class _LogPickDialogState extends State<_LogPickDialog> {
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  String _unit = 'pcs';
  String _block = 'MORNING';
  bool _planOnly = false;
  ReminderState _reminder = const ReminderState.disabled();

  static const _blocks = ['MORNING', 'AFTERNOON', 'EVENING', 'NIGHT'];
  static const _suppUnits = ['g', 'mg', 'ml', 'drops', 'capsules', 'pcs'];
  static const _medUnits = ['mg', 'ml', 'pills', 'capsules', 'drops', 'pcs'];

  @override
  void initState() {
    super.initState();
    final a = widget.amountPrefill;
    if (a != null && a > 0) {
      _amount.text =
          a == a.roundToDouble() ? a.toInt().toString() : a.toString();
    }
    final u = (widget.unitPrefill ?? '').trim();
    if (u.isNotEmpty) _unit = u;
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  double _d(String v) => double.tryParse(v.trim().replaceAll(',', '.')) ?? 0.0;

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    const gold = Color(0xFFCBAB67);
    final accent = widget.type == _IntakeType.medication ? gold : cyan;
    final units = widget.type == _IntakeType.medication ? _medUnits : _suppUnits;
    final loc = context.l10n;

    return AlertDialog(
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      title: Text(
        widget.title.toUpperCase(),
        style: TextStyle(color: accent, fontFamily: 'monospace'),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.name,
              style: const TextStyle(
                color: cyan,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment<bool>(
                  value: false,
                  label: Text(
                    loc.intakeAddModeLogNow,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
                ButtonSegment<bool>(
                  value: true,
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
              selected: {_planOnly},
              onSelectionChanged: (s) {
                if (s.isEmpty) return;
                setState(() => _planOnly = s.first);
              },
              style: ButtonStyle(
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return accent;
                  }
                  return cyan;
                }),
                textStyle: WidgetStateProperty.all(
                  const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
                side: WidgetStateProperty.all(
                  BorderSide(color: accent, width: 1),
                ),
                shape: WidgetStateProperty.all(
                  const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                ),
              ),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 6),
            Text(
              loc.intakeAddModeHint,
              style: TextStyle(
                color: accent.withValues(alpha: 0.85),
                fontFamily: 'monospace',
                fontSize: 10,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _time,
                      );
                      if (picked == null) return;
                      if (!mounted) return;
                      setState(() => _time = picked);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                      side: BorderSide(color: accent),
                    ),
                    child: Text(
                      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _block,
                    items: _blocks
                        .map((b) => DropdownMenuItem(
                              value: b,
                              child: Text(b),
                            ))
                        .toList(growable: false),
                    onChanged: (v) => setState(() => _block = v ?? _block),
                    decoration: InputDecoration(
                      labelText: 'Block',
                      labelStyle: TextStyle(color: accent, fontFamily: 'monospace'),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: accent, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: accent, width: 1.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      labelStyle: TextStyle(color: accent, fontFamily: 'monospace'),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: accent, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: accent, width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _unit,
                    items: units
                        .map((u) => DropdownMenuItem(
                              value: u,
                              child: Text(u),
                            ))
                        .toList(growable: false),
                    onChanged: (v) => setState(() => _unit = v ?? _unit),
                    decoration: InputDecoration(
                      labelText: 'Unit',
                      labelStyle: TextStyle(color: accent, fontFamily: 'monospace'),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: accent, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: accent, width: 1.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ReminderSection(
              state: _reminder,
              onChanged: (s) => setState(() => _reminder = s),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              style: const TextStyle(color: cyan, fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: 'Notes (optional)',
                labelStyle: TextStyle(color: accent, fontFamily: 'monospace'),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: accent, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: accent, width: 1.5),
                ),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(loc.cancel.toUpperCase()),
        ),
        TextButton(
          onPressed: () {
            final amt = _d(_amount.text);
            if (amt <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(loc.msgValidAmount)),
              );
              return;
            }
            Navigator.of(context).pop(
              _LogPick(
                time: _time,
                amount: amt,
                unit: _unit,
                block: _block,
                notes: _notes.text.trim(),
                planOnly: _planOnly,
                reminder: _reminder,
              ),
            );
          },
          child: Text(loc.logVerb.toUpperCase()),
        ),
      ],
    );
  }
}

