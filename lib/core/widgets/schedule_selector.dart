import 'package:flutter/material.dart';

/// Immutable set of selections emitted by [ScheduleSelector].
///
/// Combines three independent scheduling methods in a single model so
/// logging dialogs can collect them with one widget and persist them with
/// one bulk insert:
/// 1. [consecutiveDays] — number of sequential days starting from a base
///    date (a simple multiplier).
/// 2. [weekdays] — ISO weekdays (1=Mon .. 7=Sun) to repeat on over the
///    next 4 weeks from the base date.
/// 3. [specificDates] — exact calendar dates (date-only, local) picked
///    individually from a calendar.
class ScheduleSelection {
  final int consecutiveDays;
  final Set<int> weekdays;
  final Set<DateTime> specificDates;

  const ScheduleSelection({
    this.consecutiveDays = 1,
    this.weekdays = const <int>{},
    this.specificDates = const <DateTime>{},
  });

  ScheduleSelection copyWith({
    int? consecutiveDays,
    Set<int>? weekdays,
    Set<DateTime>? specificDates,
  }) {
    return ScheduleSelection(
      consecutiveDays: consecutiveDays ?? this.consecutiveDays,
      weekdays: weekdays ?? this.weekdays,
      specificDates: specificDates ?? this.specificDates,
    );
  }

  /// Union of all three methods, deduped + sorted. Falls back to
  /// `[baseDate]` when nothing is selected so callers always get at least
  /// one record to insert.
  List<DateTime> resolveDates(DateTime baseDate) {
    final base = _dateOnly(baseDate);
    final out = <DateTime>{};

    final n = consecutiveDays.clamp(0, 365);
    for (var i = 0; i < n; i++) {
      out.add(base.add(Duration(days: i)));
    }

    if (weekdays.isNotEmpty) {
      for (var i = 0; i < 28; i++) {
        final d = base.add(Duration(days: i));
        if (weekdays.contains(d.weekday)) out.add(d);
      }
    }

    for (final d in specificDates) {
      out.add(_dateOnly(d));
    }

    if (out.isEmpty) out.add(base);
    final list = out.toList()..sort();
    return list;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

/// Compact widget that lets the user compose a [ScheduleSelection] via:
/// a "Number of days" field, 7 weekday checkboxes, and a multi-date
/// calendar picker. Controlled: parent owns the [selection] and receives
/// updates through [onChanged].
class ScheduleSelector extends StatefulWidget {
  final ScheduleSelection selection;
  final ValueChanged<ScheduleSelection> onChanged;
  final DateTime baseDate;

  const ScheduleSelector({
    super.key,
    required this.selection,
    required this.onChanged,
    required this.baseDate,
  });

  @override
  State<ScheduleSelector> createState() => _ScheduleSelectorState();
}

class _ScheduleSelectorState extends State<ScheduleSelector> {
  late final TextEditingController _daysCtrl;

  @override
  void initState() {
    super.initState();
    _daysCtrl = TextEditingController(
      text: widget.selection.consecutiveDays.toString(),
    );
  }

  @override
  void didUpdateWidget(covariant ScheduleSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    final want = widget.selection.consecutiveDays.toString();
    if (_daysCtrl.text != want) _daysCtrl.text = want;
  }

  @override
  void dispose() {
    _daysCtrl.dispose();
    super.dispose();
  }

  void _toggleWeekday(int iso) {
    final next = Set<int>.from(widget.selection.weekdays);
    if (!next.remove(iso)) next.add(iso);
    widget.onChanged(widget.selection.copyWith(weekdays: next));
  }

  Future<void> _pickSpecificDates() async {
    final now = DateTime.now();
    final result = await showDialog<Set<DateTime>>(
      context: context,
      builder: (_) => _MultiDatePickerDialog(
        initialSelected: widget.selection.specificDates,
        firstDate: DateTime(now.year - 1, 1, 1),
        lastDate: DateTime(now.year + 2, 12, 31),
        focusedDay: widget.baseDate,
      ),
    );
    if (result == null) return;
    widget.onChanged(widget.selection.copyWith(specificDates: result));
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('DEBUG: ScheduleSelector build triggered');
    const cyan = Color(0xFF00F3FF);
    const gold = Color(0xFFFFD700);
    final sel = widget.selection;
    final sortedDates = sel.specificDates.toList()..sort();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0x0DFFD700),
        border: Border.all(color: gold, width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'SCHEDULE',
            style: TextStyle(
              color: gold,
              fontFamily: 'monospace',
              fontSize: 12,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Pick any combination — a bulk insert covers them all.',
            style: TextStyle(
              color: Color(0xCCFFFFFF),
              fontFamily: 'monospace',
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _daysCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Number of days',
              helperText: 'One record per day starting today',
              labelStyle: TextStyle(color: gold, fontFamily: 'monospace'),
              helperStyle: TextStyle(
                color: Color(0xCCFFFFFF),
                fontFamily: 'monospace',
                fontSize: 10,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: gold, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: gold, width: 1.5),
              ),
            ),
            onChanged: (v) {
              final parsed = int.tryParse(v.trim()) ?? 1;
              widget.onChanged(
                sel.copyWith(consecutiveDays: parsed.clamp(0, 365)),
              );
            },
          ),
          const SizedBox(height: 14),
          const Text(
            'REPEAT ON WEEKDAYS (NEXT 4 WEEKS)',
            style: TextStyle(
              color: gold,
              fontFamily: 'monospace',
              fontSize: 11,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 1; i <= 7; i++)
                _WeekdayCheckbox(
                  label: _shortWeekday(i),
                  value: sel.weekdays.contains(i),
                  onChanged: (_) => _toggleWeekday(i),
                ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickSpecificDates,
            icon: const Icon(Icons.event_note, size: 18, color: gold),
            label: Text(
              sel.specificDates.isEmpty
                  ? 'SELECT SPECIFIC DATES'
                  : 'SELECT SPECIFIC DATES (${sel.specificDates.length})',
              style: const TextStyle(
                color: gold,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                fontSize: 11,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: gold, width: 1),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
            ),
          ),
          if (sortedDates.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final d in sortedDates)
                  InputChip(
                    label: Text(
                      _shortDate(d),
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                    backgroundColor: const Color(0x33FFD700),
                    shape: const StadiumBorder(
                      side: BorderSide(color: gold, width: 1),
                    ),
                    deleteIconColor: gold,
                    onDeleted: () {
                      final next = Set<DateTime>.from(sel.specificDates)
                        ..remove(d);
                      widget.onChanged(
                        sel.copyWith(specificDates: next),
                      );
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            _summaryLine(sel, widget.baseDate),
            style: const TextStyle(
              color: cyan,
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  static String _summaryLine(ScheduleSelection sel, DateTime baseDate) {
    final count = sel.resolveDates(baseDate).length;
    return count == 1
        ? 'Will create 1 record.'
        : 'Will create $count records.';
  }

  static String _shortWeekday(int iso) {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return labels[(iso - 1).clamp(0, 6)];
  }
}

String _shortDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day.toString().padLeft(2, '0')}';
}

class _WeekdayCheckbox extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool?> onChanged;

  const _WeekdayCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFFFD700);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            side: const BorderSide(color: gold, width: 1.2),
            activeColor: gold,
            checkColor: Colors.black,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: gold,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _MultiDatePickerDialog extends StatefulWidget {
  final Set<DateTime> initialSelected;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime focusedDay;

  const _MultiDatePickerDialog({
    required this.initialSelected,
    required this.firstDate,
    required this.lastDate,
    required this.focusedDay,
  });

  @override
  State<_MultiDatePickerDialog> createState() => _MultiDatePickerDialogState();
}

class _MultiDatePickerDialogState extends State<_MultiDatePickerDialog> {
  late Set<DateTime> _selected;
  late DateTime _focused;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelected
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet();
    final base = DateTime(
      widget.focusedDay.year,
      widget.focusedDay.month,
      widget.focusedDay.day,
    );
    _focused = base.isBefore(widget.firstDate)
        ? widget.firstDate
        : (base.isAfter(widget.lastDate) ? widget.lastDate : base);
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    final sorted = _selected.toList()..sort();

    return AlertDialog(
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      title: const Text(
        'SELECT DATES',
        style: TextStyle(
          color: cyan,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
        ),
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: Theme.of(context).colorScheme.copyWith(
                    primary: cyan,
                    onPrimary: Colors.black,
                    surface: bg,
                    onSurface: cyan,
                  ),
                ),
                child: CalendarDatePicker(
                  key: ValueKey(_focused),
                  initialDate: _focused,
                  firstDate: widget.firstDate,
                  lastDate: widget.lastDate,
                  onDateChanged: (d) {
                    final k = DateTime(d.year, d.month, d.day);
                    setState(() {
                      _focused = k;
                      if (_selected.contains(k)) {
                        _selected.remove(k);
                      } else {
                        _selected.add(k);
                      }
                    });
                  },
                ),
              ),
              const Text(
                'Tap a day to toggle it on or off.',
                style: TextStyle(
                  color: Color(0x8800F3FF),
                  fontFamily: 'monospace',
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 10),
              if (sorted.isEmpty)
                const Text(
                  'No dates selected.',
                  style: TextStyle(
                    color: Color(0x6600F3FF),
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final d in sorted)
                      InputChip(
                        label: Text(
                          _shortDate(d),
                          style: const TextStyle(
                            color: cyan,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                        backgroundColor: const Color(0x1A00F3FF),
                        shape: const StadiumBorder(
                          side: BorderSide(color: cyan, width: 1),
                        ),
                        deleteIconColor: cyan,
                        onDeleted: () =>
                            setState(() => _selected.remove(d)),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
