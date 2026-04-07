import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bio_cyber_os/l10n/app_localizations.dart';

class SymptomLogScreen extends StatefulWidget {
  const SymptomLogScreen({super.key});

  @override
  State<SymptomLogScreen> createState() => _SymptomLogScreenState();
}

class _SymptomLogScreenState extends State<SymptomLogScreen> {
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
      final startIso = _isoUtc(_startOfSelectedDayLocal());
      final endIso = _isoUtc(_endOfSelectedDayLocal());

      final data = await _client
          .from(_table)
          .select()
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

    final res = await showDialog<_SymptomLogDraft?>(
      context: context,
      builder: (_) => _LogVitalsSymptomsDialog(
        initialCreatedAtLocal: initialCreatedAtLocal,
      ),
    );
    if (res == null) return;

    try {
      final symptomName = await _ensureSymptomName(res.symptomType);
      if (symptomName == null) return;
      final payload = res.toUpsertMap(isoUtc: _isoUtc, symptomType: symptomName);
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

    final existing = _SymptomLogDraft(
      id: id,
      createdAtLocal: createdLocal,
      bodyTemp: asDouble(row['body_temp']),
      heartRate: asInt(row['heart_rate']),
      bpSystolic: asInt(row['bp_systolic']),
      bpDiastolic: asInt(row['bp_diastolic']),
      spo2: asInt(row['spo2']),
      glucose: asDouble(row['glucose']),
      symptomType: asText(row['symptom_type']),
      intensity: asInt(row['intensity']),
      notes: asText(row['notes']),
    );

    final res = await showDialog<_SymptomLogDraft?>(
      context: context,
      builder: (_) => _LogVitalsSymptomsDialog(
        initialCreatedAtLocal: existing.createdAtLocal,
        initialDraft: existing,
      ),
    );
    if (res == null) return;

    try {
      final symptomName = await _ensureSymptomName(res.symptomType);
      if (symptomName == null) return;
      final payload = res.toUpsertMap(isoUtc: _isoUtc, symptomType: symptomName);
      await _client.from(_table).update(payload).eq('id', id);
      if (!mounted) return;
      await _fetch();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<String?> _ensureSymptomName(String raw) async {
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

  Future<void> _deleteRow(String id) async {
    try {
      await _client.from(_table).delete().eq('id', id);
      await _fetch();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
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
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(l10n.screenVitalsSymptoms),
        actions: [
          IconButton(
            onPressed: _fetch,
            tooltip: l10n.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'vitals_fab',
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
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: Text(
                                'No logs yet today. Tap + to add.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
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

                              final symptomType = _nonEmpty(row['symptom_type']);
                              final intensity = row['intensity'];
                              final intensityInt = intensity is num
                                  ? intensity.toInt()
                                  : int.tryParse((intensity ?? '').toString());
                              final symptomLine = symptomType.isNotEmpty
                                  ? (intensityInt != null
                                      ? '$symptomType — $intensityInt/10'
                                      : symptomType)
                                  : '';

                              final notes = _nonEmpty(row['notes']);
                              final id = (row['id'] ?? '').toString();

                              return InkWell(
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
                                              onPressed: id.isEmpty
                                                  ? null
                                                  : () => _deleteRow(id),
                                              icon: const Icon(
                                                Icons.delete_outline,
                                                color: cyan,
                                              ),
                                              tooltip: 'Delete',
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
                                        if (symptomLine.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            symptomLine,
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
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _SymptomLogDraft {
  final String? id;
  final DateTime createdAtLocal;
  final double? bodyTemp;
  final int? heartRate;
  final int? bpSystolic;
  final int? bpDiastolic;
  final int? spo2;
  final double? glucose;
  final String symptomType;
  final int? intensity;
  final String notes;

  const _SymptomLogDraft({
    this.id,
    required this.createdAtLocal,
    required this.bodyTemp,
    required this.heartRate,
    required this.bpSystolic,
    required this.bpDiastolic,
    required this.spo2,
    required this.glucose,
    required this.symptomType,
    required this.intensity,
    required this.notes,
  });

  Map<String, dynamic> toUpsertMap({
    required String Function(DateTime) isoUtc,
    required String symptomType,
  }) {
    final map = <String, dynamic>{
      'created_at': isoUtc(createdAtLocal),
    };
    if (bodyTemp != null) map['body_temp'] = bodyTemp;
    if (heartRate != null) map['heart_rate'] = heartRate;
    if (bpSystolic != null) map['bp_systolic'] = bpSystolic;
    if (bpDiastolic != null) map['bp_diastolic'] = bpDiastolic;
    if (spo2 != null) map['spo2'] = spo2;
    if (glucose != null) map['glucose'] = glucose;
    if (symptomType.trim().isNotEmpty) map['symptom_type'] = symptomType.trim();
    if (intensity != null) map['intensity'] = intensity;
    if (notes.trim().isNotEmpty) map['notes'] = notes.trim();
    return map;
  }
}

class _LogVitalsSymptomsDialog extends StatefulWidget {
  final DateTime initialCreatedAtLocal;
  final _SymptomLogDraft? initialDraft;

  const _LogVitalsSymptomsDialog({
    required this.initialCreatedAtLocal,
    this.initialDraft,
  });

  @override
  State<_LogVitalsSymptomsDialog> createState() =>
      _LogVitalsSymptomsDialogState();
}

class _LogVitalsSymptomsDialogState extends State<_LogVitalsSymptomsDialog> {
  static const _addNewSentinel = '__ADD_NEW_SYMPTOM__';
  final _client = Supabase.instance.client;

  late DateTime _createdAtLocal;

  final _tempCtrl = TextEditingController();
  final _pulseCtrl = TextEditingController();
  final _bpCtrl = TextEditingController();
  final _spo2Ctrl = TextEditingController();

  bool _loadingSymptoms = true;
  Object? _symptomLoadError;
  List<String> _symptomTypes = const [];
  String? _symptomType;
  double _intensity = 5;
  final _notesCtrl = TextEditingController();

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
      if (d.intensity != null) _intensity = d.intensity!.toDouble();
      if (d.symptomType.trim().isNotEmpty) _symptomType = d.symptomType.trim();
    }
    _loadSymptomDictionary();
  }

  Future<void> _loadSymptomDictionary() async {
    setState(() {
      _loadingSymptoms = true;
      _symptomLoadError = null;
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

      // Ensure currently selected symptom exists in list (edit mode / legacy rows).
      final current = (_symptomType ?? '').trim();
      if (current.isNotEmpty &&
          !names.any((e) => e.toLowerCase() == current.toLowerCase())) {
        names.insert(0, current);
      }

      if (!mounted) return;
      setState(() {
        _symptomTypes = names;
        _symptomType ??= _symptomTypes.isNotEmpty ? _symptomTypes.first : null;
        _loadingSymptoms = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _symptomLoadError = e;
        _symptomTypes = const [];
        _loadingSymptoms = false;
      });
    }
  }

  Future<void> _addNewSymptomFlow() async {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    final ctrl = TextEditingController();
    final name = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: bg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Text(
          'ADD NEW SYMPTOM',
          style: TextStyle(color: cyan, fontFamily: 'monospace'),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: cyan, fontFamily: 'monospace'),
          decoration: const InputDecoration(
            labelText: 'Name',
            labelStyle: TextStyle(color: cyan, fontFamily: 'monospace'),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: cyan, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: cyan, width: 1.5),
            ),
          ),
          onSubmitted: (_) => Navigator.of(context).pop(ctrl.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
            child: const Text('ADD'),
          ),
        ],
      ),
    );
    final trimmed = (name ?? '').trim();
    if (trimmed.isEmpty || !mounted) return;
    setState(() {
      _symptomTypes = [
        trimmed,
        ..._symptomTypes.where((e) => e.toLowerCase() != trimmed.toLowerCase()),
      ];
      _symptomType = trimmed;
    });
  }

  @override
  void dispose() {
    _tempCtrl.dispose();
    _pulseCtrl.dispose();
    _bpCtrl.dispose();
    _spo2Ctrl.dispose();
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

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bodyTemp = _tryDouble(_tempCtrl.text);
      final pulse = _tryInt(_pulseCtrl.text);
      final bp = _parseBp(_bpCtrl.text);
      final spo2 = _tryInt(_spo2Ctrl.text);

      final clampedIntensity = _intensity.round().clamp(1, 10);

      final sym = (_symptomType ?? '').trim();
      final draft = _SymptomLogDraft(
        id: widget.initialDraft?.id,
        createdAtLocal: _createdAtLocal,
        bodyTemp: bodyTemp,
        heartRate: pulse,
        bpSystolic: bp.$1,
        bpDiastolic: bp.$2,
        spo2: spo2,
        glucose: null,
        symptomType: sym,
        intensity: clampedIntensity,
        notes: _notesCtrl.text,
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

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);

    final timeLabel =
        '${_createdAtLocal.hour.toString().padLeft(2, '0')}:${_createdAtLocal.minute.toString().padLeft(2, '0')}';

    return AlertDialog(
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      title: const Text(
        'LOG VITALS & SYMPTOMS',
        style: TextStyle(color: cyan, fontFamily: 'monospace'),
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
                  'TIME  $timeLabel',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'PHYSICAL VITALS',
                style: TextStyle(
                  color: cyan.withValues(alpha: 0.9),
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _tempCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                decoration: _dec('Temp (°C)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _pulseCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                decoration: _dec('Pulse (BPM)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _bpCtrl,
                keyboardType: TextInputType.text,
                style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                decoration: _dec('BP (120/80)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _spo2Ctrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                decoration: _dec('SpO2 (%)'),
              ),
              const SizedBox(height: 18),
              Text(
                'SYMPTOMS',
                style: TextStyle(
                  color: cyan.withValues(alpha: 0.9),
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _loadingSymptoms
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: LinearProgressIndicator(),
                          )
                        : DropdownButtonFormField<String>(
                            initialValue: _symptomType,
                            dropdownColor: bg,
                            decoration: _dec('Symptom type'),
                            items: [
                              ..._symptomTypes.map(
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
                              const DropdownMenuItem(
                                value: _addNewSentinel,
                                child: Text(
                                  '+ Add New Symptom',
                                  style: TextStyle(
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
                                await _addNewSymptomFlow();
                                return;
                              }
                              if (!mounted) return;
                              setState(() => _symptomType = v);
                            },
                          ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    tooltip: 'Add new symptom',
                    onPressed: _loadingSymptoms ? null : _addNewSymptomFlow,
                    icon: const Icon(Icons.add, color: cyan),
                  ),
                ],
              ),
              if (_symptomLoadError != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Failed to load symptom list: ${_symptomLoadError.toString()}',
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 6),
                OutlinedButton(
                  onPressed: _loadSymptomDictionary,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cyan,
                    side: const BorderSide(color: cyan, width: 1),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                  child: const Text(
                    'RETRY LOAD',
                    style: TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text(
                    'Intensity',
                    style: TextStyle(
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
              const SizedBox(height: 10),
              TextField(
                controller: _notesCtrl,
                maxLines: 3,
                style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                decoration: _dec('Notes'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(null),
          child: const Text('CANCEL'),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: const Text('SAVE'),
        ),
      ],
    );
  }
}

