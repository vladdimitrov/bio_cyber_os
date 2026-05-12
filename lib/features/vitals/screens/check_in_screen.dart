import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bio_cyber_os/l10n/app_localizations.dart';

class CheckInScreen extends StatefulWidget {
  const CheckInScreen({super.key});

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  static const _table = 'symptom_logs';
  static const _dictTable = 'symptom_dictionary';
  final _client = Supabase.instance.client;

  DateTime _selectedDay = DateTime.now();
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _rows = const [];

  DateTime _startOfSelectedDayLocal() {
    final d = _selectedDay;
    return DateTime(d.year, d.month, d.day);
  }

  DateTime _endOfSelectedDayLocal() => _startOfSelectedDayLocal()
      .add(const Duration(days: 1))
      .subtract(const Duration(microseconds: 1));

  String _isoUtc(DateTime dtLocal) => dtLocal.toUtc().toIso8601String();

  String _dayLabel(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        if (!mounted) return;
        setState(() {
          _rows = const [];
          _loading = false;
        });
        return;
      }

      final startIso = _isoUtc(_startOfSelectedDayLocal());
      final endIso = _isoUtc(_endOfSelectedDayLocal());

      final data = await _client
          .from(_table)
          .select()
          .eq('user_id', uid)
          .gte('created_at', startIso)
          .lte('created_at', endIso)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _rows = (data as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rows = const [];
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked == null) return;
    setState(() {
      _selectedDay = DateTime(picked.year, picked.month, picked.day);
    });
    await _fetch();
  }

  Future<void> _shiftDay(int deltaDays) async {
    setState(() => _selectedDay = _selectedDay.add(Duration(days: deltaDays)));
    await _fetch();
  }

  Future<void> _openLogDialog() async {
    final createdAt = _startOfSelectedDayLocal();
    final initialTime = TimeOfDay.now();
    final initialCreatedAtLocal = DateTime(
      createdAt.year,
      createdAt.month,
      createdAt.day,
      initialTime.hour,
      initialTime.minute,
    );

    final res = await showDialog<_FeelLogDraft?>(
      context: context,
      builder: (_) => _CheckInDialog(
        initialCreatedAtLocal: initialCreatedAtLocal,
      ),
    );
    if (res == null) return;

    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        if (!mounted) return;
        final loc = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.msgSignInSave)),
        );
        return;
      }
      final feelName = await _ensureFeelName(res.feelType);
      if (feelName == null) return;
      final payload = res.toUpsertMap(
        userId: uid,
        isoUtc: _isoUtc,
        feelType: feelName,
      );
      await _client.from(_table).insert(payload);
      if (!mounted) return;
      await _fetch();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _openEditDialog(Map<String, dynamic> row) async {
    final id = (row['id'] ?? '').toString().trim();
    if (id.isEmpty) return;

    DateTime createdLocal;
    try {
      createdLocal = DateTime.parse((row['created_at'] ?? '').toString()).toLocal();
    } catch (_) {
      createdLocal = DateTime.now();
    }

    String asText(dynamic v) => (v ?? '').toString().trim();
    double? asDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    int? asInt(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    final existing = _FeelLogDraft(
      id: id,
      createdAtLocal: createdLocal,
      bodyTemp: asDouble(row['body_temp']),
      heartRate: asInt(row['heart_rate']),
      bpSystolic: asInt(row['bp_systolic']),
      bpDiastolic: asInt(row['bp_diastolic']),
      spo2: asInt(row['spo2']),
      glucose: asDouble(row['glucose']),
      feelType: asText(row['symptom_type']),
      intensity: asInt(row['intensity']),
      notes: asText(row['notes']),
    );

    final res = await showDialog<_FeelLogDraft?>(
      context: context,
      builder: (_) => _CheckInDialog(
        initialCreatedAtLocal: existing.createdAtLocal,
        initialDraft: existing,
      ),
    );
    if (res == null) return;

    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        if (!mounted) return;
        final loc = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.msgSignInSave)),
        );
        return;
      }
      final feelName = await _ensureFeelName(res.feelType);
      if (feelName == null) return;
      final payload = res.toUpsertMap(
        userId: uid,
        isoUtc: _isoUtc,
        feelType: feelName,
      );
      await _client.from(_table).update(payload).eq('id', id).eq('user_id', uid);
      if (!mounted) return;
      await _fetch();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<String?> _ensureFeelName(String raw) async {
    final name = raw.trim();
    if (name.isEmpty) return null;
    try {
      await _client.from(_dictTable).insert({'name': name});
      return name;
    } catch (e) {
      if (e is PostgrestException && e.code == '23505') {
        return name; // already exists
      }
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
      return null;
    }
  }

  Future<void> _deleteWithUndo(Map<String, dynamic> row) async {
    final id = (row['id'] ?? '').toString().trim();
    if (id.isEmpty || !mounted) return;
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    final messenger = ScaffoldMessenger.of(context);

    final idx = _rows.indexWhere((r) => (r['id'] ?? '').toString().trim() == id);
    if (idx < 0) return;
    final removed = row;

    setState(() {
      final next = _rows.toList(growable: true);
      next.removeAt(idx);
      _rows = next;
    });

    var undone = false;
    final loc = AppLocalizations.of(context)!;
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text(loc.msgLogDeleted),
        action: SnackBarAction(
          label: loc.snackUndo,
          onPressed: () {
            undone = true;
            if (!mounted) return;
            setState(() {
              final next = _rows.toList(growable: true);
              final insertAt = idx.clamp(0, next.length);
              next.insert(insertAt, removed);
              _rows = next;
            });
          },
        ),
      ),
    );

    final reason = await controller.closed;
    if (!mounted) return;
    if (undone || reason == SnackBarClosedReason.action) return;

    try {
      await _client.from(_table).delete().eq('id', id).eq('user_id', uid);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final next = _rows.toList(growable: true);
        final insertAt = idx.clamp(0, next.length);
        next.insert(insertAt, removed);
        _rows = next;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.redAccent,
          showCloseIcon: true,
        ),
      );
    }
  }

  String _fmtTime(dynamic isoLike) {
    final s = (isoLike ?? '').toString();
    final dt = DateTime.tryParse(s);
    if (dt == null) return '--:--';
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _fmtBp(Map<String, dynamic> row) {
    final sys = row['bp_systolic'];
    final dia = row['bp_diastolic'];
    final s = sys is num ? sys.toInt() : int.tryParse((sys ?? '').toString());
    final d = dia is num ? dia.toInt() : int.tryParse((dia ?? '').toString());
    if (s == null && d == null) return '';
    return '${s ?? '--'}/${d ?? '--'}';
  }

  String _nonEmpty(dynamic v) => (v ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    const ruby = Color(0xFFE91E63);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(l10n.checkInTitle),
        actions: [
          IconButton(
            onPressed: _fetch,
            tooltip: l10n.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'check_in_fab',
        onPressed: _openLogDialog,
        backgroundColor: cyan,
        foregroundColor: Colors.black,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => _shiftDay(-1),
                    icon: const Icon(Icons.chevron_left),
                    color: cyan,
                    tooltip: 'Previous day',
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
                    tooltip: 'Next day',
                  ),
                ],
              ),
            ),
          ),
          Expanded(
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
                    : _rows.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                l10n.checkInNoLogsToday,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0x8800F3FF),
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                            itemCount: _rows.length,
                            itemBuilder: (context, index) {
                              final row = _rows[index];
                              final time = _fmtTime(row['created_at']);

                              final temp = row['body_temp'];
                              final hr = row['heart_rate'];
                              final spo2 = row['spo2'];
                              final glucose = row['glucose'];
                              final bp = _fmtBp(row);

                              String? fmtNum(dynamic v,
                                  {int? decimals, String suffix = ''}) {
                                if (v == null) return null;
                                final n = v is num
                                    ? v.toDouble()
                                    : double.tryParse(v.toString());
                                if (n == null) return null;
                                final t = decimals == null
                                    ? n.toString()
                                    : n.toStringAsFixed(decimals);
                                return '$t$suffix';
                              }

                              final vitalsParts = <String>[
                                if (fmtNum(temp, decimals: 1, suffix: '°C') !=
                                    null)
                                  'Temp ${fmtNum(temp, decimals: 1, suffix: '°C')}',
                                if (hr != null)
                                  'Pulse ${(hr is num ? hr.toInt() : hr).toString()} BPM',
                                if (bp.isNotEmpty) 'BP $bp',
                                if (spo2 != null)
                                  'SpO2 ${(spo2 is num ? spo2.toInt() : spo2).toString()}%',
                                if (fmtNum(glucose, decimals: 1, suffix: '') !=
                                    null)
                                  'Glu ${fmtNum(glucose, decimals: 1)}',
                              ];

                              final feelLabel = _nonEmpty(row['symptom_type']);
                              final intensity = row['intensity'];
                              final intensityInt = intensity is num
                                  ? intensity.toInt()
                                  : int.tryParse((intensity ?? '').toString());
                              final feelLine = feelLabel.isNotEmpty
                                  ? (intensityInt != null
                                      ? '$feelLabel — $intensityInt/10'
                                      : feelLabel)
                                  : '';

                              final notes = _nonEmpty(row['notes']);
                              final id = (row['id'] ?? '').toString();

                              final tile = InkWell(
                                onTap: () => _openEditDialog(row),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: bg,
                                    border: Border.all(color: cyan, width: 1),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x2200F3FF),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child: DefaultTextStyle(
                                    style: const TextStyle(
                                      color: cyan,
                                      fontFamily: 'monospace',
                                      letterSpacing: 0.4,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              time,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 1.0,
                                              ),
                                            ),
                                            const Spacer(),
                                            IconButton(
                                              tooltip: l10n.edit,
                                              onPressed: () =>
                                                  _openEditDialog(row),
                                              constraints:
                                                  const BoxConstraints.tightFor(
                                                width: 36,
                                                height: 36,
                                              ),
                                              padding: EdgeInsets.zero,
                                              icon: const Icon(
                                                Icons.edit_outlined,
                                                size: 20,
                                                color: cyan,
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: id.isEmpty
                                                  ? null
                                                  : () => _deleteWithUndo(row),
                                              icon: Icon(
                                                Icons.delete_outline,
                                                color: ruby.withValues(alpha: 0.85),
                                              ),
                                              tooltip: l10n.delete,
                                              constraints:
                                                  const BoxConstraints.tightFor(
                                                width: 36,
                                                height: 36,
                                              ),
                                              padding: EdgeInsets.zero,
                                            ),
                                          ],
                                        ),
                                        if (vitalsParts.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            vitalsParts.join('  ·  '),
                                            style: const TextStyle(
                                              color: Color(0xAA00F3FF),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                        if (feelLine.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            feelLine,
                                            style: const TextStyle(
                                              color: cyan,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.6,
                                            ),
                                          ),
                                        ],
                                        if (notes.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            notes,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              );

                              if (id.isEmpty) return tile;

                              return Dismissible(
                                key: ValueKey('check_in_log:$id'),
                                direction: DismissDirection.endToStart,
                                confirmDismiss: (_) async {
                                  // Always allow swipe; actual delete is delayed with UNDO.
                                  return true;
                                },
                                onDismissed: (_) {
                                  _deleteWithUndo(row);
                                },
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: ruby.withValues(alpha: 0.15),
                                    border: Border.all(
                                      color: ruby.withValues(alpha: 0.5),
                                      width: 1,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.delete_outline,
                                    color: Color(0xFFE91E63),
                                  ),
                                ),
                                child: tile,
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _FeelLogDraft {
  final String? id;
  final DateTime createdAtLocal;
  final double? bodyTemp;
  final int? heartRate;
  final int? bpSystolic;
  final int? bpDiastolic;
  final int? spo2;
  final double? glucose;
  final String feelType;
  final int? intensity;
  final String notes;

  const _FeelLogDraft({
    this.id,
    required this.createdAtLocal,
    required this.bodyTemp,
    required this.heartRate,
    required this.bpSystolic,
    required this.bpDiastolic,
    required this.spo2,
    required this.glucose,
    required this.feelType,
    required this.intensity,
    required this.notes,
  });

  Map<String, dynamic> toUpsertMap({
    required String userId,
    required String Function(DateTime) isoUtc,
    required String feelType,
  }) {
    final map = <String, dynamic>{
      'user_id': userId,
      'created_at': isoUtc(createdAtLocal),
    };
    if (bodyTemp != null) map['body_temp'] = bodyTemp;
    if (heartRate != null) map['heart_rate'] = heartRate;
    if (bpSystolic != null) map['bp_systolic'] = bpSystolic;
    if (bpDiastolic != null) map['bp_diastolic'] = bpDiastolic;
    if (spo2 != null) map['spo2'] = spo2;
    if (glucose != null) map['glucose'] = glucose;
    if (feelType.trim().isNotEmpty) map['symptom_type'] = feelType.trim();
    if (intensity != null) map['intensity'] = intensity;
    if (notes.trim().isNotEmpty) map['notes'] = notes.trim();
    return map;
  }
}

class _CheckInDialog extends StatefulWidget {
  final DateTime initialCreatedAtLocal;
  final _FeelLogDraft? initialDraft;

  const _CheckInDialog({
    required this.initialCreatedAtLocal,
    this.initialDraft,
  });

  @override
  State<_CheckInDialog> createState() =>
      _CheckInDialogState();
}

class _CheckInDialogState extends State<_CheckInDialog> {
  static const _addNewSentinel = '__ADD_NEW_FEEL__';
  static const List<String> _energyEmojis = ['😫', '😐', '🙂', '😄'];
  static const List<String> _moodEmojis = ['😢', '😕', '😊', '🤩'];

  final _client = Supabase.instance.client;

  late DateTime _createdAtLocal;

  final _tempCtrl = TextEditingController();
  final _pulseCtrl = TextEditingController();
  final _bpCtrl = TextEditingController();
  final _spo2Ctrl = TextEditingController();
  final _sleepHoursCtrl = TextEditingController();

  bool _loadingFeelTypes = true;
  Object? _feelLoadError;
  List<String> _feelTypes = const [];
  String? _selectedFeelType;
  double _intensity = 5;
  final _notesCtrl = TextEditingController();

  /// When false, only Energy / Mood / Sleep are shown up top; measurements live in [ExpansionTile].
  bool _showAdvancedMeasurements = false;

  int? _energyEmojiIdx;
  int? _moodEmojiIdx;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _createdAtLocal = widget.initialCreatedAtLocal;
    final d = widget.initialDraft;
    if (d != null) {
      if (d.bodyTemp != null) {
        _tempCtrl.text = d.bodyTemp!.toStringAsFixed(1);
      }
      if (d.heartRate != null) _pulseCtrl.text = d.heartRate.toString();
      final sys = d.bpSystolic;
      final dia = d.bpDiastolic;
      if (sys != null || dia != null) {
        _bpCtrl.text = '${sys ?? ''}${(dia != null) ? '/$dia' : ''}';
      }
      if (d.spo2 != null) _spo2Ctrl.text = d.spo2.toString();
      _notesCtrl.text = d.notes;
      if (d.intensity != null) {
        _intensity = d.intensity!.toDouble();
        final ie = d.intensity!;
        if (ie <= 4) {
          _energyEmojiIdx = 1;
        } else if (ie <= 6) {
          _energyEmojiIdx = 2;
        } else if (ie <= 8) {
          _energyEmojiIdx = 3;
        } else {
          _energyEmojiIdx = 4;
        }
      }
      if (d.feelType.trim().isNotEmpty) {
        _selectedFeelType = d.feelType.trim();
      }
      final hasMeasurements = d.bodyTemp != null ||
          d.heartRate != null ||
          d.bpSystolic != null ||
          d.bpDiastolic != null ||
          d.spo2 != null ||
          d.glucose != null;
      if (hasMeasurements) _showAdvancedMeasurements = true;
    }
    _loadFeelDictionary();
  }

  Future<void> _loadFeelDictionary() async {
    setState(() {
      _loadingFeelTypes = true;
      _feelLoadError = null;
    });
    try {
      final data =
          await _client.from('symptom_dictionary').select('name').order('name');
      final rows = (data as List).cast<Map<String, dynamic>>();
      final names = rows
          .map((r) => (r['name'] ?? '').toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
      names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      const canonicalDefault = 'Check-in';
      if (!names.any(
            (e) => e.toLowerCase() == canonicalDefault.toLowerCase(),
          )) {
        names.insert(0, canonicalDefault);
      }

      final current = (_selectedFeelType ?? '').trim();
      if (current.isNotEmpty &&
          !names.any((e) => e.toLowerCase() == current.toLowerCase())) {
        names.insert(0, current);
      }

      if (!mounted) return;
      setState(() {
        _feelTypes = names;
        _selectedFeelType ??= canonicalDefault;
        _loadingFeelTypes = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _feelLoadError = e;
        _feelTypes = const [];
        _loadingFeelTypes = false;
      });
    }
  }

  Future<void> _addNewFeelFlow() async {
    final loc = AppLocalizations.of(context)!;
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    final ctrl = TextEditingController();
    final name = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: bg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(
          loc.addFeelTagTitle,
          style: const TextStyle(color: cyan, fontFamily: 'monospace'),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: cyan, fontFamily: 'monospace'),
          decoration: InputDecoration(
            labelText: loc.feelTagNameLabel,
            labelStyle: const TextStyle(color: cyan, fontFamily: 'monospace'),
            enabledBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: cyan, width: 1),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: cyan, width: 1.5),
            ),
          ),
          onSubmitted: (_) => Navigator.of(context).pop(ctrl.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(loc.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
            child: Text(loc.save),
          ),
        ],
      ),
    );
    final trimmed = (name ?? '').trim();
    if (trimmed.isEmpty || !mounted) return;
    setState(() {
      _feelTypes = [
        trimmed,
        ..._feelTypes.where((e) => e.toLowerCase() != trimmed.toLowerCase()),
      ];
      _selectedFeelType = trimmed;
    });
  }

  @override
  void dispose() {
    _tempCtrl.dispose();
    _pulseCtrl.dispose();
    _bpCtrl.dispose();
    _spo2Ctrl.dispose();
    _sleepHoursCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  int? _tryInt(String raw) => int.tryParse(raw.trim());
  double? _tryDouble(String raw) =>
      double.tryParse(raw.trim().replaceAll(',', '.'));

  (int? sys, int? dia) _parseBp(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return (null, null);
    final parts = t.split(RegExp(r'[/\\\s]+')).where((x) => x.isNotEmpty).toList();
    if (parts.isEmpty) return (null, null);
    if (parts.length == 1) return (_tryInt(parts[0]), null);
    return (_tryInt(parts[0]), _tryInt(parts[1]));
  }

  Future<void> _pickTime() async {
    final now = TimeOfDay.fromDateTime(_createdAtLocal);
    final picked = await showTimePicker(context: context, initialTime: now);
    if (picked == null) return;
    setState(() {
      _createdAtLocal = DateTime(
        _createdAtLocal.year,
        _createdAtLocal.month,
        _createdAtLocal.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  int _intensityFromEnergyEmoji() {
    switch (_energyEmojiIdx) {
      case 1:
        return 3;
      case 2:
        return 5;
      case 3:
        return 7;
      case 4:
        return 9;
      default:
        return _intensity.round().clamp(1, 10);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final loc = AppLocalizations.of(context)!;
      final bodyTemp = _tryDouble(_tempCtrl.text);
      final pulse = _tryInt(_pulseCtrl.text);
      final bp = _parseBp(_bpCtrl.text);
      final spo2 = _tryInt(_spo2Ctrl.text);

      final clampedIntensity = _intensityFromEnergyEmoji();

      final defaultTag = loc.checkInDefaultTag;
      final tagTrim = (_selectedFeelType ?? '').trim();
      final feelOut = tagTrim.isEmpty ? defaultTag : tagTrim;

      final extra = <String>[];
      if (_moodEmojiIdx != null) {
        extra.add(loc.moodLineShort(_moodEmojiIdx!));
      }
      final sleep = _sleepHoursCtrl.text.trim();
      if (sleep.isNotEmpty) {
        extra.add(loc.sleepLineShort(sleep));
      }
      var notesOut = _notesCtrl.text.trim();
      if (extra.isNotEmpty) {
        final prefix = extra.join('\n');
        notesOut = notesOut.isEmpty ? prefix : '$prefix\n$notesOut';
      }

      final draft = _FeelLogDraft(
        id: widget.initialDraft?.id,
        createdAtLocal: _createdAtLocal,
        bodyTemp: bodyTemp,
        heartRate: pulse,
        bpSystolic: bp.$1,
        bpDiastolic: bp.$2,
        spo2: spo2,
        glucose: null,
        feelType: feelOut,
        intensity: clampedIntensity,
        notes: notesOut,
      );

      if (!mounted) return;
      Navigator.of(context).pop(draft);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _dec(String label) {
    const cyan = Color(0xFF00F3FF);
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: cyan, fontFamily: 'monospace'),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: cyan, width: 1),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: cyan, width: 1.5),
      ),
    );
  }

  Widget _emojiRow({
    required String title,
    required List<String> emojis,
    required int? selected,
    required ValueChanged<int> onPick,
  }) {
    const cyan = Color(0xFF00F3FF);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: cyan.withValues(alpha: 0.9),
            fontFamily: 'monospace',
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(emojis.length, (i) {
            final idx = i + 1;
            final on = selected == idx;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Material(
                  color: on ? const Color(0x2200F3FF) : Colors.transparent,
                  child: InkWell(
                    onTap: () => setState(() => onPick(idx)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        emojis[i],
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 28),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    final loc = AppLocalizations.of(context)!;

    final timeLabel =
        '${_createdAtLocal.hour.toString().padLeft(2, '0')}:${_createdAtLocal.minute.toString().padLeft(2, '0')}';

    return AlertDialog(
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      title: Text(
        loc.checkInDialogTitle,
        style: const TextStyle(color: cyan, fontFamily: 'monospace'),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _pickTime,
                style: OutlinedButton.styleFrom(
                  foregroundColor: cyan,
                  side: const BorderSide(color: cyan, width: 1),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                icon: const Icon(Icons.schedule),
                label: Text(
                  loc.timeAt(timeLabel),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _emojiRow(
                title: loc.energyLabel,
                emojis: _energyEmojis,
                selected: _energyEmojiIdx,
                onPick: (i) => setState(() => _energyEmojiIdx = i),
              ),
              const SizedBox(height: 14),
              _emojiRow(
                title: loc.moodLabel,
                emojis: _moodEmojis,
                selected: _moodEmojiIdx,
                onPick: (i) => setState(() => _moodEmojiIdx = i),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _sleepHoursCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                decoration: _dec(loc.sleepHoursLabel),
              ),
              const SizedBox(height: 12),
              ExpansionTile(
                initiallyExpanded: _showAdvancedMeasurements,
                onExpansionChanged: (open) =>
                    setState(() => _showAdvancedMeasurements = open),
                tilePadding: EdgeInsets.zero,
                title: Text(
                  loc.advancedMeasurementsTitle,
                  style: TextStyle(
                    color: cyan.withValues(alpha: 0.95),
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 1.0,
                  ),
                ),
                children: [
                  TextField(
                    controller: _tempCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                    decoration: _dec(loc.bodyTempLabel),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _pulseCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                    decoration: _dec(loc.pulseLabel),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _bpCtrl,
                    keyboardType: TextInputType.text,
                    style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                    decoration: _dec(loc.bpLabel),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _spo2Ctrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                    decoration: _dec(loc.spo2Label),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  loc.moreOptionsTitle,
                  style: TextStyle(
                    color: cyan.withValues(alpha: 0.95),
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 1.0,
                  ),
                ),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _loadingFeelTypes
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: LinearProgressIndicator(),
                              )
                            : DropdownButtonFormField<String>(
                                key: ValueKey(
                                  '${_feelTypes.join()}|${_selectedFeelType ?? ''}',
                                ),
                                initialValue: _selectedFeelType,
                                dropdownColor: bg,
                                decoration: _dec(loc.feelTagLabel),
                                items: [
                                  ..._feelTypes.map(
                                    (t) => DropdownMenuItem(
                                      value: t,
                                      child: Text(
                                        t,
                                        style: const TextStyle(
                                          color: cyan,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: _addNewSentinel,
                                    child: Text(
                                      loc.addFeelTagListItem,
                                      style: const TextStyle(
                                        color: Color(0xFF88CCFF),
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (v) async {
                                  if (v == null) return;
                                  if (v == _addNewSentinel) {
                                    await _addNewFeelFlow();
                                    return;
                                  }
                                  if (!mounted) return;
                                  setState(() {
                                    _selectedFeelType = v;
                                    _showAdvancedMeasurements = true;
                                  });
                                },
                              ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        tooltip: loc.addFeelTagTooltip,
                        onPressed:
                            _loadingFeelTypes ? null : _addNewFeelFlow,
                        icon: const Icon(Icons.add, color: cyan),
                      ),
                    ],
                  ),
                  if (_feelLoadError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      loc.failedFeelList(_feelLoadError.toString()),
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton(
                      onPressed: _loadFeelDictionary,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cyan,
                        side: const BorderSide(color: cyan, width: 1),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                      ),
                      child: Text(
                        loc.refresh,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        loc.intensityLabel,
                        style: const TextStyle(
                          color: Color(0x8800F3FF),
                          fontFamily: 'monospace',
                          letterSpacing: 0.6,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_intensity.round()}/10',
                        style: const TextStyle(
                          color: cyan,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _intensity,
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: _intensity.round().toString(),
                    activeColor: cyan,
                    inactiveColor: const Color(0x3300F3FF),
                    onChanged: (v) => setState(() => _intensity = v),
                  ),
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 3,
                    style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                    decoration: _dec(loc.notes),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(null),
          child: Text(loc.cancel),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: Text(loc.save),
        ),
      ],
    );
  }
}

