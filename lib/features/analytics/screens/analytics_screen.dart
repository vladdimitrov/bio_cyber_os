import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bio_cyber_os/l10n/app_localizations.dart';

import '../../../core/reports/analytics_models.dart';
import '../../../core/reports/analytics_repository.dart';
import '../../../core/reports/pdf_export_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late final AnalyticsRepository _repo;
  late final TabController _tabController;

  DateTime _rangeStart = DateTime.now();
  DateTime _rangeEnd = DateTime.now();
  DateTime _dailyExportDate = DateTime.now();

  List<DailyFuelPoint> _fuel = [];
  List<DailyAdherencePoint> _supps = [];
  List<DailyAdherencePoint> _meds = [];

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo = AnalyticsRepository(Supabase.instance.client);
    _tabController = TabController(length: 3, vsync: this);
    final now = DateTime.now();
    _rangeEnd = DateTime(now.year, now.month, now.day);
    _rangeStart = _rangeEnd.subtract(const Duration(days: 6));
    _dailyExportDate = _rangeEnd;
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDateRange: DateTimeRange(start: _rangeStart, end: _rangeEnd),
      helpText: AppLocalizations.of(context)!.selectDateRange,
    );
    if (picked == null) return;
    setState(() {
      _rangeStart = picked.start;
      _rangeEnd = picked.end;
    });
    await _loadAll();
  }

  Future<void> _pickDailyExportDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dailyExportDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() => _dailyExportDate = picked);
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fuel = await _repo.fetchFuelSeries(
        rangeStart: _rangeStart,
        rangeEnd: _rangeEnd,
      );
      final sup = await _repo.fetchSupplementAdherence(
        rangeStart: _rangeStart,
        rangeEnd: _rangeEnd,
      );
      final med = await _repo.fetchMedicationAdherence(
        rangeStart: _rangeStart,
        rangeEnd: _rangeEnd,
      );
      if (!mounted) return;
      setState(() {
        _fuel = fuel;
        _supps = sup;
        _meds = med;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _printDailyPlan() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await PdfExportService.buildDailyPlanPdfFromSupabase(
        client: Supabase.instance.client,
        date: _dailyExportDate,
      );
      if (!mounted) return;
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name:
            'daily_plan_${_dailyExportDate.year}${_dailyExportDate.month.toString().padLeft(2, '0')}${_dailyExportDate.day.toString().padLeft(2, '0')}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.pdfError('$e')),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _printWeeklySummary() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await PdfExportService.buildWeeklySummaryPdfFromSupabase(
        client: Supabase.instance.client,
        rangeStart: _rangeStart,
        rangeEnd: _rangeEnd,
      );
      if (!mounted) return;
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'weekly_summary.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.pdfError('$e')),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showExportSheet() {
    final cyan = const Color(0xFF00F3FF);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF050510),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) {
        final loc = AppLocalizations.of(ctx)!;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  loc.printExport,
                  style: TextStyle(
                    color: cyan,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: Icon(Icons.today, color: cyan),
                  title: Text(
                    loc.printDailyPlanTitle,
                    style: TextStyle(
                      color: cyan,
                      fontFamily: 'monospace',
                    ),
                  ),
                  subtitle: Text(
                    loc.analyticsDailyPlanSubtitle(_ymd(_dailyExportDate)),
                    style: const TextStyle(
                      color: Color(0xFF757575),
                      fontSize: 11,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _printDailyPlan();
                  },
                ),
                ListTile(
                  leading: Icon(Icons.table_chart_outlined, color: cyan),
                  title: Text(
                    loc.exportWeeklySummaryTitle,
                    style: TextStyle(
                      color: cyan,
                      fontFamily: 'monospace',
                    ),
                  ),
                  subtitle: Text(
                    loc.analyticsWeeklySubtitle(
                      _ymd(_rangeStart),
                      _ymd(_rangeEnd),
                    ),
                    style: const TextStyle(
                      color: Color(0xFF757575),
                      fontSize: 11,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _printWeeklySummary();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _shortDay(DateTime d) => '${d.month}/${d.day}';

  Widget _fuelTab(AppLocalizations loc) {
    const cyan = Color(0xFF00F3FF);
    if (_fuel.isEmpty) {
      return Center(
        child: Text(
          loc.analyticsNoDaysInRange,
          style: const TextStyle(color: cyan, fontFamily: 'monospace'),
        ),
      );
    }

    final calSpots = <FlSpot>[];
    final glSpots = <FlSpot>[];
    for (var i = 0; i < _fuel.length; i++) {
      calSpots.add(FlSpot(i.toDouble(), _fuel[i].calories));
      glSpots.add(FlSpot(i.toDouble(), _fuel[i].glycemicLoad));
    }

    final maxCal = _fuel.map((e) => e.calories).fold<double>(0, math.max);
    final maxGl = _fuel.map((e) => e.glycemicLoad).fold<double>(0, math.max);
    final maxYCal = maxCal <= 0 ? 1.0 : maxCal * 1.15;
    final maxYGl = maxGl <= 0 ? 1.0 : maxGl * 1.15;

    LineChartData lineData({
      required List<FlSpot> spots,
      required double maxY,
      required Color color,
    }) {
      return LineChartData(
        minX: 0,
        maxX: math.max(0, _fuel.length - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          getDrawingHorizontalLine: (v) => FlLine(
            color: const Color(0x3300F3FF),
            strokeWidth: 1,
          ),
          getDrawingVerticalLine: (v) => FlLine(
            color: const Color(0x2200F3FF),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, m) => Text(
                v.round().toString(),
                style: const TextStyle(
                  color: Color(0x8800F3FF),
                  fontSize: 10,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (v, m) {
                final i = v.round();
                if (i < 0 || i >= _fuel.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _shortDay(_fuel[i].day),
                    style: const TextStyle(
                      color: Color(0x8800F3FF),
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: const Border(
            bottom: BorderSide(color: Color(0x4400F3FF)),
            left: BorderSide(color: Color(0x4400F3FF)),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: color,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.12),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touched) {
              return touched.map((e) {
                final i = e.x.round();
                if (i < 0 || i >= _fuel.length) return null;
                final d = _fuel[i].day;
                final label =
                    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                return LineTooltipItem(
                  '$label\n${e.y.toStringAsFixed(1)}',
                  const TextStyle(color: Colors.white, fontSize: 12),
                );
              }).toList();
            },
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          loc.analyticsConsumedCaloriesTitle,
          style: const TextStyle(
            color: cyan,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        if (maxCal == 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              loc.analyticsNoConsumedFood,
              style: const TextStyle(
                color: Color(0x8800F3FF),
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ),
        SizedBox(
          height: 220,
          child: LineChart(
            lineData(
              spots: calSpots,
              maxY: maxYCal,
              color: const Color(0xFF00F3FF),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          loc.analyticsGlycemicTitle,
          style: const TextStyle(
            color: cyan,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        if (maxGl == 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              loc.analyticsNoGiData,
              style: const TextStyle(
                color: Color(0x8800F3FF),
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ),
        SizedBox(
          height: 220,
          child: LineChart(
            lineData(
              spots: glSpots,
              maxY: maxYGl,
              color: const Color(0xFF88CCFF),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          loc.analyticsSourceDailyLogs,
          style: TextStyle(
            color: cyan.withValues(alpha: 0.55),
            fontFamily: 'monospace',
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _adherenceTab(
    AppLocalizations loc,
    List<DailyAdherencePoint> data,
    String title, {
    String? sourceLine,
  }) {
    const cyan = Color(0xFF00F3FF);
    if (data.isEmpty) {
      return Center(
        child: Text(
          loc.analyticsNoDataForRange,
          style: const TextStyle(color: cyan, fontFamily: 'monospace'),
        ),
      );
    }

    double maxY = 1;
    for (final d in data) {
      maxY = math.max(maxY, (d.taken + d.missed).toDouble());
    }
    if (maxY <= 0) maxY = 1;
    maxY *= 1.15;

    final groups = <BarChartGroupData>[];
    for (var i = 0; i < data.length; i++) {
      final t = data[i].taken.toDouble();
      final m = data[i].missed.toDouble();
      groups.add(
        BarChartGroupData(
          x: i,
          barsSpace: 6,
          barRods: [
            BarChartRodData(
              toY: t,
              width: 10,
              color: const Color(0xFF4CAF50),
              borderRadius: BorderRadius.zero,
            ),
            BarChartRodData(
              toY: m,
              width: 10,
              color: const Color(0xFFE53935),
              borderRadius: BorderRadius.zero,
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          title,
          style: const TextStyle(
            color: cyan,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w800,
            fontSize: 11,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _LegendDot(color: const Color(0xFF4CAF50), label: loc.analyticsLegendTaken),
            const SizedBox(width: 16),
            _LegendDot(color: const Color(0xFFE53935), label: loc.analyticsLegendMissed),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 280,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                getDrawingHorizontalLine: (v) => FlLine(
                  color: const Color(0x3300F3FF),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    getTitlesWidget: (v, m) => Text(
                      v.round().toString(),
                      style: const TextStyle(
                        color: Color(0x8800F3FF),
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, m) {
                      final i = v.toInt();
                      if (i < 0 || i >= data.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _shortDay(data[i].day),
                          style: const TextStyle(
                            color: Color(0x8800F3FF),
                            fontSize: 10,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: const Border(
                  bottom: BorderSide(color: Color(0x4400F3FF)),
                  left: BorderSide(color: Color(0x4400F3FF)),
                ),
              ),
              barGroups: groups,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          loc.analyticsMissedExplainer,
          style: TextStyle(
            color: cyan.withValues(alpha: 0.55),
            fontFamily: 'monospace',
            fontSize: 10,
          ),
        ),
        if (sourceLine != null) ...[
          const SizedBox(height: 10),
          Text(
            sourceLine,
            style: TextStyle(
              color: cyan.withValues(alpha: 0.55),
              fontFamily: 'monospace',
              fontSize: 10,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    final l10n = AppLocalizations.of(context)!;

    final uid = _repo.currentUserId;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(l10n.screenReports),
        bottom: TabBar(
          controller: _tabController,
          labelColor: cyan,
          unselectedLabelColor: const Color(0x8800F3FF),
          indicatorColor: cyan,
          tabs: [
            Tab(text: l10n.navFuel),
            Tab(text: l10n.navSupps),
            Tab(text: l10n.navMeds),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'analytics_fab',
        onPressed: uid == null ? null : _showExportSheet,
        backgroundColor: bg,
        foregroundColor: cyan,
        icon: const Icon(Icons.print_outlined),
        label: Text(
          l10n.printExport,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      ),
      body: uid == null
          ? Center(
              child: Text(
                l10n.msgSignInReports,
                style: const TextStyle(color: cyan, fontFamily: 'monospace'),
              ),
            )
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(
                          _error!,
                          style: const TextStyle(color: cyan),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        Material(
                          color: bg,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _pickRange,
                                  icon: const Icon(Icons.date_range),
                                  label: Text(
                                    l10n.analyticsRangeButton(
                                      _ymd(_rangeStart),
                                      _ymd(_rangeEnd),
                                    ),
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: cyan,
                                    side: const BorderSide(color: cyan),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.zero,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: _pickDailyExportDate,
                                  icon: const Icon(Icons.edit_calendar_outlined),
                                  label: Text(
                                    l10n.analyticsDailyPlanPdfDate(
                                      _ymd(_dailyExportDate),
                                    ),
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF88CCFF),
                                    side: const BorderSide(
                                      color: Color(0xFF88CCFF),
                                    ),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.zero,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _fuelTab(l10n),
                              _adherenceTab(
                                l10n,
                                _supps,
                                l10n.analyticsSuppAdherenceTitle,
                                sourceLine: l10n.analyticsSourceDailyLogsShort,
                              ),
                              _adherenceTab(
                                l10n,
                                _meds,
                                l10n.analyticsMedAdherenceTitle,
                                sourceLine: l10n.analyticsSourceMedLogs,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF00F3FF),
            fontFamily: 'monospace',
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
