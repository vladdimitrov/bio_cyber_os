// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'BIO_CYBER OS';

  @override
  String get navFuel => 'FUEL';

  @override
  String get navSupps => 'SUPPS';

  @override
  String get navMeds => 'MEDS';

  @override
  String get navVitals => 'VITALS';

  @override
  String get navReports => 'REPORTS';

  @override
  String get navLibrary => 'LIBRARY';

  @override
  String get navConfig => 'CONFIG';

  @override
  String get screenFuelLog => 'FUEL LOG';

  @override
  String get screenSupps => 'SUPPS';

  @override
  String get screenMeds => 'MEDS';

  @override
  String get screenVitalsSymptoms => 'VITALS & SYMPTOMS';

  @override
  String get screenReports => 'REPORTS';

  @override
  String get screenLibrary => 'LIBRARY';

  @override
  String get screenConfig => 'CONFIG';

  @override
  String get addFood => 'ADD FOOD';

  @override
  String get save => 'SAVE';

  @override
  String get saveData => 'SAVE DATA';

  @override
  String get saveConfig => 'SAVE CONFIG';

  @override
  String get cancel => 'CANCEL';

  @override
  String get logIn => 'LOG IN';

  @override
  String get signUp => 'SIGN UP';

  @override
  String get logOut => 'Log out';

  @override
  String get refresh => 'Refresh';

  @override
  String get languageSectionTitle => 'LANGUAGE';

  @override
  String get languageLabel => 'Language';

  @override
  String get languageSystem => 'System default';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageBulgarian => 'Bulgarian';

  @override
  String get mealBreakfast => 'BREAKFAST';

  @override
  String get mealLunch => 'LUNCH';

  @override
  String get mealDinner => 'DINNER';

  @override
  String get mealExtraSnack => 'EXTRA / SNACK';

  @override
  String get mealExtraUnsorted => 'EXTRA';

  @override
  String get blockMorning => 'MORNING';

  @override
  String get blockAfternoon => 'AFTERNOON';

  @override
  String get blockEvening => 'EVENING';

  @override
  String get blockNight => 'NIGHT';

  @override
  String get nutritionDailyProgress => 'DAILY NUTRITION PROGRESS';

  @override
  String get nutritionChartLegend =>
      '■ solid = consumed  ·  ░ dashed = planned extra  ·  │ goal = daily target';

  @override
  String get nutritionProtein => 'PROTEIN';

  @override
  String get nutritionCarbs => 'CARBS';

  @override
  String get nutritionFats => 'FATS';

  @override
  String get nutritionCal => 'CAL';

  @override
  String get nutritionEatenShort => 'eaten';

  @override
  String get nutritionWithPlanShort => 'w/ plan';

  @override
  String get nutritionTargetShort => 'target';

  @override
  String get labelEaten => 'Eaten';

  @override
  String get labelPlanned => 'Planned';

  @override
  String get labelGoal => 'Goal';

  @override
  String get labelCurrent => 'current';

  @override
  String get labelPlannedLower => 'planned';

  @override
  String get dailyRecords => 'DAILY RECORDS';

  @override
  String get actionAddPlan => 'PLAN';

  @override
  String get actionAddExtra => '+ ADD EXTRA / SNACK';

  @override
  String get take => 'TAKE';

  @override
  String get edit => 'Edit';

  @override
  String get delete => 'Delete';

  @override
  String get printExport => 'PRINT / EXPORT';

  @override
  String get printDailyPlanTitle => 'Print Daily Plan (selected date)';

  @override
  String get exportWeeklySummaryTitle => 'Export Weekly Summary (PDF)';

  @override
  String get selectDateRange => 'Select date range';

  @override
  String get prevDay => 'Previous day';

  @override
  String get nextDay => 'Next day';

  @override
  String get close => 'Close';

  @override
  String get ok => 'OK';

  @override
  String get logVerb => 'LOG';

  @override
  String get unit => 'Unit';

  @override
  String get notes => 'Notes';

  @override
  String get number => 'Number';

  @override
  String get requiredField => 'Required';

  @override
  String get searchHint => 'Search…';

  @override
  String get noItemsFound => 'No items found';

  @override
  String get unknown => 'Unknown';

  @override
  String get missed => 'MISSED';

  @override
  String get plannedUpper => 'PLANNED';

  @override
  String get consumedUpper => 'CONSUMED';

  @override
  String get subtotal => 'SUBTOTAL';

  @override
  String fuelMacrosLine(String p, String c, String f, String cal) {
    return 'P: ${p}g | C: ${c}g | F: ${f}g | $cal kcal';
  }

  @override
  String get reminder => 'REMINDER';

  @override
  String get none => 'None';

  @override
  String get specific => 'Specific';

  @override
  String get minutesBefore => 'Minutes before';

  @override
  String get specificTime => 'Specific time';

  @override
  String get minutes => 'Minutes';

  @override
  String get pickTime => 'Pick time';

  @override
  String get recipe => 'Recipe';

  @override
  String get ingredient => 'Ingredient';

  @override
  String get planTag => '[PLAN]';

  @override
  String get gramsSuffix => 'g';

  @override
  String get fuelNoMealsToday =>
      'No meals logged for today yet. Use “+ ADD BREAKFAST/LUNCH/DINNER” (or PLAN) to log food — your history will appear here.';

  @override
  String fuelNoMealsForDay(String date) {
    return 'No meals logged for $date. RLS shows only your own entries; use the add buttons below when you are ready to log this day.';
  }

  @override
  String get fuelNoItemsBlock =>
      'No items for this block yet.\nTap “+ ADD …” or “PLAN” above.';

  @override
  String macroSummaryLine(String p, String c, String f, String cal) {
    return 'P ${p}g  C ${c}g  F ${f}g  $cal kcal';
  }

  @override
  String macroCompareLine(String current, String planned) {
    return 'current $current  |  planned $planned';
  }

  @override
  String get supsEmptyToday =>
      'No supplements logged for today.\nUse “+ ADD MORNING/AFTERNOON/EVENING/NIGHT SUPP” to plan.\n\nOnly your own logs appear here (per-account data).';

  @override
  String supsEmptyForDay(String date) {
    return 'No supplements logged for $date.\nUse the section “+ ADD … SUPP” buttons to plan.\n\nOnly your own logs appear here (per-account data).';
  }

  @override
  String get medsEmptyToday =>
      'No medications planned for today.\nUse “+ ADD MORNING/AFTERNOON/EVENING/NIGHT MED” to plan.\n\nOnly your own logs appear here (per-account data).';

  @override
  String medsEmptyForDay(String date) {
    return 'No medications planned for $date.\nUse the section “+ ADD … MED” buttons to plan.\n\nOnly your own logs appear here (per-account data).';
  }

  @override
  String supsAddBlockSupp(String block) {
    return '+ ADD $block SUPP';
  }

  @override
  String medsAddBlockMed(String block) {
    return '+ ADD $block MED';
  }

  @override
  String get settingsMeasurementSection => 'MEASUREMENT SYSTEM';

  @override
  String get settingsMeasurementSystem => 'Measurement System';

  @override
  String get settingsMetric => 'Metric (g, ml, kg)';

  @override
  String get settingsImperial => 'Imperial (oz, fl oz, lbs)';

  @override
  String get settingsNotificationsTitle => 'Enable Notifications / Reminders';

  @override
  String get settingsNotificationsSubtitle =>
      'When enabled, the app can schedule intake reminders.';

  @override
  String get settingsNotificationsDenied =>
      'Notifications permission is required. Please enable it in OS/Browser settings.';

  @override
  String get settingsUserProfileSection => 'USER PROFILE / METRICS';

  @override
  String get settingsHeightCmOptional => 'Height (cm), optional';

  @override
  String get settingsHeightInOptional => 'Height (in), optional';

  @override
  String get settingsWeightKgOptional => 'Weight (kg), optional';

  @override
  String get settingsWeightLbsOptional => 'Weight (lbs), optional';

  @override
  String get settingsAgeOptional => 'Age, optional';

  @override
  String get settingsBmiHeading => 'BMI (Body Mass Index)';

  @override
  String get settingsUserTargetsSection => 'USER TARGETS';

  @override
  String get settingsProteinG => 'Protein (g)';

  @override
  String get settingsCarbsG => 'Carbs (g)';

  @override
  String get settingsFatsG => 'Fats (g)';

  @override
  String get settingsCalories => 'Calories';

  @override
  String get bmiEnterImperial =>
      'Enter height (in) and weight (lbs) to compute BMI.';

  @override
  String get bmiEnterMetric =>
      'Enter height (cm) and weight (kg) to compute BMI.';

  @override
  String get bmiEnterValid => 'Enter valid height and weight.';

  @override
  String get bmiUnderweight => 'Underweight (under 18.5)';

  @override
  String get bmiNormal => 'Normal weight (18.5–24.9)';

  @override
  String get bmiOverweight => 'Overweight (25–29.9)';

  @override
  String get bmiObese => 'Obese (30 or higher)';

  @override
  String get bmiDash => '—';

  @override
  String get msgSignInDeleteLogs => 'You must be signed in to delete logs.';

  @override
  String get msgSignInUpdateLogs => 'You must be signed in to update logs.';

  @override
  String get msgSignInLogFood => 'You must be signed in to log food.';

  @override
  String get msgSignInLogSupps => 'You must be signed in to log supplements.';

  @override
  String get msgSignInLogMeds => 'You must be signed in to log medications.';

  @override
  String get msgSignInSave => 'You must be signed in to save.';

  @override
  String get msgSignInAddMeds => 'You must be signed in to add medications.';

  @override
  String get msgSignInReports => 'Sign in to view reports (RLS + user_id).';

  @override
  String get msgPlannedMealRemoved => 'Planned meal removed';

  @override
  String get msgEntryUpdated => 'Entry updated';

  @override
  String get msgEmptyRecordId => 'Error: empty record id';

  @override
  String get msgMealMarkedConsumed => 'Meal marked as consumed!';

  @override
  String get msgValidAmountGrams => 'Enter a valid amount in grams';

  @override
  String get msgValidAmount => 'Enter a valid amount';

  @override
  String get msgValidDose => 'Enter a valid dose';

  @override
  String get msgLogged => 'Logged.';

  @override
  String get msgLogDeleted => 'Log deleted.';

  @override
  String get msgLogUpdated => 'Log updated!';

  @override
  String get msgConfigSaved => 'CONFIG SAVED';

  @override
  String msgPlannedForMeal(String meal) {
    return 'PLANNED → $meal';
  }

  @override
  String logsError(String details) {
    return 'Logs error: $details';
  }

  @override
  String libraryError(String details) {
    return 'Library error: $details';
  }

  @override
  String pdfError(String details) {
    return 'PDF error: $details';
  }

  @override
  String get analyticsNoDaysInRange =>
      'No days in range — adjust the date range.';

  @override
  String get analyticsConsumedCaloriesTitle =>
      'CONSUMED FOOD — Calories by day';

  @override
  String get analyticsNoConsumedFood =>
      'No consumed food in range — chart baseline is 0.';

  @override
  String get analyticsGlycemicTitle =>
      'CONSUMED FOOD — Estimated glycemic load (GI × carbs where known)';

  @override
  String get analyticsNoGiData =>
      'No GI data / no carbs in logged items — chart baseline is 0.';

  @override
  String get analyticsSourceDailyLogs =>
      'Source: daily_logs · filtered by created_at (UTC day range, same as FUEL screen).';

  @override
  String get analyticsNoDataForRange => 'No data for range.';

  @override
  String get analyticsSuppAdherenceTitle =>
      'SUPPLEMENT ADHERENCE (taken vs missed)';

  @override
  String get analyticsMedAdherenceTitle =>
      'MEDICATION ADHERENCE (taken vs missed)';

  @override
  String get analyticsSourceDailyLogsShort =>
      'Source: daily_logs · created_at (UTC day range).';

  @override
  String get analyticsSourceMedLogs =>
      'Source: medication_logs · created_at (UTC day range). Rows include medication_id → medications(name) for labels in exports.';

  @override
  String get analyticsMissedExplainer =>
      'Missed = scheduled, not taken, and past the grace window (today: +60 min) or any prior day.';

  @override
  String get analyticsLegendTaken => 'Taken';

  @override
  String get analyticsLegendMissed => 'Missed';

  @override
  String analyticsRangeButton(String start, String end) {
    return 'Range: $start → $end';
  }

  @override
  String analyticsDailyPlanPdfDate(String date) {
    return 'Daily plan PDF date: $date';
  }

  @override
  String analyticsDailyPlanSubtitle(String date) {
    return '$date — tap “Daily plan date” above to change';
  }

  @override
  String analyticsWeeklySubtitle(String start, String end) {
    return 'Uses the current date range ($start → $end).';
  }

  @override
  String get addSupplementToLibrary => 'Add supplement to library';

  @override
  String get addMedicationToLibrary => 'Add medication to library';

  @override
  String get editLog => 'Edit log';

  @override
  String get deleteLog => 'Delete log';

  @override
  String get fuelLogIntakeTitle => 'LOG INTAKE';

  @override
  String get fuelIntakeTime => 'INTAKE TIME';

  @override
  String get fuelIntakeTimeDash => 'INTAKE TIME  —';

  @override
  String timeAt(String time) {
    return 'TIME  $time';
  }

  @override
  String intakeTimeAt(String time) {
    return 'INTAKE TIME  $time';
  }

  @override
  String get amountTaken => 'Amount Taken';

  @override
  String get numberOfConsecutiveDays => 'Number of consecutive days';

  @override
  String get saveAsDefaultDoseLibrary => 'Save as default dose in Library';

  @override
  String get addSupplementTitle => 'ADD SUPPLEMENT';

  @override
  String get amountLabelShort => 'Amount';

  @override
  String get fuelScheduleMultiDays => 'Schedule for multiple days';

  @override
  String get fuelRepeatDaysLabel => 'Enter number of days';

  @override
  String get fuelEditEntryTitle => 'EDIT ENTRY';

  @override
  String get fuelAmountGrams => 'AMOUNT (GRAMS)';

  @override
  String get fuelConsumptionTime => 'CONSUMPTION TIME';

  @override
  String fuelConsumptionTimeAt(String time) {
    return 'CONSUMPTION TIME  $time';
  }

  @override
  String get fuelPlanningSaved => 'PLANNING — saved as not consumed yet';

  @override
  String reminderTitleMeal(String name) {
    return 'Meal time: $name.';
  }

  @override
  String reminderAtTime(String time) {
    return 'Reminder: $time';
  }

  @override
  String get reminderBody => 'Reminder';

  @override
  String reminderTimeToTake(String name) {
    return 'Time to take your $name!';
  }

  @override
  String get supsLogIntakeTitle => 'LOG SUPPLEMENT INTAKE';

  @override
  String get medsLogIntakeTitle => 'LOG MEDICATION INTAKE';

  @override
  String get supsEditLogTitle => 'EDIT SUPPLEMENT LOG';

  @override
  String get medsEditLogTitle => 'EDIT MEDICATION LOG';

  @override
  String get supsNewSupplementTitle => 'NEW SUPPLEMENT';

  @override
  String get medsNewMedicationTitle => 'ADD MEDICATION';

  @override
  String get medsMedicationName => 'Name';

  @override
  String logSupplementBlock(String block) {
    return 'LOG SUPPLEMENT — $block';
  }

  @override
  String logMedicationBlock(String block) {
    return 'LOG MEDICATION — $block';
  }

  @override
  String get defaultSupplementName => 'Supplement';

  @override
  String get defaultMedicationName => 'Medication';

  @override
  String notificationReminderSuppIntake(String name) {
    return 'Reminder: $name intake.';
  }

  @override
  String notificationReminderMedIntake(String name) {
    return 'Reminder: $name intake.';
  }

  @override
  String get libraryAddNew => '+ Add New to Library';

  @override
  String libraryDefaultDose(String dose, String unit) {
    return 'Default $dose $unit (tap to edit at log time)';
  }

  @override
  String get libraryNoDefaultDose => 'No default dose (tap to enter now)';

  @override
  String get dialogSaving => '…';
}
