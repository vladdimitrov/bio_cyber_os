import 'package:flutter/material.dart';

import 'package:bio_cyber_os/l10n/app_localizations.dart';

import 'features/analytics/screens/analytics_screen.dart';
import 'features/config/screens/settings_screen.dart';
import 'features/fuel/screens/fuel_dashboard_screen.dart';
import 'features/intake/screens/daily_intake_screen.dart';
import 'features/library/screens/library_screen.dart';
import 'features/vitals/screens/check_in_screen.dart';

class AppShell extends StatefulWidget {
  static final GlobalKey<_AppShellState> _shellKey = GlobalKey<_AppShellState>();

  const AppShell({super.key});

  static Key get shellKey => _shellKey;

  static void openFuel({String? focusLogId, DateTime? focusDate}) {
    _shellKey.currentState?._openFuel(
      focusLogId: focusLogId,
      focusDate: focusDate,
    );
  }

  static void openSupps({String? focusLogId, DateTime? focusDate}) {
    _shellKey.currentState?._openSupps(
      focusLogId: focusLogId,
      focusDate: focusDate,
    );
  }

  static void openMeds({String? focusLogId, DateTime? focusDate}) {
    _shellKey.currentState?._openMeds(
      focusLogId: focusLogId,
      focusDate: focusDate,
    );
  }

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  int _intakeTabIndex = 0;
  String? _fuelFocusLogId;
  DateTime? _fuelFocusDate;
  String? _suppsFocusLogId;
  DateTime? _suppsFocusDate;
  String? _medsFocusLogId;
  DateTime? _medsFocusDate;

  void _openFuel({String? focusLogId, DateTime? focusDate}) {
    setState(() {
      _index = 0;
      _fuelFocusLogId = focusLogId;
      _fuelFocusDate = focusDate;
    });
  }

  void _openSupps({String? focusLogId, DateTime? focusDate}) {
    setState(() {
      _index = 1;
      _intakeTabIndex = 0;
      _suppsFocusLogId = focusLogId;
      _suppsFocusDate = focusDate;
    });
  }

  void _openMeds({String? focusLogId, DateTime? focusDate}) {
    setState(() {
      _index = 1;
      _intakeTabIndex = 1;
      _medsFocusLogId = focusLogId;
      _medsFocusDate = focusDate;
    });
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          FuelDashboardScreen(
            focusLogId: _fuelFocusLogId,
            focusDate: _fuelFocusDate,
            isActive: _index == 0,
          ),
          DailyIntakeScreen(
            initialTabIndex: _intakeTabIndex,
            focusSuppLogId: _suppsFocusLogId,
            focusSuppDate: _suppsFocusDate,
            focusMedLogId: _medsFocusLogId,
            focusMedDate: _medsFocusDate,
          ),
          const CheckInScreen(),
          const AnalyticsScreen(),
          const LibraryScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: cyan, width: 2)),
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() {
            _index = i;
            // Clear deep-link focus if user navigates manually.
            if (i != 0) {
              _fuelFocusLogId = null;
              _fuelFocusDate = null;
            }
            if (i != 1) _suppsFocusLogId = null;
            if (i != 1) _suppsFocusDate = null;
            if (i != 1) _medsFocusLogId = null;
            if (i != 1) _medsFocusDate = null;
          }),
          backgroundColor: bg,
          selectedItemColor: cyan,
          unselectedItemColor: const Color(0x8800F3FF),
          selectedLabelStyle: const TextStyle(
            fontFamily: 'monospace',
            letterSpacing: 1.0,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(
            fontFamily: 'monospace',
            letterSpacing: 1.0,
          ),
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.local_fire_department_outlined),
              activeIcon: const Icon(Icons.local_fire_department),
              label: l10n.navFuel,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.medication_outlined),
              activeIcon: const Icon(Icons.medication),
              label: 'Intake',
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.favorite_border),
              activeIcon: const Icon(Icons.favorite),
              label: l10n.navVitals,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.insights_outlined),
              activeIcon: const Icon(Icons.insights),
              label: l10n.navReports,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.library_books_outlined),
              activeIcon: const Icon(Icons.library_books),
              label: l10n.navLibrary,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.settings_outlined),
              activeIcon: const Icon(Icons.settings),
              label: l10n.navConfig,
            ),
          ],
        ),
      ),
    );
  }
}

