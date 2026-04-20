import 'package:flutter/material.dart';

/// Brand gold (`#FFD700`) — use for login, Fuel, Meds, and other gold accents.
abstract final class AppColors {
  AppColors._();

  static const Color cyberGold = Color(0xFFFFD700);

  /// Muted gold for secondary text on dark backgrounds (alpha 0x88).
  static const Color cyberGoldMuted = Color(0x88FFD700);
}
