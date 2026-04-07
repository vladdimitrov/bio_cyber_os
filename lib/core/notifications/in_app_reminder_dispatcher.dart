import 'dart:async';
import 'package:flutter/material.dart';

import '../navigation/app_navigator.dart';
import '../../app_shell.dart';

typedef _Pending = ({
  DateTime whenLocal,
  String title,
  String body,
  Map<String, dynamic>? payload,
});

class InAppReminderDispatcher {
  InAppReminderDispatcher._();

  static final Map<String, _Pending> _pending = {};
  static Timer? _timer;
  static bool _showing = false;

  static void init() {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  static Future<void> schedule({
    required String key,
    required String title,
    required String body,
    required DateTime whenLocal,
    Map<String, dynamic>? payload,
  }) async {
    init();
    _pending[key] =
        (whenLocal: whenLocal, title: title, body: body, payload: payload);
  }

  static Future<void> cancel(String key) async {
    _pending.remove(key);
  }

  static void _tick() {
    if (_pending.isEmpty) return;
    if (_showing) return;

    final now = DateTime.now();
    final due = <String>[];
    _pending.forEach((k, v) {
      if (!v.whenLocal.isAfter(now)) due.add(k);
    });
    if (due.isEmpty) return;

    final key = due.first;
    final p = _pending.remove(key);
    if (p == null) return;

    final nav = AppNavigator.key.currentState;
    final ctx = nav?.overlay?.context;
    if (ctx == null) {
      // No UI yet; put it back and try next tick.
      _pending[key] = p;
      return;
    }

    _showing = true;
    _showReminderDialog(
      ctx,
      key: key,
      title: p.title,
      body: p.body,
      when: p.whenLocal,
      payload: p.payload,
    )
        .whenComplete(() => _showing = false);
  }

  static String _hhmm(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  static Future<void> _showReminderDialog(
    BuildContext context, {
    required String key,
    required String title,
    required String body,
    required DateTime when,
    Map<String, dynamic>? payload,
  }) async {
    const red = Color(0xFFFF3B30);
    const bg = Color(0xFF050510);

    final msg = 'Hey! $body\nScheduled for: ${_hhmm(when)}.';

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: const BorderSide(color: red, width: 2),
        ),
        title: Row(
          children: const [
            Icon(Icons.alarm, color: red),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Biohacker OS Reminder',
                style: TextStyle(
                  color: red,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF00F3FF),
                fontFamily: 'monospace',
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              msg,
              style: const TextStyle(
                color: Colors.white70,
                fontFamily: 'monospace',
                height: 1.3,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _handleView(key, when: when, payload: payload);
            },
            child: const Text('VIEW'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('DISMISS'),
          ),
        ],
      ),
    );
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _parseTargetDateLocalOrFallback(
    Map<String, dynamic>? payload,
    DateTime fallback,
  ) {
    final raw = (payload?['target_date'] ?? '').toString().trim();
    if (raw.isEmpty) return _dateOnly(fallback);
    try {
      // Accept "YYYY-MM-DD" or ISO.
      final dt = DateTime.parse(raw);
      return _dateOnly(dt.isUtc ? dt.toLocal() : dt);
    } catch (_) {
      return _dateOnly(fallback);
    }
  }

  static void _handleView(
    String key, {
    required DateTime when,
    Map<String, dynamic>? payload,
  }) {
    final itemType = (payload?['item_type'] ?? '').toString().trim().toLowerCase();
    final itemId = (payload?['item_id'] ?? '').toString().trim();
    final targetDate = _parseTargetDateLocalOrFallback(payload, when);

    if (itemType == 'supplement') {
      AppShell.openSupps(
        focusLogId: itemId.isEmpty ? null : itemId,
        focusDate: targetDate,
      );
      return;
    }
    if (itemType == 'medication') {
      AppShell.openMeds(
        focusLogId: itemId.isEmpty ? null : itemId,
        focusDate: targetDate,
      );
      return;
    }
    if (itemType == 'food') {
      AppShell.openFuel(
        focusLogId: itemId.isEmpty ? null : itemId,
        focusDate: targetDate,
      );
      return;
    }

    // Back-compat: infer from key if payload missing.
    final k = key.trim();
    if (k.startsWith('daily_logs:')) {
      final id = k.substring('daily_logs:'.length).trim();
      AppShell.openSupps(focusLogId: id.isEmpty ? null : id, focusDate: targetDate);
      return;
    }
    if (k.startsWith('medication_logs:')) {
      final id = k.substring('medication_logs:'.length).trim();
      AppShell.openMeds(focusLogId: id.isEmpty ? null : id, focusDate: targetDate);
      return;
    }
  }
}

