import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bio_cyber_os/l10n/app_localizations.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/settings/locale_settings.dart';
import '../../../core/settings/measurement_settings.dart';
import '../../../core/settings/unit_converter.dart';
import '../../../core/settings/notification_settings.dart';
import '../../auth/screens/splash_route.dart';

const _kPrefHeightCm = 'profile_height_cm';
const _kPrefWeightKg = 'profile_weight_kg';
const _kPrefAge = 'profile_age';

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

  Timer? _profileRemoteDebounce;
  Timer? _targetsRemoteDebounce;

  bool _hydratingProfile = false;
  bool _hydratingTargets = false;

  MeasurementSystem _measurementSystem = MeasurementSystem.metric;
  bool _notificationsEnabled = false;
  bool _updatingDisplay = false;

  void _onProfileFieldsChanged() {
    if (_hydratingProfile) return;
    setState(() {});
    unawaited(_saveProfileLocal());
    _profileRemoteDebounce?.cancel();
    _profileRemoteDebounce = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      unawaited(_persistProfileRemote());
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
      final p = await SharedPreferences.getInstance();
      final hRaw = _heightCmController.text.trim();
      final wRaw = _weightKgController.text.trim();

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

      await p.setString(_kPrefHeightCm, hCm?.toString() ?? '');
      await p.setString(_kPrefWeightKg, wKg?.toString() ?? '');
      await p.setString(_kPrefAge, _ageController.text.trim());
    } catch (_) {}
  }

  Future<void> _loadProfileFromPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      final hCm = _parseOptionalDouble(p.getString(_kPrefHeightCm) ?? '');
      final wKg = _parseOptionalDouble(p.getString(_kPrefWeightKg) ?? '');
      _updatingDisplay = true;
      _heightCmController.text = (_measurementSystem == MeasurementSystem.imperial && hCm != null)
          ? UnitConverter.cmToInches(hCm).toStringAsFixed(0)
          : (hCm?.toStringAsFixed(0) ?? '');
      _weightKgController.text = (_measurementSystem == MeasurementSystem.imperial && wKg != null)
          ? UnitConverter.kgToLbs(wKg).toStringAsFixed(1)
          : (wKg?.toStringAsFixed(1) ?? '');
      _updatingDisplay = false;
      _ageController.text = p.getString(_kPrefAge) ?? '';
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
    MeasurementSettings.system.addListener(_onMeasurementChanged);
    NotificationSettings.enabled.addListener(_onNotificationsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapScreen());
  }

  Future<void> _bootstrapScreen() async {
    setState(() => _loading = true);
    await _loadProfileFromPrefs();
    final uid = _client.auth.currentUser?.id;
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
          .select('height_cm, weight_kg, age')
          .eq('id', uid)
          .maybeSingle();
      if (!mounted || row == null) return;

      final h = row['height_cm'];
      final w = row['weight_kg'];
      final a = row['age'];
      final hCm = h is num ? h.toDouble() : double.tryParse('$h');
      final wKg = w is num ? w.toDouble() : double.tryParse('$w');
      final ageStr = a == null ? '' : '$a'.trim();

      _hydratingProfile = true;
      _updatingDisplay = true;
      _heightCmController.text =
          (_measurementSystem == MeasurementSystem.imperial && hCm != null)
              ? UnitConverter.cmToInches(hCm).toStringAsFixed(0)
              : (hCm != null ? hCm.toStringAsFixed(0) : '');
      _weightKgController.text =
          (_measurementSystem == MeasurementSystem.imperial && wKg != null)
              ? UnitConverter.kgToLbs(wKg).toStringAsFixed(1)
              : (wKg != null ? wKg.toStringAsFixed(1) : '');
      _ageController.text = ageStr;
      _updatingDisplay = false;
      _hydratingProfile = false;

      await _saveProfileLocal();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _persistProfileRemote() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;

    double? parseNum(String v) {
      final t = v.trim().replaceAll(',', '.');
      if (t.isEmpty) return null;
      return double.tryParse(t);
    }

    final hRaw = _heightCmController.text.trim();
    final wRaw = _weightKgController.text.trim();
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

    final payload = <String, dynamic>{
      'id': uid,
      'height_cm': hCm,
      'weight_kg': wKg,
      'age': ageTrim.isEmpty ? null : ageInt,
    };

    try {
      await _client.from('profiles').upsert(payload, onConflict: 'id');
    } catch (_) {}
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

  Future<void> _persistTargetsRemote({required bool showSnack}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    if (!_targetsParseOk()) return;

    if (showSnack) setState(() => _saving = true);
    try {
      final fields = <String, dynamic>{
        'protein_target': _parseDouble(_proteinController.text),
        'carbs_target': _parseDouble(_carbsController.text),
        'fat_target': _parseDouble(_fatsController.text),
        'calories_target': _parseInt(_caloriesController.text),
      };

      final existing = await _client
          .from('user_targets')
          .select('id')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (existing != null && existing['id'] != null) {
        await _client.from('user_targets').update(fields).eq('id', existing['id']);
      } else {
        await _client.from('user_targets').insert({...fields, 'user_id': uid});
      }

      if (showSnack && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.msgConfigSaved)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
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

  int _parseInt(String v) => int.tryParse(v.trim()) ?? 0;
  double _parseDouble(String v) => double.tryParse(v.trim()) ?? 0.0;

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
    await _persistProfileRemote();
    await _persistTargetsRemote(showSnack: true);
    final uid = _client.auth.currentUser?.id;
    if (uid != null) await _loadTargetsForUser(uid);
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    final l10n = AppLocalizations.of(context)!;
    final bmi = _bmiDisplay(l10n);

    return Scaffold(
      backgroundColor: bg,
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
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
                      key: ValueKey(LocaleSettings.preference),
                      initialValue: LocaleSettings.preference,
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
                    const SizedBox(height: 20),
                    SizedBox(
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
                  ],
                ),
              ),
            ),
    );
  }
}

