import 'package:flutter/material.dart';

/// Compact GF / LGI chips and high-allergen warning for search and list rows.
class DietIndicatorBadges extends StatelessWidget {
  final bool isGlutenFree;
  final int? glycemicIndex;
  final int allergenLevel;

  const DietIndicatorBadges({
    super.key,
    required this.isGlutenFree,
    required this.glycemicIndex,
    required this.allergenLevel,
  });

  Widget _chip(
    String label,
    String tooltip, {
    Color? borderColor,
    Color? textColor,
  }) {
    const cyan = Color(0xFF00F3FF);
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: borderColor ?? const Color(0x5500F3FF)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            fontFamily: 'monospace',
            letterSpacing: 0.4,
          ).copyWith(color: textColor ?? cyan),
        ),
      ),
    );
  }

  ({String label, Color color, String tooltip})? _giChip(int? gi) {
    if (gi == null) return null;
    final v = gi.clamp(0, 100);
    if (v <= 55) {
      return (
        label: 'GI: $v (Low)',
        color: const Color(0xFF4CAF50),
        tooltip: 'Low GI (≤55)',
      );
    }
    if (v <= 69) {
      return (
        label: 'GI: $v (Med)',
        color: const Color(0xFFFFB74D),
        tooltip: 'Medium GI (56–69)',
      );
    }
    return (
      label: 'GI: $v (High)',
      color: const Color(0xFFFF3B30),
      tooltip: 'High GI (≥70)',
    );
  }

  @override
  Widget build(BuildContext context) {
    final gi = _giChip(glycemicIndex);
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (isGlutenFree) _chip('GF', 'Gluten-Free'),
        if (gi != null)
          _chip(
            gi.label,
            gi.tooltip,
            borderColor: gi.color.withValues(alpha: 0.55),
            textColor: gi.color,
          ),
        if (allergenLevel > 3)
          Tooltip(
            message: 'Allergen level: $allergenLevel (elevated)',
            child: const Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: Color(0xFFFFB74D),
            ),
          ),
      ],
    );
  }
}
