// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Bulgarian (`bg`).
class AppLocalizationsBg extends AppLocalizations {
  AppLocalizationsBg([String locale = 'bg']) : super(locale);

  @override
  String get appTitle => 'BIO_CYBER OS';

  @override
  String get navFuel => 'ГОРИВО';

  @override
  String get navSupps => 'ДОБАВКИ';

  @override
  String get navMeds => 'ЛЕКАРСТВА';

  @override
  String get navVitals => 'ПОКАЗАТЕЛИ';

  @override
  String get navReports => 'ОТЧЕТИ';

  @override
  String get navLibrary => 'БИБЛИОТЕКА';

  @override
  String get navConfig => 'НАСТРОЙКИ';

  @override
  String get screenFuelLog => 'ДНЕВНИК — ГОРИВО';

  @override
  String get screenSupps => 'ДОБАВКИ';

  @override
  String get screenMeds => 'ЛЕКАРСТВА';

  @override
  String get screenVitalsSymptoms => 'ПОКАЗАТЕЛИ И СИМПТОМИ';

  @override
  String get screenReports => 'ОТЧЕТИ';

  @override
  String get screenLibrary => 'БИБЛИОТЕКА';

  @override
  String get screenConfig => 'НАСТРОЙКИ';

  @override
  String get addFood => 'ДОБАВИ ХРАНА';

  @override
  String get save => 'ЗАПАЗИ';

  @override
  String get saveData => 'ЗАПАЗИ ДАННИ';

  @override
  String get saveConfig => 'ЗАПАЗИ НАСТРОЙКИ';

  @override
  String get cancel => 'ОТКАЗ';

  @override
  String get logIn => 'ВХОД';

  @override
  String get signUp => 'РЕГИСТРАЦИЯ';

  @override
  String get logOut => 'Изход';

  @override
  String get refresh => 'Опресни';

  @override
  String get languageSectionTitle => 'ЕЗИК';

  @override
  String get languageLabel => 'Език';

  @override
  String get languageSystem => 'Системен';

  @override
  String get languageEnglish => 'Английски';

  @override
  String get languageBulgarian => 'Български';

  @override
  String get mealBreakfast => 'ЗАКУСКА';

  @override
  String get mealLunch => 'ОБЯД';

  @override
  String get mealDinner => 'ВЕЧЕРЯ';

  @override
  String get mealExtraSnack => 'ДОПЪЛНИТЕЛНО / ЗАКУСКА';

  @override
  String get mealExtraUnsorted => 'ДОПЪЛНИТЕЛНО';

  @override
  String get blockMorning => 'СУТРИН';

  @override
  String get blockAfternoon => 'СЛЕДОБЕД';

  @override
  String get blockEvening => 'ВЕЧЕР';

  @override
  String get blockNight => 'НОЩ';

  @override
  String get nutritionDailyProgress => 'ДНЕВЕН ХРАНИТЕЛЕН ПРОГРЕС';

  @override
  String get nutritionChartLegend =>
      '■ плътно = прието  ·  ░ пунктир = планирано допълнително  ·  │ цел = дневна норма';

  @override
  String get nutritionProtein => 'ПРОТЕИН';

  @override
  String get nutritionCarbs => 'ВЪГЛЕХИДРАТИ';

  @override
  String get nutritionFats => 'МАЗНИНИ';

  @override
  String get nutritionCal => 'КАЛОРИИ';

  @override
  String get nutritionEatenShort => 'прието';

  @override
  String get nutritionWithPlanShort => 'с план';

  @override
  String get nutritionTargetShort => 'цел';

  @override
  String get labelEaten => 'Прието';

  @override
  String get labelPlanned => 'Планирано';

  @override
  String get labelGoal => 'Цел';

  @override
  String get labelCurrent => 'текущо';

  @override
  String get labelPlannedLower => 'планирано';

  @override
  String get dailyRecords => 'ДНЕВНИ ЗАПИСИ';

  @override
  String get actionAddPlan => 'ПЛАН';

  @override
  String get actionAddExtra => '+ ДОБАВИ ДОПЪЛНИТЕЛНО / ЗАКУСКА';

  @override
  String get take => 'ПРИЕМИ';

  @override
  String get edit => 'Редактирай';

  @override
  String get delete => 'Изтрий';

  @override
  String get printExport => 'ПЕЧАТ / ЕКСПОРТ';

  @override
  String get printDailyPlanTitle => 'Печат на дневен план (избрана дата)';

  @override
  String get exportWeeklySummaryTitle => 'Експорт на седмично обобщение (PDF)';

  @override
  String get selectDateRange => 'Изберете период от дати';

  @override
  String get prevDay => 'Предишен ден';

  @override
  String get nextDay => 'Следващ ден';

  @override
  String get close => 'Затвори';

  @override
  String get ok => 'ОК';

  @override
  String get logVerb => 'ЗАПИШИ';

  @override
  String get unit => 'Мерна единица';

  @override
  String get notes => 'Бележки';

  @override
  String get number => 'Число';

  @override
  String get requiredField => 'Задължително';

  @override
  String get searchHint => 'Търсене…';

  @override
  String get noItemsFound => 'Няма намерени записи';

  @override
  String get unknown => 'Неизвестно';

  @override
  String get missed => 'ПРОПУСНАТО';

  @override
  String get plannedUpper => 'ПЛАНИРАНО';

  @override
  String get consumedUpper => 'ПРИЕТО';

  @override
  String get subtotal => 'МЕЖДИННА СУМА';

  @override
  String fuelMacrosLine(String p, String c, String f, String cal) {
    return 'P: ${p}g | C: ${c}g | F: ${f}g | $cal kcal';
  }

  @override
  String get reminder => 'НАПОМНЯНЕ';

  @override
  String get none => 'Няма';

  @override
  String get specific => 'Конкретно време';

  @override
  String get minutesBefore => 'Минути преди';

  @override
  String get specificTime => 'Конкретен час';

  @override
  String get minutes => 'Минути';

  @override
  String get pickTime => 'Избор на час';

  @override
  String get recipe => 'Рецепта';

  @override
  String get ingredient => 'Съставка';

  @override
  String get planTag => '[ПЛАН]';

  @override
  String get gramsSuffix => 'g';

  @override
  String get fuelNoMealsToday =>
      'Все още няма записани хранения за днес. Използвайте „+ ДОБАВИ ЗАКУСКА/ОБЯД/ВЕЧЕРЯ“ (или ПЛАН), за да запишете храна — историята ще се появи тук.';

  @override
  String fuelNoMealsForDay(String date) {
    return 'Няма записани хранения за $date. RLS показва само вашите записи; използвайте бутоните за добавяне по-долу, когато сте готови да логнете този ден.';
  }

  @override
  String get fuelNoItemsBlock =>
      'Все още няма записи в този блок.\nДокоснете „+ ДОБАВИ …“ или „ПЛАН“ по-горе.';

  @override
  String macroSummaryLine(String p, String c, String f, String cal) {
    return 'П ${p}g  В ${c}g  М ${f}g  $cal kcal';
  }

  @override
  String macroCompareLine(String current, String planned) {
    return 'текущо $current  |  планирано $planned';
  }

  @override
  String get supsEmptyToday =>
      'Няма записани добавки за днес.\nИзползвайте „+ ДОБАВИ СУТРИН/СЛЕДОБЕД/ВЕЧЕР/НОЩ ДОБАВКА“, за да планирате.\n\nТук се показват само вашите записи (по акаунт).';

  @override
  String supsEmptyForDay(String date) {
    return 'Няма записани добавки за $date.\nИзползвайте бутоните „+ ДОБАВИ … ДОБАВКА“ в секциите, за да планирате.\n\nТук се показват само вашите записи (по акаунт).';
  }

  @override
  String get medsEmptyToday =>
      'Няма планирани лекарства за днес.\nИзползвайте „+ ДОБАВИ СУТРИН/СЛЕДОБЕД/ВЕЧЕР/НОЩ ЛЕКАРСТВО“, за да планирате.\n\nТук се показват само вашите записи (по акаунт).';

  @override
  String medsEmptyForDay(String date) {
    return 'Няма планирани лекарства за $date.\nИзползвайте бутоните „+ ДОБАВИ … ЛЕКАРСТВО“ в секциите, за да планирате.\n\nТук се показват само вашите записи (по акаунт).';
  }

  @override
  String supsAddBlockSupp(String block) {
    return '+ ДОБАВИ $block ДОБАВКА';
  }

  @override
  String medsAddBlockMed(String block) {
    return '+ ДОБАВИ $block ЛЕКАРСТВО';
  }

  @override
  String get settingsMeasurementSection => 'МЕРНА СИСТЕМА';

  @override
  String get settingsMeasurementSystem => 'Мерна система';

  @override
  String get settingsMetric => 'Метрична (g, ml, kg)';

  @override
  String get settingsImperial => 'Имперска (oz, fl oz, lbs)';

  @override
  String get settingsNotificationsTitle => 'Включи известия / напомняния';

  @override
  String get settingsNotificationsSubtitle =>
      'Когато са включени, приложението може да планира напомняния за прием.';

  @override
  String get settingsNotificationsDenied =>
      'Необходимо е разрешение за известия. Включете го в настройките на ОС/браузъра.';

  @override
  String get settingsUserProfileSection => 'ПРОФИЛ / ПОКАЗАТЕЛИ';

  @override
  String get settingsHeightCmOptional => 'Височина (cm), по избор';

  @override
  String get settingsHeightInOptional => 'Височина (in), по избор';

  @override
  String get settingsWeightKgOptional => 'Тегло (kg), по избор';

  @override
  String get settingsWeightLbsOptional => 'Тегло (lbs), по избор';

  @override
  String get settingsAgeOptional => 'Възраст, по избор';

  @override
  String get settingsBmiHeading => 'ИТМ (индекс на телесна маса)';

  @override
  String get settingsUserTargetsSection => 'ДНЕВНИ ЦЕЛИ';

  @override
  String get settingsProteinG => 'Протеин (g)';

  @override
  String get settingsCarbsG => 'Въглехидрати (g)';

  @override
  String get settingsFatsG => 'Мазнини (g)';

  @override
  String get settingsCalories => 'Калории';

  @override
  String get bmiEnterImperial =>
      'Въведете височина (in) и тегло (lbs), за да се изчисли ИТМ.';

  @override
  String get bmiEnterMetric =>
      'Въведете височина (cm) и тегло (kg), за да се изчисли ИТМ.';

  @override
  String get bmiEnterValid => 'Въведете валидни височина и тегло.';

  @override
  String get bmiUnderweight => 'Поднормено тегло (под 18.5)';

  @override
  String get bmiNormal => 'Нормално тегло (18.5–24.9)';

  @override
  String get bmiOverweight => 'Наднормено тегло (25–29.9)';

  @override
  String get bmiObese => 'Затлъстяване (30 и повече)';

  @override
  String get bmiDash => '—';

  @override
  String get msgSignInDeleteLogs =>
      'Трябва да сте влезли, за да изтривате записи.';

  @override
  String get msgSignInUpdateLogs =>
      'Трябва да сте влезли, за да актуализирате записи.';

  @override
  String get msgSignInLogFood => 'Трябва да сте влезли, за да записвате храна.';

  @override
  String get msgSignInLogSupps =>
      'Трябва да сте влезли, за да записвате добавки.';

  @override
  String get msgSignInLogMeds =>
      'Трябва да сте влезли, за да записвате лекарства.';

  @override
  String get msgSignInSave => 'Трябва да сте влезли, за да запазите.';

  @override
  String get msgSignInAddMeds =>
      'Трябва да сте влезли, за да добавяте лекарства.';

  @override
  String get msgSignInReports =>
      'Влезте, за да видите отчетите (RLS + user_id).';

  @override
  String get msgPlannedMealRemoved => 'Планираното хранене е премахнато';

  @override
  String get msgEntryUpdated => 'Записът е актуализиран';

  @override
  String get msgEmptyRecordId => 'Грешка: празен идентификатор на запис';

  @override
  String get msgMealMarkedConsumed => 'Храненето е маркирано като прието!';

  @override
  String get msgValidAmountGrams => 'Въведете валидно количество в грамове';

  @override
  String get msgValidAmount => 'Въведете валидно количество';

  @override
  String get msgValidDose => 'Въведете валидна доза';

  @override
  String get msgLogged => 'Записано.';

  @override
  String get msgLogDeleted => 'Записът е изтрит.';

  @override
  String get msgLogUpdated => 'Записът е актуализиран!';

  @override
  String get msgConfigSaved => 'НАСТРОЙКИТЕ СА ЗАПАЗЕНИ';

  @override
  String msgPlannedForMeal(String meal) {
    return 'ПЛАНИРАНО → $meal';
  }

  @override
  String logsError(String details) {
    return 'Грешка в записите: $details';
  }

  @override
  String libraryError(String details) {
    return 'Грешка в библиотеката: $details';
  }

  @override
  String pdfError(String details) {
    return 'PDF грешка: $details';
  }

  @override
  String get analyticsNoDaysInRange =>
      'Няма дни в избрания период — променете периода.';

  @override
  String get analyticsConsumedCaloriesTitle => 'ПРИЕТА ХРАНА — Калории по дни';

  @override
  String get analyticsNoConsumedFood =>
      'Няма приета храна в периода — графиката е на нулева основа.';

  @override
  String get analyticsGlycemicTitle =>
      'ПРИЕТА ХРАНА — Оценъчен гликемичен товар (GI × въглехидрати, където е известно)';

  @override
  String get analyticsNoGiData =>
      'Няма GI данни / няма въглехидрати в записаните артикули — графиката е на нулева основа.';

  @override
  String get analyticsSourceDailyLogs =>
      'Източник: daily_logs · филтрирано по created_at (UTC ден, като екрана ГОРИВО).';

  @override
  String get analyticsNoDataForRange => 'Няма данни за периода.';

  @override
  String get analyticsSuppAdherenceTitle =>
      'СПАЗВАНЕ НА ДОБАВКИ (прието срещу пропуснато)';

  @override
  String get analyticsMedAdherenceTitle =>
      'СПАЗВАНЕ НА ЛЕКАРСТВА (прието срещу пропуснато)';

  @override
  String get analyticsSourceDailyLogsShort =>
      'Източник: daily_logs · created_at (UTC ден).';

  @override
  String get analyticsSourceMedLogs =>
      'Източник: medication_logs · created_at (UTC ден). Редовете включват medication_id → medications(name) за етикети при експорт.';

  @override
  String get analyticsMissedExplainer =>
      'Пропуснато = планирано, неприето и след гратис периода (днес: +60 мин) или предишен ден.';

  @override
  String get analyticsLegendTaken => 'Прието';

  @override
  String get analyticsLegendMissed => 'Пропуснато';

  @override
  String analyticsRangeButton(String start, String end) {
    return 'Период: $start → $end';
  }

  @override
  String analyticsDailyPlanPdfDate(String date) {
    return 'Дата за PDF дневен план: $date';
  }

  @override
  String analyticsDailyPlanSubtitle(String date) {
    return '$date — докоснете „Дата за PDF дневен план“ по-горе за промяна';
  }

  @override
  String analyticsWeeklySubtitle(String start, String end) {
    return 'Използва текущия период от дати ($start → $end).';
  }

  @override
  String get addSupplementToLibrary => 'Добави добавка в библиотеката';

  @override
  String get addMedicationToLibrary => 'Добави лекарство в библиотеката';

  @override
  String get editLog => 'Редактирай запис';

  @override
  String get deleteLog => 'Изтрий запис';

  @override
  String get fuelLogIntakeTitle => 'ЗАПИС НА ПРИЕМ';

  @override
  String get fuelIntakeTime => 'ЧАС НА ПРИЕМ';

  @override
  String get fuelIntakeTimeDash => 'ЧАС НА ПРИЕМ  —';

  @override
  String timeAt(String time) {
    return 'ЧАС  $time';
  }

  @override
  String intakeTimeAt(String time) {
    return 'ЧАС НА ПРИЕМ  $time';
  }

  @override
  String get amountTaken => 'Прието количество';

  @override
  String get numberOfConsecutiveDays => 'Брой последователни дни';

  @override
  String get saveAsDefaultDoseLibrary =>
      'Запази като стандартна доза в библиотеката';

  @override
  String get addSupplementTitle => 'ДОБАВИ ДОБАВКА';

  @override
  String get amountLabelShort => 'Количество';

  @override
  String get fuelScheduleMultiDays => 'Планиране за няколко дни';

  @override
  String get fuelRepeatDaysLabel => 'Брой дни';

  @override
  String get fuelEditEntryTitle => 'РЕДАКТИРАНЕ НА ЗАПИС';

  @override
  String get fuelAmountGrams => 'КОЛИЧЕСТВО (ГРАМОВЕ)';

  @override
  String get fuelConsumptionTime => 'ЧАС НА КОНСУМАЦИЯ';

  @override
  String fuelConsumptionTimeAt(String time) {
    return 'ЧАС НА КОНСУМАЦИЯ  $time';
  }

  @override
  String get fuelPlanningSaved => 'ПЛАНИРАНЕ — запазено като все още неприето';

  @override
  String reminderTitleMeal(String name) {
    return 'Хранене: $name.';
  }

  @override
  String reminderAtTime(String time) {
    return 'Напомняне: $time';
  }

  @override
  String get reminderBody => 'Напомняне';

  @override
  String reminderTimeToTake(String name) {
    return 'Време за прием на $name!';
  }

  @override
  String get supsLogIntakeTitle => 'ЗАПИС НА ПРИЕМ НА ДОБАВКА';

  @override
  String get medsLogIntakeTitle => 'ЗАПИС НА ПРИЕМ НА ЛЕКАРСТВО';

  @override
  String get supsEditLogTitle => 'РЕДАКЦИЯ НА ЗАПИС — ДОБАВКА';

  @override
  String get medsEditLogTitle => 'РЕДАКЦИЯ НА ЗАПИС — ЛЕКАРСТВО';

  @override
  String get supsNewSupplementTitle => 'НОВА ДОБАВКА';

  @override
  String get medsNewMedicationTitle => 'ДОБАВИ ЛЕКАРСТВО';

  @override
  String get medsMedicationName => 'Име';

  @override
  String logSupplementBlock(String block) {
    return 'ДОБАВКА — $block';
  }

  @override
  String logMedicationBlock(String block) {
    return 'ЛЕКАРСТВО — $block';
  }

  @override
  String get defaultSupplementName => 'Добавка';

  @override
  String get defaultMedicationName => 'Лекарство';

  @override
  String notificationReminderSuppIntake(String name) {
    return 'Напомняне: прием на $name.';
  }

  @override
  String notificationReminderMedIntake(String name) {
    return 'Напомняне: прием на $name.';
  }

  @override
  String get libraryAddNew => '+ Нова в библиотеката';

  @override
  String libraryDefaultDose(String dose, String unit) {
    return 'По подразбиране $dose $unit (редактирайте при запис)';
  }

  @override
  String get libraryNoDefaultDose =>
      'Няма доза по подразбиране (въведете при запис)';

  @override
  String get dialogSaving => '…';

  @override
  String get intakeAddModeLogNow => 'ЗАПИС СЕГА';

  @override
  String get intakeAddModePlan => 'ПЛАН';

  @override
  String get intakeAddModeHint =>
      'Планираните остават отворени, докато натиснете ПРИЕМ.';

  @override
  String notificationTimeForIntake(String name) {
    return 'Време за прием: $name';
  }
}
