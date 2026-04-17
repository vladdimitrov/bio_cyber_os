import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_bg.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('bg'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'BIO_CYBER OS'**
  String get appTitle;

  /// No description provided for @navFuel.
  ///
  /// In en, this message translates to:
  /// **'FUEL'**
  String get navFuel;

  /// No description provided for @navSupps.
  ///
  /// In en, this message translates to:
  /// **'SUPPS'**
  String get navSupps;

  /// No description provided for @navMeds.
  ///
  /// In en, this message translates to:
  /// **'MEDS'**
  String get navMeds;

  /// No description provided for @navVitals.
  ///
  /// In en, this message translates to:
  /// **'VITALS'**
  String get navVitals;

  /// No description provided for @navReports.
  ///
  /// In en, this message translates to:
  /// **'REPORTS'**
  String get navReports;

  /// No description provided for @navLibrary.
  ///
  /// In en, this message translates to:
  /// **'LIBRARY'**
  String get navLibrary;

  /// No description provided for @navConfig.
  ///
  /// In en, this message translates to:
  /// **'CONFIG'**
  String get navConfig;

  /// No description provided for @screenFuelLog.
  ///
  /// In en, this message translates to:
  /// **'FUEL LOG'**
  String get screenFuelLog;

  /// No description provided for @screenSupps.
  ///
  /// In en, this message translates to:
  /// **'SUPPS'**
  String get screenSupps;

  /// No description provided for @screenMeds.
  ///
  /// In en, this message translates to:
  /// **'MEDS'**
  String get screenMeds;

  /// No description provided for @screenVitalsSymptoms.
  ///
  /// In en, this message translates to:
  /// **'VITALS & SYMPTOMS'**
  String get screenVitalsSymptoms;

  /// No description provided for @screenReports.
  ///
  /// In en, this message translates to:
  /// **'REPORTS'**
  String get screenReports;

  /// No description provided for @screenLibrary.
  ///
  /// In en, this message translates to:
  /// **'LIBRARY'**
  String get screenLibrary;

  /// No description provided for @screenConfig.
  ///
  /// In en, this message translates to:
  /// **'CONFIG'**
  String get screenConfig;

  /// No description provided for @addFood.
  ///
  /// In en, this message translates to:
  /// **'ADD FOOD'**
  String get addFood;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'SAVE'**
  String get save;

  /// No description provided for @saveData.
  ///
  /// In en, this message translates to:
  /// **'SAVE DATA'**
  String get saveData;

  /// No description provided for @saveConfig.
  ///
  /// In en, this message translates to:
  /// **'SAVE CONFIG'**
  String get saveConfig;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'CANCEL'**
  String get cancel;

  /// No description provided for @logIn.
  ///
  /// In en, this message translates to:
  /// **'LOG IN'**
  String get logIn;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'SIGN UP'**
  String get signUp;

  /// No description provided for @logOut.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logOut;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @languageSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'LANGUAGE'**
  String get languageSectionTitle;

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageLabel;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageBulgarian.
  ///
  /// In en, this message translates to:
  /// **'Bulgarian'**
  String get languageBulgarian;

  /// No description provided for @mealBreakfast.
  ///
  /// In en, this message translates to:
  /// **'BREAKFAST'**
  String get mealBreakfast;

  /// No description provided for @mealLunch.
  ///
  /// In en, this message translates to:
  /// **'LUNCH'**
  String get mealLunch;

  /// No description provided for @mealDinner.
  ///
  /// In en, this message translates to:
  /// **'DINNER'**
  String get mealDinner;

  /// No description provided for @mealExtraSnack.
  ///
  /// In en, this message translates to:
  /// **'EXTRA / SNACK'**
  String get mealExtraSnack;

  /// No description provided for @mealExtraUnsorted.
  ///
  /// In en, this message translates to:
  /// **'EXTRA'**
  String get mealExtraUnsorted;

  /// No description provided for @blockMorning.
  ///
  /// In en, this message translates to:
  /// **'MORNING'**
  String get blockMorning;

  /// No description provided for @blockAfternoon.
  ///
  /// In en, this message translates to:
  /// **'AFTERNOON'**
  String get blockAfternoon;

  /// No description provided for @blockEvening.
  ///
  /// In en, this message translates to:
  /// **'EVENING'**
  String get blockEvening;

  /// No description provided for @blockNight.
  ///
  /// In en, this message translates to:
  /// **'NIGHT'**
  String get blockNight;

  /// No description provided for @nutritionDailyProgress.
  ///
  /// In en, this message translates to:
  /// **'DAILY NUTRITION PROGRESS'**
  String get nutritionDailyProgress;

  /// No description provided for @nutritionChartLegend.
  ///
  /// In en, this message translates to:
  /// **'■ solid = consumed  ·  ░ dashed = planned extra  ·  │ goal = daily target'**
  String get nutritionChartLegend;

  /// No description provided for @nutritionProtein.
  ///
  /// In en, this message translates to:
  /// **'PROTEIN'**
  String get nutritionProtein;

  /// No description provided for @nutritionCarbs.
  ///
  /// In en, this message translates to:
  /// **'CARBS'**
  String get nutritionCarbs;

  /// No description provided for @nutritionFats.
  ///
  /// In en, this message translates to:
  /// **'FATS'**
  String get nutritionFats;

  /// No description provided for @nutritionCal.
  ///
  /// In en, this message translates to:
  /// **'CAL'**
  String get nutritionCal;

  /// No description provided for @nutritionEatenShort.
  ///
  /// In en, this message translates to:
  /// **'eaten'**
  String get nutritionEatenShort;

  /// No description provided for @nutritionWithPlanShort.
  ///
  /// In en, this message translates to:
  /// **'w/ plan'**
  String get nutritionWithPlanShort;

  /// No description provided for @nutritionTargetShort.
  ///
  /// In en, this message translates to:
  /// **'target'**
  String get nutritionTargetShort;

  /// No description provided for @labelEaten.
  ///
  /// In en, this message translates to:
  /// **'Eaten'**
  String get labelEaten;

  /// No description provided for @labelPlanned.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get labelPlanned;

  /// No description provided for @labelGoal.
  ///
  /// In en, this message translates to:
  /// **'Goal'**
  String get labelGoal;

  /// No description provided for @labelCurrent.
  ///
  /// In en, this message translates to:
  /// **'current'**
  String get labelCurrent;

  /// No description provided for @labelPlannedLower.
  ///
  /// In en, this message translates to:
  /// **'planned'**
  String get labelPlannedLower;

  /// No description provided for @dailyRecords.
  ///
  /// In en, this message translates to:
  /// **'DAILY RECORDS'**
  String get dailyRecords;

  /// No description provided for @actionAddPlan.
  ///
  /// In en, this message translates to:
  /// **'PLAN'**
  String get actionAddPlan;

  /// No description provided for @actionAddExtra.
  ///
  /// In en, this message translates to:
  /// **'+ ADD EXTRA / SNACK'**
  String get actionAddExtra;

  /// No description provided for @take.
  ///
  /// In en, this message translates to:
  /// **'TAKE'**
  String get take;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @printExport.
  ///
  /// In en, this message translates to:
  /// **'PRINT / EXPORT'**
  String get printExport;

  /// No description provided for @printDailyPlanTitle.
  ///
  /// In en, this message translates to:
  /// **'Print Daily Plan (selected date)'**
  String get printDailyPlanTitle;

  /// No description provided for @exportWeeklySummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Export Weekly Summary (PDF)'**
  String get exportWeeklySummaryTitle;

  /// No description provided for @selectDateRange.
  ///
  /// In en, this message translates to:
  /// **'Select date range'**
  String get selectDateRange;

  /// No description provided for @prevDay.
  ///
  /// In en, this message translates to:
  /// **'Previous day'**
  String get prevDay;

  /// No description provided for @nextDay.
  ///
  /// In en, this message translates to:
  /// **'Next day'**
  String get nextDay;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @logVerb.
  ///
  /// In en, this message translates to:
  /// **'LOG'**
  String get logVerb;

  /// No description provided for @unit.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get unit;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @number.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get number;

  /// No description provided for @requiredField.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get requiredField;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search…'**
  String get searchHint;

  /// No description provided for @noItemsFound.
  ///
  /// In en, this message translates to:
  /// **'No items found'**
  String get noItemsFound;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @missed.
  ///
  /// In en, this message translates to:
  /// **'MISSED'**
  String get missed;

  /// No description provided for @plannedUpper.
  ///
  /// In en, this message translates to:
  /// **'PLANNED'**
  String get plannedUpper;

  /// No description provided for @consumedUpper.
  ///
  /// In en, this message translates to:
  /// **'CONSUMED'**
  String get consumedUpper;

  /// No description provided for @subtotal.
  ///
  /// In en, this message translates to:
  /// **'SUBTOTAL'**
  String get subtotal;

  /// No description provided for @fuelMacrosLine.
  ///
  /// In en, this message translates to:
  /// **'P: {p}g | C: {c}g | F: {f}g | {cal} kcal'**
  String fuelMacrosLine(String p, String c, String f, String cal);

  /// No description provided for @reminder.
  ///
  /// In en, this message translates to:
  /// **'REMINDER'**
  String get reminder;

  /// No description provided for @none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// No description provided for @specific.
  ///
  /// In en, this message translates to:
  /// **'Specific'**
  String get specific;

  /// No description provided for @minutesBefore.
  ///
  /// In en, this message translates to:
  /// **'Minutes before'**
  String get minutesBefore;

  /// No description provided for @specificTime.
  ///
  /// In en, this message translates to:
  /// **'Specific time'**
  String get specificTime;

  /// No description provided for @minutes.
  ///
  /// In en, this message translates to:
  /// **'Minutes'**
  String get minutes;

  /// No description provided for @pickTime.
  ///
  /// In en, this message translates to:
  /// **'Pick time'**
  String get pickTime;

  /// No description provided for @recipe.
  ///
  /// In en, this message translates to:
  /// **'Recipe'**
  String get recipe;

  /// No description provided for @ingredient.
  ///
  /// In en, this message translates to:
  /// **'Ingredient'**
  String get ingredient;

  /// No description provided for @planTag.
  ///
  /// In en, this message translates to:
  /// **'[PLAN]'**
  String get planTag;

  /// No description provided for @gramsSuffix.
  ///
  /// In en, this message translates to:
  /// **'g'**
  String get gramsSuffix;

  /// No description provided for @fuelNoMealsToday.
  ///
  /// In en, this message translates to:
  /// **'No meals logged for today yet. Use “+ ADD BREAKFAST/LUNCH/DINNER” (or PLAN) to log food — your history will appear here.'**
  String get fuelNoMealsToday;

  /// No description provided for @fuelNoMealsForDay.
  ///
  /// In en, this message translates to:
  /// **'No meals logged for {date}. RLS shows only your own entries; use the add buttons below when you are ready to log this day.'**
  String fuelNoMealsForDay(String date);

  /// No description provided for @fuelNoItemsBlock.
  ///
  /// In en, this message translates to:
  /// **'No items for this block yet.\nTap “+ ADD …” or “PLAN” above.'**
  String get fuelNoItemsBlock;

  /// No description provided for @macroSummaryLine.
  ///
  /// In en, this message translates to:
  /// **'P {p}g  C {c}g  F {f}g  {cal} kcal'**
  String macroSummaryLine(String p, String c, String f, String cal);

  /// No description provided for @macroCompareLine.
  ///
  /// In en, this message translates to:
  /// **'current {current}  |  planned {planned}'**
  String macroCompareLine(String current, String planned);

  /// No description provided for @supsEmptyToday.
  ///
  /// In en, this message translates to:
  /// **'No supplements logged for today.\nUse “+ ADD MORNING/AFTERNOON/EVENING/NIGHT SUPP” to plan.\n\nOnly your own logs appear here (per-account data).'**
  String get supsEmptyToday;

  /// No description provided for @supsEmptyForDay.
  ///
  /// In en, this message translates to:
  /// **'No supplements logged for {date}.\nUse the section “+ ADD … SUPP” buttons to plan.\n\nOnly your own logs appear here (per-account data).'**
  String supsEmptyForDay(String date);

  /// No description provided for @medsEmptyToday.
  ///
  /// In en, this message translates to:
  /// **'No medications planned for today.\nUse “+ ADD MORNING/AFTERNOON/EVENING/NIGHT MED” to plan.\n\nOnly your own logs appear here (per-account data).'**
  String get medsEmptyToday;

  /// No description provided for @medsEmptyForDay.
  ///
  /// In en, this message translates to:
  /// **'No medications planned for {date}.\nUse the section “+ ADD … MED” buttons to plan.\n\nOnly your own logs appear here (per-account data).'**
  String medsEmptyForDay(String date);

  /// No description provided for @supsAddBlockSupp.
  ///
  /// In en, this message translates to:
  /// **'+ ADD {block} SUPP'**
  String supsAddBlockSupp(String block);

  /// No description provided for @medsAddBlockMed.
  ///
  /// In en, this message translates to:
  /// **'+ ADD {block} MED'**
  String medsAddBlockMed(String block);

  /// No description provided for @settingsMeasurementSection.
  ///
  /// In en, this message translates to:
  /// **'MEASUREMENT SYSTEM'**
  String get settingsMeasurementSection;

  /// No description provided for @settingsMeasurementSystem.
  ///
  /// In en, this message translates to:
  /// **'Measurement System'**
  String get settingsMeasurementSystem;

  /// No description provided for @settingsMetric.
  ///
  /// In en, this message translates to:
  /// **'Metric (g, ml, kg)'**
  String get settingsMetric;

  /// No description provided for @settingsImperial.
  ///
  /// In en, this message translates to:
  /// **'Imperial (oz, fl oz, lbs)'**
  String get settingsImperial;

  /// No description provided for @settingsNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable Notifications / Reminders'**
  String get settingsNotificationsTitle;

  /// No description provided for @settingsNotificationsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When enabled, the app can schedule intake reminders.'**
  String get settingsNotificationsSubtitle;

  /// No description provided for @settingsNotificationsDenied.
  ///
  /// In en, this message translates to:
  /// **'Notifications permission is required. Please enable it in OS/Browser settings.'**
  String get settingsNotificationsDenied;

  /// No description provided for @settingsUserProfileSection.
  ///
  /// In en, this message translates to:
  /// **'USER PROFILE / METRICS'**
  String get settingsUserProfileSection;

  /// No description provided for @settingsHeightCmOptional.
  ///
  /// In en, this message translates to:
  /// **'Height (cm), optional'**
  String get settingsHeightCmOptional;

  /// No description provided for @settingsHeightInOptional.
  ///
  /// In en, this message translates to:
  /// **'Height (in), optional'**
  String get settingsHeightInOptional;

  /// No description provided for @settingsWeightKgOptional.
  ///
  /// In en, this message translates to:
  /// **'Weight (kg), optional'**
  String get settingsWeightKgOptional;

  /// No description provided for @settingsWeightLbsOptional.
  ///
  /// In en, this message translates to:
  /// **'Weight (lbs), optional'**
  String get settingsWeightLbsOptional;

  /// No description provided for @settingsAgeOptional.
  ///
  /// In en, this message translates to:
  /// **'Age, optional'**
  String get settingsAgeOptional;

  /// No description provided for @settingsBmiHeading.
  ///
  /// In en, this message translates to:
  /// **'BMI (Body Mass Index)'**
  String get settingsBmiHeading;

  /// No description provided for @settingsUserTargetsSection.
  ///
  /// In en, this message translates to:
  /// **'USER TARGETS'**
  String get settingsUserTargetsSection;

  /// No description provided for @settingsProteinG.
  ///
  /// In en, this message translates to:
  /// **'Protein (g)'**
  String get settingsProteinG;

  /// No description provided for @settingsCarbsG.
  ///
  /// In en, this message translates to:
  /// **'Carbs (g)'**
  String get settingsCarbsG;

  /// No description provided for @settingsFatsG.
  ///
  /// In en, this message translates to:
  /// **'Fats (g)'**
  String get settingsFatsG;

  /// No description provided for @settingsCalories.
  ///
  /// In en, this message translates to:
  /// **'Calories'**
  String get settingsCalories;

  /// No description provided for @bmiEnterImperial.
  ///
  /// In en, this message translates to:
  /// **'Enter height (in) and weight (lbs) to compute BMI.'**
  String get bmiEnterImperial;

  /// No description provided for @bmiEnterMetric.
  ///
  /// In en, this message translates to:
  /// **'Enter height (cm) and weight (kg) to compute BMI.'**
  String get bmiEnterMetric;

  /// No description provided for @bmiEnterValid.
  ///
  /// In en, this message translates to:
  /// **'Enter valid height and weight.'**
  String get bmiEnterValid;

  /// No description provided for @bmiUnderweight.
  ///
  /// In en, this message translates to:
  /// **'Underweight (under 18.5)'**
  String get bmiUnderweight;

  /// No description provided for @bmiNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal weight (18.5–24.9)'**
  String get bmiNormal;

  /// No description provided for @bmiOverweight.
  ///
  /// In en, this message translates to:
  /// **'Overweight (25–29.9)'**
  String get bmiOverweight;

  /// No description provided for @bmiObese.
  ///
  /// In en, this message translates to:
  /// **'Obese (30 or higher)'**
  String get bmiObese;

  /// No description provided for @bmiDash.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get bmiDash;

  /// No description provided for @msgSignInDeleteLogs.
  ///
  /// In en, this message translates to:
  /// **'You must be signed in to delete logs.'**
  String get msgSignInDeleteLogs;

  /// No description provided for @msgSignInUpdateLogs.
  ///
  /// In en, this message translates to:
  /// **'You must be signed in to update logs.'**
  String get msgSignInUpdateLogs;

  /// No description provided for @msgSignInLogFood.
  ///
  /// In en, this message translates to:
  /// **'You must be signed in to log food.'**
  String get msgSignInLogFood;

  /// No description provided for @msgSignInLogSupps.
  ///
  /// In en, this message translates to:
  /// **'You must be signed in to log supplements.'**
  String get msgSignInLogSupps;

  /// No description provided for @msgSignInLogMeds.
  ///
  /// In en, this message translates to:
  /// **'You must be signed in to log medications.'**
  String get msgSignInLogMeds;

  /// No description provided for @msgSignInSave.
  ///
  /// In en, this message translates to:
  /// **'You must be signed in to save.'**
  String get msgSignInSave;

  /// No description provided for @msgSignInAddMeds.
  ///
  /// In en, this message translates to:
  /// **'You must be signed in to add medications.'**
  String get msgSignInAddMeds;

  /// No description provided for @msgSignInReports.
  ///
  /// In en, this message translates to:
  /// **'Sign in to view reports (RLS + user_id).'**
  String get msgSignInReports;

  /// No description provided for @msgPlannedMealRemoved.
  ///
  /// In en, this message translates to:
  /// **'Planned meal removed'**
  String get msgPlannedMealRemoved;

  /// No description provided for @msgEntryUpdated.
  ///
  /// In en, this message translates to:
  /// **'Entry updated'**
  String get msgEntryUpdated;

  /// No description provided for @msgEmptyRecordId.
  ///
  /// In en, this message translates to:
  /// **'Error: empty record id'**
  String get msgEmptyRecordId;

  /// No description provided for @msgMealMarkedConsumed.
  ///
  /// In en, this message translates to:
  /// **'Meal marked as consumed!'**
  String get msgMealMarkedConsumed;

  /// No description provided for @msgValidAmountGrams.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount in grams'**
  String get msgValidAmountGrams;

  /// No description provided for @msgValidAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount'**
  String get msgValidAmount;

  /// No description provided for @msgValidDose.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid dose'**
  String get msgValidDose;

  /// No description provided for @msgLogged.
  ///
  /// In en, this message translates to:
  /// **'Logged.'**
  String get msgLogged;

  /// No description provided for @msgLogDeleted.
  ///
  /// In en, this message translates to:
  /// **'Log deleted.'**
  String get msgLogDeleted;

  /// No description provided for @msgLogUpdated.
  ///
  /// In en, this message translates to:
  /// **'Log updated!'**
  String get msgLogUpdated;

  /// No description provided for @msgConfigSaved.
  ///
  /// In en, this message translates to:
  /// **'CONFIG SAVED'**
  String get msgConfigSaved;

  /// No description provided for @msgPlannedForMeal.
  ///
  /// In en, this message translates to:
  /// **'PLANNED → {meal}'**
  String msgPlannedForMeal(String meal);

  /// No description provided for @logsError.
  ///
  /// In en, this message translates to:
  /// **'Logs error: {details}'**
  String logsError(String details);

  /// No description provided for @libraryError.
  ///
  /// In en, this message translates to:
  /// **'Library error: {details}'**
  String libraryError(String details);

  /// No description provided for @pdfError.
  ///
  /// In en, this message translates to:
  /// **'PDF error: {details}'**
  String pdfError(String details);

  /// No description provided for @analyticsNoDaysInRange.
  ///
  /// In en, this message translates to:
  /// **'No days in range — adjust the date range.'**
  String get analyticsNoDaysInRange;

  /// No description provided for @analyticsConsumedCaloriesTitle.
  ///
  /// In en, this message translates to:
  /// **'CONSUMED FOOD — Calories by day'**
  String get analyticsConsumedCaloriesTitle;

  /// No description provided for @analyticsNoConsumedFood.
  ///
  /// In en, this message translates to:
  /// **'No consumed food in range — chart baseline is 0.'**
  String get analyticsNoConsumedFood;

  /// No description provided for @analyticsGlycemicTitle.
  ///
  /// In en, this message translates to:
  /// **'CONSUMED FOOD — Estimated glycemic load (GI × carbs where known)'**
  String get analyticsGlycemicTitle;

  /// No description provided for @analyticsNoGiData.
  ///
  /// In en, this message translates to:
  /// **'No GI data / no carbs in logged items — chart baseline is 0.'**
  String get analyticsNoGiData;

  /// No description provided for @analyticsSourceDailyLogs.
  ///
  /// In en, this message translates to:
  /// **'Source: daily_logs · filtered by created_at (UTC day range, same as FUEL screen).'**
  String get analyticsSourceDailyLogs;

  /// No description provided for @analyticsNoDataForRange.
  ///
  /// In en, this message translates to:
  /// **'No data for range.'**
  String get analyticsNoDataForRange;

  /// No description provided for @analyticsSuppAdherenceTitle.
  ///
  /// In en, this message translates to:
  /// **'SUPPLEMENT ADHERENCE (taken vs missed)'**
  String get analyticsSuppAdherenceTitle;

  /// No description provided for @analyticsMedAdherenceTitle.
  ///
  /// In en, this message translates to:
  /// **'MEDICATION ADHERENCE (taken vs missed)'**
  String get analyticsMedAdherenceTitle;

  /// No description provided for @analyticsSourceDailyLogsShort.
  ///
  /// In en, this message translates to:
  /// **'Source: daily_logs · created_at (UTC day range).'**
  String get analyticsSourceDailyLogsShort;

  /// No description provided for @analyticsSourceMedLogs.
  ///
  /// In en, this message translates to:
  /// **'Source: medication_logs · created_at (UTC day range). Rows include medication_id → medications(name) for labels in exports.'**
  String get analyticsSourceMedLogs;

  /// No description provided for @analyticsMissedExplainer.
  ///
  /// In en, this message translates to:
  /// **'Missed = scheduled, not taken, and past the grace window (today: +60 min) or any prior day.'**
  String get analyticsMissedExplainer;

  /// No description provided for @analyticsLegendTaken.
  ///
  /// In en, this message translates to:
  /// **'Taken'**
  String get analyticsLegendTaken;

  /// No description provided for @analyticsLegendMissed.
  ///
  /// In en, this message translates to:
  /// **'Missed'**
  String get analyticsLegendMissed;

  /// No description provided for @analyticsRangeButton.
  ///
  /// In en, this message translates to:
  /// **'Range: {start} → {end}'**
  String analyticsRangeButton(String start, String end);

  /// No description provided for @analyticsDailyPlanPdfDate.
  ///
  /// In en, this message translates to:
  /// **'Daily plan PDF date: {date}'**
  String analyticsDailyPlanPdfDate(String date);

  /// No description provided for @analyticsDailyPlanSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{date} — tap “Daily plan date” above to change'**
  String analyticsDailyPlanSubtitle(String date);

  /// No description provided for @analyticsWeeklySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Uses the current date range ({start} → {end}).'**
  String analyticsWeeklySubtitle(String start, String end);

  /// No description provided for @addSupplementToLibrary.
  ///
  /// In en, this message translates to:
  /// **'Add supplement to library'**
  String get addSupplementToLibrary;

  /// No description provided for @addMedicationToLibrary.
  ///
  /// In en, this message translates to:
  /// **'Add medication to library'**
  String get addMedicationToLibrary;

  /// No description provided for @editLog.
  ///
  /// In en, this message translates to:
  /// **'Edit log'**
  String get editLog;

  /// No description provided for @deleteLog.
  ///
  /// In en, this message translates to:
  /// **'Delete log'**
  String get deleteLog;

  /// No description provided for @fuelLogIntakeTitle.
  ///
  /// In en, this message translates to:
  /// **'LOG INTAKE'**
  String get fuelLogIntakeTitle;

  /// No description provided for @fuelIntakeTime.
  ///
  /// In en, this message translates to:
  /// **'INTAKE TIME'**
  String get fuelIntakeTime;

  /// No description provided for @fuelIntakeTimeDash.
  ///
  /// In en, this message translates to:
  /// **'INTAKE TIME  —'**
  String get fuelIntakeTimeDash;

  /// No description provided for @timeAt.
  ///
  /// In en, this message translates to:
  /// **'TIME  {time}'**
  String timeAt(String time);

  /// No description provided for @intakeTimeAt.
  ///
  /// In en, this message translates to:
  /// **'INTAKE TIME  {time}'**
  String intakeTimeAt(String time);

  /// No description provided for @amountTaken.
  ///
  /// In en, this message translates to:
  /// **'Amount Taken'**
  String get amountTaken;

  /// No description provided for @numberOfConsecutiveDays.
  ///
  /// In en, this message translates to:
  /// **'Number of consecutive days'**
  String get numberOfConsecutiveDays;

  /// No description provided for @saveAsDefaultDoseLibrary.
  ///
  /// In en, this message translates to:
  /// **'Save as default dose in Library'**
  String get saveAsDefaultDoseLibrary;

  /// No description provided for @addSupplementTitle.
  ///
  /// In en, this message translates to:
  /// **'ADD SUPPLEMENT'**
  String get addSupplementTitle;

  /// No description provided for @amountLabelShort.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amountLabelShort;

  /// No description provided for @fuelScheduleMultiDays.
  ///
  /// In en, this message translates to:
  /// **'Schedule for multiple days'**
  String get fuelScheduleMultiDays;

  /// No description provided for @fuelRepeatDaysLabel.
  ///
  /// In en, this message translates to:
  /// **'Enter number of days'**
  String get fuelRepeatDaysLabel;

  /// No description provided for @fuelEditEntryTitle.
  ///
  /// In en, this message translates to:
  /// **'EDIT ENTRY'**
  String get fuelEditEntryTitle;

  /// No description provided for @fuelAmountGrams.
  ///
  /// In en, this message translates to:
  /// **'AMOUNT (GRAMS)'**
  String get fuelAmountGrams;

  /// No description provided for @fuelConsumptionTime.
  ///
  /// In en, this message translates to:
  /// **'CONSUMPTION TIME'**
  String get fuelConsumptionTime;

  /// No description provided for @fuelConsumptionTimeAt.
  ///
  /// In en, this message translates to:
  /// **'CONSUMPTION TIME  {time}'**
  String fuelConsumptionTimeAt(String time);

  /// No description provided for @fuelPlanningSaved.
  ///
  /// In en, this message translates to:
  /// **'PLANNING — saved as not consumed yet'**
  String get fuelPlanningSaved;

  /// No description provided for @reminderTitleMeal.
  ///
  /// In en, this message translates to:
  /// **'Meal time: {name}.'**
  String reminderTitleMeal(String name);

  /// No description provided for @reminderAtTime.
  ///
  /// In en, this message translates to:
  /// **'Reminder: {time}'**
  String reminderAtTime(String time);

  /// No description provided for @reminderBody.
  ///
  /// In en, this message translates to:
  /// **'Reminder'**
  String get reminderBody;

  /// No description provided for @reminderTimeToTake.
  ///
  /// In en, this message translates to:
  /// **'Time to take your {name}!'**
  String reminderTimeToTake(String name);

  /// No description provided for @supsLogIntakeTitle.
  ///
  /// In en, this message translates to:
  /// **'LOG SUPPLEMENT INTAKE'**
  String get supsLogIntakeTitle;

  /// No description provided for @medsLogIntakeTitle.
  ///
  /// In en, this message translates to:
  /// **'LOG MEDICATION INTAKE'**
  String get medsLogIntakeTitle;

  /// No description provided for @supsEditLogTitle.
  ///
  /// In en, this message translates to:
  /// **'EDIT SUPPLEMENT LOG'**
  String get supsEditLogTitle;

  /// No description provided for @medsEditLogTitle.
  ///
  /// In en, this message translates to:
  /// **'EDIT MEDICATION LOG'**
  String get medsEditLogTitle;

  /// No description provided for @supsNewSupplementTitle.
  ///
  /// In en, this message translates to:
  /// **'NEW SUPPLEMENT'**
  String get supsNewSupplementTitle;

  /// No description provided for @medsNewMedicationTitle.
  ///
  /// In en, this message translates to:
  /// **'ADD MEDICATION'**
  String get medsNewMedicationTitle;

  /// No description provided for @medsMedicationName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get medsMedicationName;

  /// No description provided for @logSupplementBlock.
  ///
  /// In en, this message translates to:
  /// **'LOG SUPPLEMENT — {block}'**
  String logSupplementBlock(String block);

  /// No description provided for @logMedicationBlock.
  ///
  /// In en, this message translates to:
  /// **'LOG MEDICATION — {block}'**
  String logMedicationBlock(String block);

  /// No description provided for @defaultSupplementName.
  ///
  /// In en, this message translates to:
  /// **'Supplement'**
  String get defaultSupplementName;

  /// No description provided for @defaultMedicationName.
  ///
  /// In en, this message translates to:
  /// **'Medication'**
  String get defaultMedicationName;

  /// No description provided for @notificationReminderSuppIntake.
  ///
  /// In en, this message translates to:
  /// **'Reminder: {name} intake.'**
  String notificationReminderSuppIntake(String name);

  /// No description provided for @notificationReminderMedIntake.
  ///
  /// In en, this message translates to:
  /// **'Reminder: {name} intake.'**
  String notificationReminderMedIntake(String name);

  /// No description provided for @libraryAddNew.
  ///
  /// In en, this message translates to:
  /// **'+ Add New to Library'**
  String get libraryAddNew;

  /// No description provided for @libraryDefaultDose.
  ///
  /// In en, this message translates to:
  /// **'Default {dose} {unit} (tap to edit at log time)'**
  String libraryDefaultDose(String dose, String unit);

  /// No description provided for @libraryNoDefaultDose.
  ///
  /// In en, this message translates to:
  /// **'No default dose (tap to enter now)'**
  String get libraryNoDefaultDose;

  /// No description provided for @dialogSaving.
  ///
  /// In en, this message translates to:
  /// **'…'**
  String get dialogSaving;

  /// No description provided for @intakeAddModeLogNow.
  ///
  /// In en, this message translates to:
  /// **'LOG NOW'**
  String get intakeAddModeLogNow;

  /// No description provided for @intakeAddModePlan.
  ///
  /// In en, this message translates to:
  /// **'PLAN'**
  String get intakeAddModePlan;

  /// No description provided for @intakeAddModeHint.
  ///
  /// In en, this message translates to:
  /// **'Planned rows stay open until you tap TAKE.'**
  String get intakeAddModeHint;

  /// No description provided for @notificationTimeForIntake.
  ///
  /// In en, this message translates to:
  /// **'Time for your intake: {name}'**
  String notificationTimeForIntake(String name);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['bg', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bg':
      return AppLocalizationsBg();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
