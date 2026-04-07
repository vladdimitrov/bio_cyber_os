/// Local calendar day as `YYYY-MM-DD` (year/month/day from [localDay], no timezone conversion).
String supabaseDateOnly(DateTime localDay) {
  final d = DateTime(localDay.year, localDay.month, localDay.day);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Lower bound for filtering `created_at` (TIMESTAMPTZ) to one UTC calendar day.
String supabaseCreatedAtDayGte(String ymd) => '${ymd}T00:00:00.000Z';

/// Upper bound for filtering `created_at` (TIMESTAMPTZ) to one UTC calendar day.
String supabaseCreatedAtDayLte(String ymd) => '${ymd}T23:59:59.999Z';

/// Half-open UTC range `[gte, lt)` for the device **local** calendar day of [localDay].
/// Use with `.gte('created_at', gte).lt('created_at', lt)` (or `scheduled_at`) so logs
/// match the day the user sees in the date picker, not the UTC `YYYY-MM-DD` string alone.
({String gte, String lt}) supabaseLocalDayUtcBounds(DateTime localDay) {
  final start = DateTime(localDay.year, localDay.month, localDay.day);
  final end = start.add(const Duration(days: 1));
  return (gte: start.toUtc().toIso8601String(), lt: end.toUtc().toIso8601String());
}

/// `YYYY-MM-DD` from a Postgres/ISO timestamp string, or null if too short.
String? supabaseYmdFromCreatedAt(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  if (s.length < 10) return null;
  return s.substring(0, 10);
}
