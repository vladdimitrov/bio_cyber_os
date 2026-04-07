/// Point for fuel charts: one local calendar day.
class DailyFuelPoint {
  final DateTime day;
  final double calories;
  final double glycemicLoad;

  const DailyFuelPoint({
    required this.day,
    required this.calories,
    required this.glycemicLoad,
  });
}

/// Adherence counts for one local calendar day.
class DailyAdherencePoint {
  final DateTime day;
  final int taken;
  final int missed;

  const DailyAdherencePoint({
    required this.day,
    required this.taken,
    required this.missed,
  });
}

/// One line on the printable daily plan.
class DailyPlanLine {
  final String block; // MORNING, AFTERNOON, ...
  final String timeLabel;
  final String name;
  final String amountUnit;
  final String categoryLabel; // FOOD | SUPP | MED

  const DailyPlanLine({
    required this.block,
    required this.timeLabel,
    required this.name,
    required this.amountUnit,
    required this.categoryLabel,
  });
}

/// Aggregates for weekly summary PDF.
class WeeklySummaryStats {
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final List<DailyFuelPoint> fuelByDay;
  final List<DailyAdherencePoint> suppsByDay;
  final List<DailyAdherencePoint> medsByDay;

  const WeeklySummaryStats({
    required this.rangeStart,
    required this.rangeEnd,
    required this.fuelByDay,
    required this.suppsByDay,
    required this.medsByDay,
  });
}
