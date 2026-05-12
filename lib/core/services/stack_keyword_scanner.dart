/// Stack-related keywords scanned from ingredient / label text (case-insensitive).
class StackKeywordReport {
  final bool gluten;
  final bool dairy;
  final bool lactose;
  final bool starch;

  const StackKeywordReport({
    required this.gluten,
    required this.dairy,
    required this.lactose,
    required this.starch,
  });

  bool get anyDetected => gluten || dairy || lactose || starch;

  /// Human-readable labels for UI chips (only detected items).
  List<String> get detectedLabels {
    final out = <String>[];
    if (gluten) out.add('Gluten');
    if (dairy) out.add('Dairy');
    if (lactose) out.add('Lactose');
    if (starch) out.add('Starch');
    return out;
  }
}

StackKeywordReport scanStackKeywords(String? raw) {
  final text = (raw ?? '').toLowerCase();
  return StackKeywordReport(
    gluten: text.contains('gluten'),
    dairy: text.contains('dairy'),
    lactose: text.contains('lactose'),
    starch: text.contains('starch'),
  );
}
