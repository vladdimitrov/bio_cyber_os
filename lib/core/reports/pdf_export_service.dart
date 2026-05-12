import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'analytics_models.dart';
import 'analytics_repository.dart';

/// PDF builders for print / save (Web & mobile via `printing`).
///
/// **Daily plan** rows are produced by [AnalyticsRepository.fetchDailyPlanLines],
/// which loads **`daily_logs`** (food + supplements) and **`medication_logs`**
/// using the same **`created_at`** UTC day-range filters as the FUEL / SUPPS /
/// MEDS reports. Medication lines use **`dose_amount`** and **`unit_type`** in
/// [DailyPlanLine.amountUnit].
///
/// For convenience, use [buildDailyPlanPdfFromSupabase] and
/// [buildWeeklySummaryPdfFromSupabase] so PDFs always match repository logic.
class PdfExportService {
  static const _blocks = ['MORNING', 'AFTERNOON', 'EVENING', 'NIGHT'];

  static pw.TextStyle get _headerStyle => pw.TextStyle(
        fontSize: 14,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.black,
      );

  static pw.TextStyle get _bodyStyle => const pw.TextStyle(
        fontSize: 10,
        color: PdfColors.black,
      );

  /// Fetches plan lines from Supabase then renders the daily plan PDF.
  static Future<Uint8List> buildDailyPlanPdfFromSupabase({
    required SupabaseClient client,
    required DateTime date,
  }) async {
    final lines = await AnalyticsRepository(client).fetchDailyPlanLines(date);
    return buildDailyPlanPdf(date: date, lines: lines);
  }

  /// Fetches weekly aggregates from Supabase then renders the summary PDF.
  static Future<Uint8List> buildWeeklySummaryPdfFromSupabase({
    required SupabaseClient client,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    final stats = await AnalyticsRepository(client).fetchWeeklySummary(
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
    );
    return buildWeeklySummaryPdf(stats);
  }

  static Future<Uint8List> buildDailyPlanPdf({
    required DateTime date,
    required List<DailyPlanLine> lines,
  }) async {
    final doc = pw.Document();
    final dateStr =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    final byBlock = <String, List<DailyPlanLine>>{
      for (final b in _blocks) b: <DailyPlanLine>[],
    };
    for (final line in lines) {
      final key = _blocks.contains(line.block) ? line.block : 'MORNING';
      byBlock[key]!.add(line);
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) {
          final widgets = <pw.Widget>[
            pw.Text(
              'BIO_CYBER OS — DAILY PLAN',
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(dateStr, style: _headerStyle),
            pw.SizedBox(height: 8),
            pw.Text(
              'Includes daily_logs (food + supplements) and medication_logs; '
              'filtered by created_at on the selected calendar day. '
              'MED lines show dose_amount and unit_type.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
            ),
            pw.SizedBox(height: 12),
            pw.Divider(thickness: 2, color: PdfColors.black),
            pw.SizedBox(height: 12),
          ];

          var any = false;
          for (final block in _blocks) {
            final items = byBlock[block]!;
            if (items.isEmpty) continue;
            any = true;
            widgets.add(pw.Text(block, style: _headerStyle));
            widgets.add(pw.SizedBox(height: 6));
            for (final line in items) {
              widgets.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.SizedBox(
                        width: 28,
                        child: pw.Text('[ ]', style: _bodyStyle),
                      ),
                      pw.Expanded(
                        child: pw.Text(
                          '${line.timeLabel}  |  ${line.name}  |  ${line.amountUnit}  (${line.categoryLabel})',
                          style: _bodyStyle,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            widgets.add(pw.SizedBox(height: 14));
          }

          if (!any) {
            widgets.add(
              pw.Text(
                'No items planned for this day.',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
              ),
            );
            widgets.add(pw.SizedBox(height: 16));
          }

          widgets.add(pw.Divider(thickness: 1, color: PdfColors.grey800));
          widgets.add(pw.SizedBox(height: 10));
          widgets.add(
            pw.Text(
              'MANUAL NOTES',
              style: _headerStyle,
            ),
          );
          widgets.add(pw.SizedBox(height: 6));
          widgets.add(
            pw.Text(
              'Use the lines below for sleep, mood, or other notes.',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800),
            ),
          );
          widgets.add(pw.SizedBox(height: 10));
          for (var i = 0; i < 12; i++) {
            widgets.add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 10),
                child: pw.Container(
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(width: 0.75, color: PdfColors.black),
                    ),
                  ),
                  height: 18,
                ),
              ),
            );
          }

          widgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 16),
              child: pw.Text(
                'Generated by Biohacker OS — for professional use alongside your care team.',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
              ),
            ),
          );

          return widgets;
        },
      ),
    );

    return doc.save();
  }

  static Future<Uint8List> buildWeeklySummaryPdf(WeeklySummaryStats stats) async {
    final doc = pw.Document();
    final rangeLabel =
        '${stats.rangeStart.year}-${stats.rangeStart.month.toString().padLeft(2, '0')}-${stats.rangeStart.day.toString().padLeft(2, '0')} — ${stats.rangeEnd.year}-${stats.rangeEnd.month.toString().padLeft(2, '0')}-${stats.rangeEnd.day.toString().padLeft(2, '0')}';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) {
          final rows = <pw.TableRow>[
            pw.TableRow(
              children: [
                _cell('Date', header: true),
                _cell('kcal', header: true),
                _cell('GL', header: true),
                _cell('Supp ✓', header: true),
                _cell('Supp ✗', header: true),
                _cell('Med ✓', header: true),
                _cell('Med ✗', header: true),
              ],
            ),
          ];

          final n = stats.fuelByDay.length;
          for (var i = 0; i < n; i++) {
            final f = stats.fuelByDay[i];
            final s = i < stats.suppsByDay.length
                ? stats.suppsByDay[i]
                : DailyAdherencePoint(day: f.day, taken: 0, missed: 0);
            final m = i < stats.medsByDay.length
                ? stats.medsByDay[i]
                : DailyAdherencePoint(day: f.day, taken: 0, missed: 0);
            final ds =
                '${f.day.year}-${f.day.month.toString().padLeft(2, '0')}-${f.day.day.toString().padLeft(2, '0')}';
            rows.add(
              pw.TableRow(
                children: [
                  _cell(ds),
                  _cell(f.calories.round().toString()),
                  _cell(f.glycemicLoad.toStringAsFixed(1)),
                  _cell(s.taken.toString()),
                  _cell(s.missed.toString()),
                  _cell(m.taken.toString()),
                  _cell(m.missed.toString()),
                ],
              ),
            );
          }

          return [
            pw.Text(
              'BIO_CYBER OS — WEEKLY SUMMARY',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(rangeLabel, style: _headerStyle),
            pw.SizedBox(height: 16),
            pw.Text(
              'FUEL: daily_logs (created_at), consumed food only. '
              'GL estimated from ingredient GI and carbs where known. '
              'SUPP: daily_logs (created_at). MED: medication_logs (created_at).',
              style:
                  const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
            ),
            pw.SizedBox(height: 12),
            pw.Table(
              border: pw.TableBorder.all(width: 0.75, color: PdfColors.black),
              columnWidths: {
                0: const pw.FixedColumnWidth(78),
                1: const pw.FixedColumnWidth(44),
                2: const pw.FixedColumnWidth(40),
                3: const pw.FixedColumnWidth(44),
                4: const pw.FixedColumnWidth(44),
                5: const pw.FixedColumnWidth(44),
                6: const pw.FixedColumnWidth(44),
              },
              children: rows,
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              'MANUAL NOTES',
              style: _headerStyle,
            ),
            pw.SizedBox(height: 8),
            for (var i = 0; i < 6; i++)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 10),
                child: pw.Container(
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(width: 0.75, color: PdfColors.black),
                    ),
                  ),
                  height: 16,
                ),
              ),
          ];
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _cell(String text, {bool header = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      alignment: pw.Alignment.centerLeft,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: header ? 9 : 9,
          fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: PdfColors.black,
        ),
      ),
    );
  }
}
