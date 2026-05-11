import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bio_cyber_os/l10n/app_localizations.dart';

import '../../../core/debug/agent_debug_log.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/notifications/vitality_notification_copy.dart';
import '../../../core/security/biometric_auth_service.dart';
import '../../../core/settings/locale_settings.dart';
import '../../../core/settings/measurement_settings.dart';
import '../../../core/settings/unit_converter.dart';
import '../../../core/settings/notification_settings.dart';
import '../../../core/settings/profile_settings.dart';
import '../../auth/screens/splash_route.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _heightCmController = TextEditingController();
  final _weightKgController = TextEditingController();
  final _ageController = TextEditingController();

  final _proteinController = TextEditingController();
  final _carbsController = TextEditingController();
  final _fatsController = TextEditingController();
  final _caloriesController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _profileListenersAttached = false;
  bool _targetsListenersAttached = false;
  String? _lastSavedHeightCmRaw;
  String? _lastSavedWeightKgRaw;
  String? _lastSavedAgeRaw;

  Timer? _profileRemoteDebounce;
  Timer? _targetsRemoteDebounce;

  bool _hydratingProfile = false;
  bool _hydratingTargets = false;

  MeasurementSystem _measurementSystem = MeasurementSystem.metric;
  bool _notificationsEnabled = false;
  AppLanguagePreference _selectedLanguage = AppLanguagePreference.system;
  bool _updatingDisplay = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  String? _lastProfileUpsertError;

  void _onProfileFieldsChanged() {
    if (_hydratingProfile) return;
    setState(() {});
    unawaited(_saveProfileLocal());
    _profileRemoteDebounce?.cancel();
    _profileRemoteDebounce = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      unawaited(_persistProfileRemote(debug: true));
    });
  }

  void _onTargetsFieldsChanged() {
    if (_hydratingTargets) return;
    _targetsRemoteDebounce?.cancel();
    _targetsRemoteDebounce = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      if (!_targetsParseOk()) return;
      unawaited(_persistTargetsRemote(showSnack: false));
    });
  }

  bool _targetsParseOk() {
    return double.tryParse(_proteinController.text.trim()) != null &&
        double.tryParse(_carbsController.text.trim()) != null &&
        double.tryParse(_fatsController.text.trim()) != null &&
        int.tryParse(_caloriesController.text.trim()) != null;
  }

  void _attachTargetListenersOnce() {
    if (_targetsListenersAttached) return;
    _proteinController.addListener(_onTargetsFieldsChanged);
    _carbsController.addListener(_onTargetsFieldsChanged);
    _fatsController.addListener(_onTargetsFieldsChanged);
    _caloriesController.addListener(_onTargetsFieldsChanged);
    _targetsListenersAttached = true;
  }

  Future<void> _saveProfileLocal() async {
    if (_updatingDisplay) return;
    try {
      final hRaw = _heightCmController.text.trim();
      final wRaw = _weightKgController.text.trim();
      final aRaw = _ageController.text.trim();

      // Avoid spamming storage writes/logs: only save when values actually change.
      if (_lastSavedHeightCmRaw == hRaw &&
          _lastSavedWeightKgRaw == wRaw &&
          _lastSavedAgeRaw == aRaw) {
        return;
      }

      double? parseNum(String v) {
        final t = v.trim().replaceAll(',', '.');
        if (t.isEmpty) return null;
        return double.tryParse(t);
      }

      final hDisplay = parseNum(hRaw);
      final wDisplay = parseNum(wRaw);

      final hCm = (_measurementSystem == MeasurementSystem.imperial && hDisplay != null)
          ? UnitConverter.inchesToCm(hDisplay)
          : hDisplay;
      final wKg = (_measurementSystem == MeasurementSystem.imperial && wDisplay != null)
          ? UnitConverter.lbsToKg(wDisplay)
          : wDisplay;

      final age = int.tryParse(aRaw);
      await ProfileSettings.setLocal(heightCm: hCm, weightKg: wKg, age: age);

      _lastSavedHeightCmRaw = hRaw;
      _lastSavedWeightKgRaw = wRaw;
      _lastSavedAgeRaw = aRaw;

      // #region agent log
      AgentDebugLog.log(
        runId: 'pre-fix',
        hypothesisId: 'H1',
        location: 'lib/features/config/screens/settings_screen.dart:_saveProfileLocal',
        message: 'Profile saved locally (best-effort)',
        data: {
          'height_raw': _heightCmController.text.trim(),
          'weight_raw': _weightKgController.text.trim(),
          'age_raw': _ageController.text.trim(),
          'height_cm': hCm,
          'weight_kg': wKg,
          'age': age,
        },
      );
      // #endregion
    } catch (_) {}
  }

  Future<void> _loadProfileFromPrefs() async {
    try {
      await ProfileSettings.loadLocal();
      if (!mounted) return;
      final hCm = ProfileSettings.heightCm.value;
      final wKg = ProfileSettings.weightKg.value;
      _updatingDisplay = true;
      _heightCmController.text = (_measurementSystem == MeasurementSystem.imperial && hCm != null)
          ? UnitConverter.cmToInches(hCm).toStringAsFixed(0)
          : (hCm?.toStringAsFixed(0) ?? '');
      _weightKgController.text = (_measurementSystem == MeasurementSystem.imperial && wKg != null)
          ? UnitConverter.kgToLbs(wKg).toStringAsFixed(1)
          : (wKg?.toStringAsFixed(1) ?? '');
      _updatingDisplay = false;
      _ageController.text = ProfileSettings.age.value?.toString() ?? '';
      if (!_profileListenersAttached) {
        _heightCmController.addListener(_onProfileFieldsChanged);
        _weightKgController.addListener(_onProfileFieldsChanged);
        _ageController.addListener(_onProfileFieldsChanged);
        _profileListenersAttached = true;
      }
      setState(() {});
    } catch (_) {}
  }

  static double? _parseOptionalDouble(String v) {
    final t = v.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  ({String value, String category}) _bmiDisplay(AppLocalizations l10n) {
    final hDisplay = _parseOptionalDouble(_heightCmController.text);
    final wDisplay = _parseOptionalDouble(_weightKgController.text);
    final h = (_measurementSystem == MeasurementSystem.imperial && hDisplay != null)
        ? UnitConverter.inchesToCm(hDisplay)
        : hDisplay;
    final w = (_measurementSystem == MeasurementSystem.imperial && wDisplay != null)
        ? UnitConverter.lbsToKg(wDisplay)
        : wDisplay;
    if (h == null || w == null || h <= 0 || w <= 0) {
      return (
        value: l10n.bmiDash,
        category: _measurementSystem == MeasurementSystem.imperial
            ? l10n.bmiEnterImperial
            : l10n.bmiEnterMetric,
      );
    }
    final hm = h / 100.0;
    final bmi = w / (hm * hm);
    if (!bmi.isFinite) {
      return (value: l10n.bmiDash, category: l10n.bmiEnterValid);
    }
    final value = bmi.toStringAsFixed(1);
    final category = () {
      if (bmi < 18.5) return l10n.bmiUnderweight;
      if (bmi < 25) return l10n.bmiNormal;
      if (bmi < 30) return l10n.bmiOverweight;
      return l10n.bmiObese;
    }();
    return (value: value, category: category);
  }

  @override
  void initState() {
    super.initState();
    _measurementSystem = MeasurementSettings.system.value;
    _notificationsEnabled = NotificationSettings.enabled.value;
    _selectedLanguage = LocaleSettings.preference;
    MeasurementSettings.system.addListener(_onMeasurementChanged);
    NotificationSettings.enabled.addListener(_onNotificationsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapScreen());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBiometricSettings());
  }

  Future<void> _loadBiometricSettings() async {
    final available = await BiometricAuthService.isAvailable();
    final enabled = await BiometricAuthService.isEnabled();
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _biometricEnabled = enabled;
    });
  }

  Future<void> _bootstrapScreen() async {
    setState(() => _loading = true);
    // ignore: avoid_print
    print('DEBUG: Settings bootstrap - loading from SharedPreferences...');
    await _loadProfileFromPrefs();
    final uid = _client.auth.currentUser?.id;
    // ignore: avoid_print
    print('DEBUG: Settings bootstrap - user_id: $uid');
    await Future.wait([
      if (uid != null) _hydrateProfileFromSupabase(),
      _loadTargetsForUser(uid),
    ]);
    _attachTargetListenersOnce();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _hydrateProfileFromSupabase() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await _client
          .from('profiles')
          .select('height_cm, weight_kg, age, selected_language, notifications_enabled')
          .eq('id', uid)
          .maybeSingle();
      if (!mounted || row == null) return;
      // ignore: avoid_print
      print('DEBUG: Settings hydrate - Supabase profile row: $row');

      final h = row['height_cm'];
      final w = row['weight_kg'];
      final a = row['age'];
      final lang = (row['selected_language'] ?? '').toString().trim().toLowerCase();
      final notifRaw = row['notifications_enabled'];
      final notif = notifRaw is bool
          ? notifRaw
          : (notifRaw is num
              ? notifRaw != 0
              : (notifRaw?.toString().toLowerCase() == 'true'));
      final hCm = h is num ? h.toDouble() : double.tryParse('$h');
      final wKg = w is num ? w.toDouble() : double.tryParse('$w');
      final ageStr = a == null ? '' : '$a'.trim();

      _hydratingProfile = true;
      _updatingDisplay = true;
      // Local fallback: do not wipe local fields if Supabase returns nulls.
      if (hCm != null) {
        _heightCmController.text =
            (_measurementSystem == MeasurementSystem.imperial)
                ? UnitConverter.cmToInches(hCm).toStringAsFixed(0)
                : hCm.toStringAsFixed(0);
      }
      if (wKg != null) {
        _weightKgController.text =
            (_measurementSystem == MeasurementSystem.imperial)
                ? UnitConverter.kgToLbs(wKg).toStringAsFixed(1)
                : wKg.toStringAsFixed(1);
      }
      if (a != null) {
        _ageController.text = ageStr;
      }
      _updatingDisplay = false;
      _hydratingProfile = false;

      // Only update local cache from Supabase if we actually received values.
      if (hCm != null || wKg != null || a != null) {
        await _saveProfileLocal();
      }

      // Apply language + notifications from Supabase to app state/prefs.
      if (lang == 'en') {
        await LocaleSettings.setPreference(AppLanguagePreference.english);
      } else if (lang == 'bg') {
        await LocaleSettings.setPreference(AppLanguagePreference.bulgarian);
      } else {
        await LocaleSettings.setPreference(AppLanguagePreference.system);
      }
      await NotificationSettings.setEnabled(notif);

      if (mounted) {
        setState(() {
          _selectedLanguage = LocaleSettings.preference;
          _notificationsEnabled = NotificationSettings.enabled.value;
        });
      }
      // ignore: avoid_print
      print('DEBUG: Local Language saved: $lang');
      // ignore: avoid_print
      print('DEBUG: Notifications Switch state: $notif');

      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<bool> _persistProfileRemote({required bool debug}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      if (debug) {
        // ignore: avoid_print
        print('DEBUG: Supabase update aborted: user_id is null (logged out?)');
      }
      // #region agent log
      AgentDebugLog.log(
        runId: 'pre-fix',
        hypothesisId: 'H2',
        location:
            'lib/features/config/screens/settings_screen.dart:_persistProfileRemote',
        message: 'Supabase profile upsert aborted: uid null',
      );
      // #endregion
      return false;
    }
    // ignore: avoid_print
    print('DEBUG: Saving profile for User ID: $uid');
    if (debug) {
      // ignore: avoid_print
      print(
        'DEBUG: Supabase session present: ${_client.auth.currentSession != null}',
      );
      // ignore: avoid_print
      print(
        'DEBUG: Supabase session user id: ${_client.auth.currentSession?.user.id}',
      );
    }

    double? parseNum(String v) {
      final t = v.trim().replaceAll(',', '.');
      if (t.isEmpty) return null;
      return double.tryParse(t);
    }

    final hRaw = _heightCmController.text.trim();
    final wRaw = _weightKgController.text.trim();
    if (debug) {
      // ignore: avoid_print
      print('DEBUG: Attempting to save Height: $hRaw');
      // ignore: avoid_print
      print('DEBUG: Attempting to save Weight: $wRaw');
      // ignore: avoid_print
      print('DEBUG: Attempting to save Age: ${_ageController.text}');
      // ignore: avoid_print
      print('DEBUG: Supabase user_id: $uid');
    }
    final hDisplay = parseNum(hRaw);
    final wDisplay = parseNum(wRaw);
    final hCm = (_measurementSystem == MeasurementSystem.imperial &&
            hDisplay != null)
        ? UnitConverter.inchesToCm(hDisplay)
        : hDisplay;
    final wKg = (_measurementSystem == MeasurementSystem.imperial &&
            wDisplay != null)
        ? UnitConverter.lbsToKg(wDisplay)
        : wDisplay;
    final ageTrim = _ageController.text.trim();
    final ageInt = int.tryParse(ageTrim);

    final lang = () {
      switch (_selectedLanguage) {
        case AppLanguagePreference.system:
          return '';
        case AppLanguagePreference.english:
          return 'en';
        case AppLanguagePreference.bulgarian:
          return 'bg';
      }
    }();
    final isEnabled = _notificationsEnabled;
    // ignore: avoid_print
    print('DEBUG: Local Language saved: $lang');
    // ignore: avoid_print
    print('DEBUG: Notifications Switch state: $isEnabled');

    final payload = <String, dynamic>{
      'id': uid,
      // Supabase schema: height_cm is INTEGER, avoid sending "174.0".
      'height_cm': hCm?.round(),
      // Supabase schema: weight_kg is INTEGER, avoid sending "65.0".
      'weight_kg': wKg?.round(),
      'age': ageTrim.isEmpty ? null : ageInt,
      'selected_language': lang,
      'notifications_enabled': isEnabled,
    };

    try {
      _lastProfileUpsertError = null;
      if (debug) {
        // ignore: avoid_print
        print('DEBUG: Supabase update payload: $payload');
      }
      // #region agent log
      AgentDebugLog.log(
        runId: 'pre-fix',
        hypothesisId: 'H2',
        location:
            'lib/features/config/screens/settings_screen.dart:_persistProfileRemote',
        message: 'Attempting Supabase profile upsert',
        data: {
          'uid_present': true,
          'payload_keys': payload.keys.toList(),
          'height_cm': hCm,
          'weight_kg': wKg,
          'age': payload['age'],
        },
      );
      // #endregion
      await _client.from('profiles').upsert(payload, onConflict: 'id');
      if (debug) {
        // ignore: avoid_print
        print('DEBUG: Supabase profile upsert OK');
      }

      // Best-effort verify/readback (never fail the save if this errors).
      // On some RLS setups, UPDATE may be allowed while SELECT is denied.
      if (debug) {
        try {
          final verify = await _client
              .from('profiles')
              .select(
                'id, height_cm, weight_kg, age, selected_language, notifications_enabled, updated_at',
              )
              .eq('id', uid)
              .maybeSingle();
          // ignore: avoid_print
          print('DEBUG: Supabase verify profile row: $verify');
        } catch (e) {
          // ignore: avoid_print
          print('DEBUG: Supabase verify read-back failed (ignored): $e');
        }
      }

      // Treat as SUCCESS if upsert did not throw.
      return true;
    } on PostgrestException catch (e) {
      final msg =
          'PostgrestException(code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint})';
      _lastProfileUpsertError = msg;
      // ignore: avoid_print
      print(
        'DEBUG: PostgrestException during profile upsert '
        '(code=${e.code} message=${e.message} details=${e.details} hint=${e.hint})',
      );
      AgentDebugLog.log(
        runId: 'pre-fix',
        hypothesisId: 'H2',
        location:
            'lib/features/config/screens/settings_screen.dart:_persistProfileRemote',
        message: 'PostgrestException during profile upsert',
        data: {
          'uid': uid,
          'code': e.code,
          'message': e.message,
          'details': e.details,
          'hint': e.hint,
          'session_present': _client.auth.currentSession != null,
          'session_user_id': _client.auth.currentSession?.user.id,
        },
      );
    } catch (e) {
      _lastProfileUpsertError = e.toString();
      // ignore: avoid_print
      print('DEBUG: Unknown exception during profile upsert: $e');
    }
    if (debug) {
      // ignore: avoid_print
      print('DEBUG: Supabase profile upsert FAILED (caught exception)');
    }
    // #region agent log
    AgentDebugLog.log(
      runId: 'pre-fix',
      hypothesisId: 'H2',
      location:
          'lib/features/config/screens/settings_screen.dart:_persistProfileRemote',
      message: 'Supabase profile upsert FAILED (caught exception)',
    );
    // #endregion
    return false;
  }

  Future<void> _loadTargetsForUser(String? uid) async {
    if (uid == null) {
      if (!mounted) return;
      _hydratingTargets = true;
      _proteinController.text = '';
      _carbsController.text = '';
      _fatsController.text = '';
      _caloriesController.text = '';
      _hydratingTargets = false;
      return;
    }
    try {
      final data = await _client
          .from('user_targets')
          .select('calories_target, protein_target, fat_target, carbs_target')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (!mounted) return;
      _hydratingTargets = true;
      setState(() {
        _proteinController.text = (data?['protein_target'] ?? '').toString();
        _carbsController.text = (data?['carbs_target'] ?? '').toString();
        _fatsController.text = (data?['fat_target'] ?? '').toString();
        _caloriesController.text = (data?['calories_target'] ?? '').toString();
      });
      _hydratingTargets = false;
    } catch (e) {
      if (!mounted) return;
      _hydratingTargets = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<bool> _persistTargetsRemote({required bool showSnack}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return false;
    if (!_targetsParseOk()) return false;

    if (showSnack) setState(() => _saving = true);
    try {
      int roundDoubleText(String v) =>
          (double.tryParse(v.trim()) ?? 0.0).round();
      final fields = <String, dynamic>{
        // Supabase schema: targets are INTEGERs, avoid "110.0" etc.
        'protein_target': roundDoubleText(_proteinController.text),
        'carbs_target': roundDoubleText(_carbsController.text),
        'fat_target': roundDoubleText(_fatsController.text),
        'calories_target': roundDoubleText(_caloriesController.text),
      };

      final existing = await _client
          .from('user_targets')
          .select('id')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (existing != null && existing['id'] != null) {
        await _client
            .from('user_targets')
            .update({...fields, 'user_id': uid})
            .eq('id', existing['id'])
            .eq('user_id', uid);
      } else {
        await _client.from('user_targets').insert({...fields, 'user_id': uid});
      }

      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
      return false;
    } finally {
      if (mounted && showSnack) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _profileRemoteDebounce?.cancel();
    _targetsRemoteDebounce?.cancel();
    if (_profileListenersAttached) {
      _heightCmController.removeListener(_onProfileFieldsChanged);
      _weightKgController.removeListener(_onProfileFieldsChanged);
      _ageController.removeListener(_onProfileFieldsChanged);
    }
    if (_targetsListenersAttached) {
      _proteinController.removeListener(_onTargetsFieldsChanged);
      _carbsController.removeListener(_onTargetsFieldsChanged);
      _fatsController.removeListener(_onTargetsFieldsChanged);
      _caloriesController.removeListener(_onTargetsFieldsChanged);
    }
    _heightCmController.dispose();
    _weightKgController.dispose();
    _ageController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatsController.dispose();
    _caloriesController.dispose();
    MeasurementSettings.system.removeListener(_onMeasurementChanged);
    NotificationSettings.enabled.removeListener(_onNotificationsChanged);
    super.dispose();
  }

  void _onMeasurementChanged() {
    if (!mounted) return;
    setState(() => _measurementSystem = MeasurementSettings.system.value);
    unawaited(_loadProfileFromPrefs());
  }

  void _onNotificationsChanged() {
    if (!mounted) return;
    setState(() => _notificationsEnabled = NotificationSettings.enabled.value);
  }

  InputDecoration _decoration(String label) {
    const cyan = Color(0xFF00F3FF);
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: cyan, fontFamily: 'monospace'),
    );
  }

  Future<void> _saveAllFromButton() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    _profileRemoteDebounce?.cancel();
    _targetsRemoteDebounce?.cancel();

    await _saveProfileLocal();
    final okProfile = await _persistProfileRemote(debug: true);
    final okTargets = await _persistTargetsRemote(showSnack: false);
    final uid = _client.auth.currentUser?.id;
    if (uid != null) await _loadTargetsForUser(uid);

    if (!mounted) return;
    if (!okProfile || !okTargets) {
      final profileDetail =
          (!okProfile && (_lastProfileUpsertError ?? '').trim().isNotEmpty)
              ? '\n${_lastProfileUpsertError!}'
              : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !okProfile
                ? 'SAVE FAILED: Profile did not persist to Supabase.$profileDetail'
                : 'SAVE FAILED: Targets did not persist to Supabase.',
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('SUCCESS')),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    final l10n = AppLocalizations.of(context)!;
    final bmi = _bmiDisplay(l10n);
    const saveBarHeight = 86.0;

    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(l10n.screenConfig),
        actions: [
          IconButton(
            tooltip: l10n.logOut,
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _client.auth.signOut();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const SplashRoute()),
                (_) => false,
              );
            },
          ),
          IconButton(
            onPressed: _loading ? null : _bootstrapScreen,
            tooltip: l10n.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              top: false,
              child: Container(
                height: saveBarHeight,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: const BoxDecoration(
                  color: bg,
                  border: Border(top: BorderSide(color: cyan, width: 2)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x5500F3FF),
                      blurRadius: 22,
                      spreadRadius: 1,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _saveAllFromButton,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cyan,
                      foregroundColor: Colors.black,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'monospace',
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : Text(l10n.saveConfig),
                  ),
                ),
              ),
            ),
      body: _loading
          ? const SafeArea(child: Center(child: CircularProgressIndicator()))
          : SafeArea(
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          16,
                          16,
                          16,
                          16 + saveBarHeight,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: cyan, width: 1),
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.zero,
                                  ),
                                ),
                                onPressed: () async {
                                  if (defaultTargetPlatform !=
                                      TargetPlatform.android) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Fix Permissions is Android-only.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  await Permission.scheduleExactAlarm.request();
                                  await Permission.ignoreBatteryOptimizations
                                      .request();
                                  await Permission.systemAlertWindow.request();
                                },
                                child: const Text(
                                  '🛠️ Fix Permissions',
                                  style: TextStyle(
                                    color: cyan,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.red, width: 2),
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.zero,
                                  ),
                                ),
                                onPressed: () async {
                                  debugPrint('DEBUG: Settings -> DEBUG SHOW NOW pressed');
                                  await NotificationService.showDebugNow(
                                    key: 'debug_show_now',
                                    title: 'DEBUG SHOW NOW',
                                    body: 'If you see/hear this, show() works.',
                                  );
                                },
                                child: const Text(
                                  '🔔 DEBUG SHOW NOW',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                    const SizedBox(height: 14),
                    Text(
                      l10n.languageSectionTitle,
                      style: const TextStyle(
                        color: Color(0x8800F3FF),
                        fontFamily: 'monospace',
                        fontSize: 11,
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<AppLanguagePreference>(
                      key: ValueKey(_selectedLanguage),
                      initialValue: _selectedLanguage,
                      decoration: _decoration(l10n.languageLabel),
                      items: [
                        DropdownMenuItem(
                          value: AppLanguagePreference.system,
                          child: Text(l10n.languageSystem),
                        ),
                        DropdownMenuItem(
                          value: AppLanguagePreference.english,
                          child: Text(l10n.languageEnglish),
                        ),
                        DropdownMenuItem(
                          value: AppLanguagePreference.bulgarian,
                          child: Text(l10n.languageBulgarian),
                        ),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        setState(() => _selectedLanguage = v);
                        await LocaleSettings.setPreference(v);
                        if (!mounted) return;
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.settingsMeasurementSection,
                      style: const TextStyle(
                        color: Color(0x8800F3FF),
                        fontFamily: 'monospace',
                        fontSize: 11,
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<MeasurementSystem>(
                      initialValue: _measurementSystem,
                      decoration: _decoration(l10n.settingsMeasurementSystem),
                      items: [
                        DropdownMenuItem(
                          value: MeasurementSystem.metric,
                          child: Text(l10n.settingsMetric),
                        ),
                        DropdownMenuItem(
                          value: MeasurementSystem.imperial,
                          child: Text(l10n.settingsImperial),
                        ),
                      ],
                      onChanged: (v) async {
                        final next = v ?? MeasurementSystem.metric;
                        await MeasurementSettings.setSystem(next);
                        if (!mounted) return;
                        setState(() => _measurementSystem = next);
                      },
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: cyan, width: 1),
                      ),
                      child: SwitchListTile(
                        value: _notificationsEnabled,
                        onChanged: (v) async {
                          if (mounted) setState(() => _notificationsEnabled = v);
                          if (v) {
                            final ok =
                                await NotificationService.requestPermissionIfNeeded(
                              context,
                            );
                            if (!context.mounted) return;
                            if (!ok) {
                              await NotificationSettings.setEnabled(false);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(l10n.settingsNotificationsDenied),
                                ),
                              );
                              return;
                            }
                            await NotificationSettings.setEnabled(true);
                          } else {
                            await NotificationSettings.setEnabled(false);
                          }
                        },
                        title: Text(
                          l10n.settingsNotificationsTitle,
                          style: const TextStyle(
                            color: cyan,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                        subtitle: Text(
                          l10n.settingsNotificationsSubtitle,
                          style: const TextStyle(
                            color: Color(0xFF757575),
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        activeThumbColor: cyan,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: cyan, width: 1),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                        ),
                        onPressed: () async {
                          final ok =
                              await NotificationService.requestPermissionIfNeeded(
                            context,
                          );
                          if (!context.mounted) return;
                          if (!ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    Text(l10n.settingsNotificationsDenied),
                              ),
                            );
                            return;
                          }
                          debugPrint(
                            '🛠️ DEBUG: Testing schedule for 5 seconds from now...',
                          );
                          final when = DateTime.now().add(
                            const Duration(seconds: 5),
                          );
                          await NotificationService.scheduleByKey(
                            key: 'test_notification_5s',
                            title: VitalityNotificationCopy.buildTitle(
                              VitalityCalendarCategory.fuel,
                            ),
                            body: '🍏 Vitality Test: Avocado - 1.0 piece',
                            whenLocal: when,
                            payload: {
                              'type': 'test',
                              'ts': DateTime.now().toIso8601String(),
                            },
                            alarmItemName: 'Avocado',
                            alarmAmount: '1.0',
                            alarmUnit: 'piece',
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Test notification scheduled (+5s)'),
                            ),
                          );
                        },
                        child: const Text(
                          'TEST NOTIFICATION (+5s)',
                          style: TextStyle(
                            color: cyan,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'SECURITY',
                      style: const TextStyle(
                        color: Color(0x8800F3FF),
                        fontFamily: 'monospace',
                        fontSize: 11,
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: cyan, width: 1),
                      ),
                      child: SwitchListTile(
                        value: _biometricEnabled,
                        onChanged: !_biometricAvailable
                            ? null
                            : (v) async {
                                if (v) {
                                  final ok =
                                      await BiometricAuthService.authenticate();
                                  if (!context.mounted) return;
                                  if (!ok) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Biometric authentication failed.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  await BiometricAuthService.setEnabled(true);
                                  if (!context.mounted) return;
                                  setState(() => _biometricEnabled = true);
                                } else {
                                  await BiometricAuthService.setEnabled(false);
                                  if (!context.mounted) return;
                                  setState(() => _biometricEnabled = false);
                                }
                              },
                        title: Text(
                          'Use Biometric Authentication',
                          style: const TextStyle(
                            color: cyan,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                        subtitle: Text(
                          _biometricAvailable
                              ? 'Unlock using fingerprint/face (requires you to log in once first).'
                              : 'Biometrics not available on this device.',
                          style: const TextStyle(
                            color: Color(0xFF757575),
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        activeThumbColor: cyan,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: cyan, width: 1),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x3300F3FF),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: DefaultTextStyle(
                        style: const TextStyle(
                          color: cyan,
                          fontFamily: 'monospace',
                          letterSpacing: 0.6,
                        ),
                        child: Text(l10n.settingsUserProfileSection),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _heightCmController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: _decoration(
                        _measurementSystem == MeasurementSystem.imperial
                            ? 'Height (in), optional'
                            : 'Height (cm), optional',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _weightKgController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: _decoration(
                        _measurementSystem == MeasurementSystem.imperial
                            ? l10n.settingsWeightLbsOptional
                            : l10n.settingsWeightKgOptional,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _ageController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: _decoration(l10n.settingsAgeOptional),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0x44FFFFFF)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.settingsBmiHeading,
                            style: const TextStyle(
                              color: Color(0xFF757575),
                              fontFamily: 'monospace',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            bmi.value,
                            style: const TextStyle(
                              color: cyan,
                              fontFamily: 'monospace',
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            bmi.category,
                            style: const TextStyle(
                              color: Color(0xFF9E9E9E),
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: cyan, width: 1),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x3300F3FF),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: DefaultTextStyle(
                        style: const TextStyle(
                          color: cyan,
                          fontFamily: 'monospace',
                          letterSpacing: 0.6,
                        ),
                        child: Text(l10n.settingsUserTargetsSection),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _proteinController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: _decoration(l10n.settingsProteinG),
                      validator: (v) =>
                          double.tryParse((v ?? '').trim()) == null
                              ? l10n.number
                              : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _carbsController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: _decoration(l10n.settingsCarbsG),
                      validator: (v) =>
                          double.tryParse((v ?? '').trim()) == null
                              ? l10n.number
                              : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _fatsController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: _decoration(l10n.settingsFatsG),
                      validator: (v) =>
                          double.tryParse((v ?? '').trim()) == null
                              ? l10n.number
                              : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _caloriesController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: _decoration(l10n.settingsCalories),
                      validator: (v) =>
                          int.tryParse((v ?? '').trim()) == null ? l10n.number : null,
                    ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

