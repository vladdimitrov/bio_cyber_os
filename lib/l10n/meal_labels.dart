import 'app_localizations.dart';

/// Local display title for a canonical meal key (e.g. [BREAKFAST]) or [EXTRA:SNACK]).
String localizedMealSectionTitle(AppLocalizations l10n, String mealKey) {
  if (mealKey.startsWith('EXTRA:')) {
    final raw = mealKey.substring('EXTRA:'.length).trim();
    final s = raw.toUpperCase();
    if (s == 'SNACK') return l10n.mealExtraSnack;
    if (s == 'UNSORTED') return l10n.mealExtraUnsorted;
    return raw;
  }
  switch (mealKey) {
    case 'BREAKFAST':
      return l10n.mealBreakfast;
    case 'LUNCH':
      return l10n.mealLunch;
    case 'DINNER':
      return l10n.mealDinner;
    default:
      return mealKey;
  }
}

String localizedTimeBlock(AppLocalizations l10n, String block) {
  switch (block) {
    case 'MORNING':
      return l10n.blockMorning;
    case 'AFTERNOON':
      return l10n.blockAfternoon;
    case 'EVENING':
      return l10n.blockEvening;
    case 'NIGHT':
      return l10n.blockNight;
    default:
      return block;
  }
}
