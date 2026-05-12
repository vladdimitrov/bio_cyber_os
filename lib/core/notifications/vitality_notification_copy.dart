/// English copy for OS notifications (Vitality Calendar product wording).
enum VitalityCalendarCategory {
  fuel,
  supplements,
  medications,
}

/// Builds consistent notification title/body for reminders.
class VitalityNotificationCopy {
  VitalityNotificationCopy._();

  static String _categoryName(VitalityCalendarCategory c) {
    switch (c) {
      case VitalityCalendarCategory.fuel:
        return 'Food';
      case VitalityCalendarCategory.supplements:
        return 'Daily essentials';
      case VitalityCalendarCategory.medications:
        return 'My list';
    }
  }

  static String _bodyPrefix(VitalityCalendarCategory c) {
    switch (c) {
      case VitalityCalendarCategory.fuel:
        return '🍏 Eat: ';
      case VitalityCalendarCategory.supplements:
        return '💊 Take: ';
      case VitalityCalendarCategory.medications:
        return '💉 Amount: ';
    }
  }

  /// e.g. `Vitality Calendar: Food`
  static String buildTitle(VitalityCalendarCategory category) {
    return 'Vitality Calendar: ${_categoryName(category)}';
  }

  static String formatAmountForDisplay(num amount) {
    if (amount == amount.roundToDouble()) {
      return amount.toInt().toString();
    }
    return amount.toString();
  }

  /// e.g. `🍏 Eat: Avocado - 1.0 piece`
  static String buildBody({
    required VitalityCalendarCategory category,
    required String itemName,
    required num? amount,
    required String unit,
  }) {
    final name = itemName.trim();
    final u = unit.trim();
    final amtStr = amount == null ? '' : formatAmountForDisplay(amount);
    final core = (amtStr.isEmpty && u.isEmpty)
        ? name
        : u.isEmpty
            ? '$name - $amtStr'
            : '$name - $amtStr $u';
    return '${_bodyPrefix(category)}$core';
  }
}
