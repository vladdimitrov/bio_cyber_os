import 'app_localizations.dart';

extension AppLocalizationsMacros on AppLocalizations {
  String formatMacroSubtotal(List<double> v) {
    return macroSummaryLine(
      v[0].toStringAsFixed(1),
      v[1].toStringAsFixed(1),
      v[2].toStringAsFixed(1),
      v[3].round().toString(),
    );
  }

  String formatMacroCompare(List<double> current, List<double> planned) {
    return macroCompareLine(
      formatMacroSubtotal(current),
      formatMacroSubtotal(planned),
    );
  }
}
