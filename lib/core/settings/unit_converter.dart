class UnitConverter {
  UnitConverter._();

  static const double _lbsPerKg = 2.2046226218;
  static const double _inchesPerCm = 0.3937007874;
  static const double _ozPerG = 0.03527396195;
  static const double _flOzPerMl = 0.0338140227;

  static double kgToLbs(double kg) => kg * _lbsPerKg;
  static double lbsToKg(double lbs) => lbs / _lbsPerKg;

  static double cmToInches(double cm) => cm * _inchesPerCm;
  static double inchesToCm(double inches) => inches / _inchesPerCm;

  static double gToOz(double g) => g * _ozPerG;
  static double ozToG(double oz) => oz / _ozPerG;

  static double mlToFlOz(double ml) => ml * _flOzPerMl;
  static double flOzToMl(double flOz) => flOz / _flOzPerMl;
}

