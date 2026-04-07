import 'package:flutter/material.dart';

enum ReminderMode { atConsumptionTime, minutesBefore }

class ReminderState {
  final bool enabled;
  final ReminderMode mode;
  final int offsetMinutes;

  const ReminderState({
    required this.enabled,
    required this.mode,
    required this.offsetMinutes,
  });

  const ReminderState.disabled()
      : enabled = false,
        mode = ReminderMode.atConsumptionTime,
        offsetMinutes = 0;

  ReminderState copyWith({
    bool? enabled,
    ReminderMode? mode,
    int? offsetMinutes,
  }) {
    return ReminderState(
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
      offsetMinutes: offsetMinutes ?? this.offsetMinutes,
    );
  }
}

class ReminderSection extends StatefulWidget {
  final ReminderState state;
  final ValueChanged<ReminderState> onChanged;
  final List<int> allowedOffsets;

  const ReminderSection({
    super.key,
    required this.state,
    required this.onChanged,
    this.allowedOffsets = const [5, 15, 30, 60],
  });

  @override
  State<ReminderSection> createState() => _ReminderSectionState();
}

class _ReminderSectionState extends State<ReminderSection> {
  late final TextEditingController _minutesCtrl;

  @override
  void initState() {
    super.initState();
    _minutesCtrl = TextEditingController(
      text: widget.state.offsetMinutes > 0
          ? widget.state.offsetMinutes.toString()
          : (widget.allowedOffsets.isNotEmpty
              ? widget.allowedOffsets.first.toString()
              : '30'),
    );
  }

  @override
  void didUpdateWidget(covariant ReminderSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final s = widget.state;
    if (s.enabled &&
        s.mode == ReminderMode.minutesBefore &&
        s.offsetMinutes > 0 &&
        _minutesCtrl.text.trim() != s.offsetMinutes.toString()) {
      _minutesCtrl.text = s.offsetMinutes.toString();
    }
  }

  @override
  void dispose() {
    _minutesCtrl.dispose();
    super.dispose();
  }

  int _parseMinutesOrFallback() {
    final raw = _minutesCtrl.text.trim();
    final v = int.tryParse(raw);
    if (v == null || v <= 0) {
      final fallback = widget.allowedOffsets.isNotEmpty
          ? widget.allowedOffsets.first
          : 30;
      return fallback;
    }
    return v;
  }

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF00F3FF);
    final state = widget.state;
    final onChanged = widget.onChanged;
    final allowedOffsets = widget.allowedOffsets;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'REMINDER',
                style: TextStyle(
                  color: Color(0x8800F3FF),
                  fontFamily: 'monospace',
                  fontSize: 11,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Switch(
              value: state.enabled,
              activeThumbColor: cyan,
              onChanged: (v) {
                final next = state.copyWith(
                  enabled: v,
                  offsetMinutes: v
                      ? (state.offsetMinutes > 0
                          ? state.offsetMinutes
                          : (allowedOffsets.isNotEmpty
                              ? allowedOffsets.first
                              : 30))
                      : 0,
                );
                onChanged(next);
              },
            ),
          ],
        ),
        if (!state.enabled) const SizedBox.shrink() else ...[
          const SizedBox(height: 8),
          SegmentedButton<ReminderMode>(
            segments: const [
              ButtonSegment(
                value: ReminderMode.atConsumptionTime,
                label: Text('At consumption time'),
              ),
              ButtonSegment(
                value: ReminderMode.minutesBefore,
                label: Text('Minutes before'),
              ),
            ],
            selected: {state.mode},
            onSelectionChanged: (s) {
              if (s.isEmpty) return;
              onChanged(state.copyWith(mode: s.first));
            },
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.all(cyan),
              textStyle: WidgetStateProperty.all(
                const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
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
          if (state.mode == ReminderMode.minutesBefore) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _minutesCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: cyan, fontFamily: 'monospace'),
              onChanged: (_) {
                final mins = _parseMinutesOrFallback();
                onChanged(state.copyWith(offsetMinutes: mins));
              },
              decoration: const InputDecoration(
                labelText: 'Offset',
                labelStyle: TextStyle(color: cyan, fontFamily: 'monospace'),
                suffixText: 'minutes',
                suffixStyle: TextStyle(color: Color(0xFF757575)),
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
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final m in allowedOffsets)
                  ActionChip(
                    label: Text(
                      '$m',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
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
                      _minutesCtrl.text = '$m';
                      onChanged(state.copyWith(offsetMinutes: m));
                    },
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}

