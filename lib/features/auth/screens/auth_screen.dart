import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app_shell.dart';
import '../../../core/security/auth_credentials_vault.dart';
import '../../../core/security/biometric_auth_service.dart';
import '../../../core/security/session_vault.dart';
import '../../../core/settings/profile_settings.dart';
import '../../../core/theme/app_colors.dart';
import 'forgot_password_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _isLogin = true;
  bool _busy = false;
  /// Null until first probe of [AuthCredentialsVault] finishes.
  bool? _vaultHasCredentials;
  /// From [AuthCredentialsVault.debugSavedEmailCharLength]; drives gold UI when > 0.
  int? _vaultSavedEmailLength;
  /// True when `cyber_vault.json` exists (Android) or non-Android vault has creds.
  bool _biometricLinked = false;

  Timer? _vaultPollTimer;
  int _vaultPollAttempt = 0;

  late final AnimationController _bioBreath;

  @override
  void initState() {
    super.initState();
    _bioBreath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    // ignore: avoid_print
    print('DEBUG: AuthScreen initState — scheduling vault probe');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startVaultProbeAfterNavigationSettled());
    });
  }

  Future<void> _startVaultProbeAfterNavigationSettled() async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    final linkedEarly = await AuthCredentialsVault.isBiometricVaultLinked();
    if (mounted) {
      setState(() {
        _biometricLinked = linkedEarly;
        if (linkedEarly) _vaultHasCredentials = true;
      });
    }
    unawaited(AuthCredentialsVault.logPhysicalVaultForAuthScreen());
    unawaited(_checkVault());
    _vaultPollAttempt = 0;
    _vaultPollTimer?.cancel();
    _vaultPollTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      _vaultPollAttempt++;
      final i = _vaultPollAttempt;
      unawaited(() async {
        final linked = await AuthCredentialsVault.isBiometricVaultLinked();
        final result = await AuthCredentialsVault.hasSavedCredentials();
        if (!mounted) return;
        // ignore: avoid_print
        print('DEBUG: [POLLING] Attempt $i - Vault found: $result');
        setState(() {
          _biometricLinked = linked;
          if (linked || result) _vaultHasCredentials = true;
        });
        if (result) {
          t.cancel();
          _vaultPollTimer = null;
          final len = await AuthCredentialsVault.debugSavedEmailCharLength();
          if (!mounted) return;
          setState(() => _vaultSavedEmailLength = len);
          return;
        }
        if (linked) {
          t.cancel();
          _vaultPollTimer = null;
          return;
        }
        if (i >= 5) {
          t.cancel();
          _vaultPollTimer = null;
        }
      }());
    });
  }

  void _debugLogVaultEmptyV4() {
    // ignore: avoid_print
    print('DEBUG: Vault is empty for namespace v4');
  }

  /// Reads vault presence. Never clears the vault here — only explicit sign-out may delete.
  Future<bool> _probeVaultHasSavedCredentials() async {
    try {
      return await AuthCredentialsVault.hasSavedCredentials();
    } catch (e) {
      debugPrint('DEBUG: Vault Error: $e');
      return false;
    }
  }

  /// One vault read + critical log; avoids double-read when possible.
  Future<({bool hasCreds, int? emailLen, bool hasEmail})>
  _readVaultSnapshotForProbe() async {
    try {
      final r = await AuthCredentialsVault.readCredentials();
      final email = r.email;
      // ignore: avoid_print
      print('DEBUG: [CRITICAL] Vault Read Test - Email length: ${email?.length}');
      final hasEmail = (email ?? '').trim().isNotEmpty;
      final hasCreds =
          hasEmail && (r.password ?? '').isNotEmpty;
      if (AuthCredentialsVault.usesManualPreferencesVault) {
        // ignore: avoid_print
        print(
          'DEBUG: [FILE VAULT] Parsed credentials present: $hasCreds',
        );
      }
      return (hasCreds: hasCreds, emailLen: email?.length, hasEmail: hasEmail);
    } catch (e) {
      debugPrint('DEBUG: [CRITICAL] Vault Read Test - Email length: null ($e)');
      try {
        final hasCreds = await _probeVaultHasSavedCredentials();
        final emailLen = await AuthCredentialsVault.debugSavedEmailCharLength();
        // ignore: avoid_print
        print('DEBUG: [CRITICAL] Vault Read Test - Email length: $emailLen');
        final hasEmail = (emailLen ?? 0) > 0;
        if (AuthCredentialsVault.usesManualPreferencesVault) {
          // ignore: avoid_print
          print(
            'DEBUG: [FILE VAULT] Parsed credentials present: $hasCreds',
          );
        }
        return (hasCreds: hasCreds, emailLen: emailLen, hasEmail: hasEmail);
      } catch (e2) {
        debugPrint('DEBUG: Vault Error: $e2');
        return (hasCreds: false, emailLen: null, hasEmail: false);
      }
    }
  }

  /// Polls vault + biometric setting; updates UI as soon as vault data appears.
  Future<void> _checkVault() async {
    final linked = await AuthCredentialsVault.isBiometricVaultLinked();
    final snap = await _readVaultSnapshotForProbe();
    final hasCreds = snap.hasCreds;
    final emailLen = snap.emailLen;
    final hasEmail = snap.hasEmail;
    if ((hasEmail || linked) && mounted) {
      setState(() {
        _biometricLinked = linked;
        _vaultHasCredentials = true;
        _vaultSavedEmailLength = emailLen;
      });
    }
    final bioOn = await BiometricAuthService.isEnabled();
    // ignore: avoid_print
    print("DEBUG: Vault has credentials: $hasCreds");
    // ignore: avoid_print
    print(
      'DEBUG: BiometricAuthService.isEnabled: $bioOn '
      '(biometric row gold state follows vault data, not this flag)',
    );
    if (!mounted) return;
    setState(() {
      _biometricLinked = linked;
      _vaultHasCredentials = hasEmail || linked;
      _vaultSavedEmailLength = emailLen;
    });
    if (!hasCreds) _debugLogVaultEmptyV4();
  }

  Future<void> _saveCredentials(String email, String password) async {
    await AuthCredentialsVault.saveCredentials(email, password);
    final snap = await _readVaultSnapshotForProbe();
    final verified = snap.hasCreds;
    final emailLen = snap.emailLen;
    // ignore: avoid_print
    print('DEBUG: Hard-verifying vault after save: $verified');
    if (!mounted) return;
    final linkedAfterSave =
        await AuthCredentialsVault.isBiometricVaultLinked();
    setState(() {
      _biometricLinked = linkedAfterSave;
      _vaultHasCredentials = snap.hasEmail || linkedAfterSave;
      _vaultSavedEmailLength = emailLen;
    });
    if (!verified) _debugLogVaultEmptyV4();
  }

  static const _kLinkBiometricsSnack =
      'Please login manually once to link biometrics.';
  static const _kSecurityKeyExpiredSnack =
      'Security key expired. Please login manually once to refresh.';

  /// Fingerprint row: when vault file (or saved creds) exists, go straight to auth.
  Future<void> _onBiometricButtonPressed() async {
    if (_busy || !mounted) return;
    final linked = await AuthCredentialsVault.isBiometricVaultLinked();
    if (!mounted) return;
    setState(() {
      _biometricLinked = linked;
      if (linked) _vaultHasCredentials = true;
    });
    if (!linked) {
      _showGoldSnack(_kLinkBiometricsSnack);
      return;
    }
    try {
      await _biometricLoginFromVault();
    } catch (e, st) {
      debugPrint('DEBUG: _onBiometricButtonPressed: $e $st');
      if (mounted) _showBiometricDiagnosticSnack(e);
    }
  }

  /// On-device diagnostic (Huawei / no adb): shows full exception text.
  void _showBiometricDiagnosticSnack(Object e) {
    if (!mounted) return;
    final msg = 'Error: ${e.toString()}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(
            color: AppColors.cyberGold,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
        backgroundColor: Colors.black87,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 12),
      ),
    );
  }

  /// [local_auth] → read vault → Supabase password sign-in (vault non-empty; no auto-prompt).
  Future<void> _biometricLoginFromVault() async {
    if (!mounted) return;
    try {
      final localAuth = LocalAuthentication();
      final canCheck = await localAuth.canCheckBiometrics;
      final supported = await localAuth.isDeviceSupported();
      debugPrint(
        'DEBUG: AuthScreen._biometricLoginFromVault pre-check '
        'canCheckBiometrics=$canCheck isDeviceSupported=$supported',
      );
      if (!canCheck && !supported) return;

      final types = await localAuth.getAvailableBiometrics();
      if (types.isEmpty) return;

      final ok = await localAuth.authenticate(
        localizedReason: 'Authenticate to sign in to Bio-Cyber OS',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (!mounted) return;
      if (!ok) {
        debugPrint(
          'DEBUG: AuthScreen._biometricLoginFromVault: local_auth canceled or failed',
        );
        return;
      }

      // Gold spinner while Supabase runs (after biometric sheet closes).
      setState(() => _busy = true);
      try {
        final ({String? email, String? password}) creds;
        try {
          creds = await AuthCredentialsVault.readCredentials();
        } catch (e, st) {
          debugPrint('DEBUG: readCredentials failed: $e $st');
          if (!mounted) return;
          final filePresent =
              await AuthCredentialsVault.physicalVaultFileExists();
          if (!mounted) return;
          if (filePresent) {
            _showGoldSnack(_kSecurityKeyExpiredSnack);
          } else {
            setState(() {
              _vaultHasCredentials = false;
              _vaultSavedEmailLength = null;
              _biometricLinked = false;
            });
            _debugLogVaultEmptyV4();
            _showGoldSnack(_kLinkBiometricsSnack);
          }
          return;
        }
        final email = creds.email?.trim() ?? '';
        final password = creds.password ?? '';
        if (email.isEmpty || password.isEmpty) {
          debugPrint(
            'DEBUG: AuthScreen._biometricLoginFromVault: vault empty after biometric OK',
          );
          if (!mounted) return;
          final filePresent =
              await AuthCredentialsVault.physicalVaultFileExists();
          if (!mounted) return;
          if (filePresent) {
            _showGoldSnack(_kSecurityKeyExpiredSnack);
          } else {
            setState(() {
              _vaultHasCredentials = false;
              _vaultSavedEmailLength = null;
              _biometricLinked = false;
            });
            _debugLogVaultEmptyV4();
            _showGoldSnack(_kLinkBiometricsSnack);
          }
          return;
        }

        final supabase = Supabase.instance.client;
        final response = await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );

        final session = response.session;
        if (session == null) {
          debugPrint(
            'DEBUG: AuthScreen._biometricLoginFromVault: signInWithPassword returned null session',
          );
          if (!mounted) return;
          _showBiometricDiagnosticSnack(
            StateError('Sign-in did not return a session. Check your password and try again.'),
          );
          return;
        }

        await SessionVault.saveRefreshToken(session.refreshToken);
        await SessionVault.saveFromCurrentSession();
        await ProfileSettings.ensureRemoteProfileRow();
        await _saveCredentials(email, password);
        if (!mounted) return;
        _goToApp();
      } on AuthException catch (e) {
        debugPrint(
          'DEBUG: AuthScreen._biometricLoginFromVault AuthException: ${e.message}',
        );
        if (!mounted) return;
        _showBiometricDiagnosticSnack(e);
      } catch (e, st) {
        debugPrint('DEBUG: AuthScreen._biometricLoginFromVault sign-in error: $e $st');
        if (!mounted) return;
        _showBiometricDiagnosticSnack(e);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } on PlatformException catch (e, st) {
      debugPrint('DEBUG: AuthScreen._biometricLoginFromVault PlatformException: $e $st');
      if (mounted) {
        _showBiometricDiagnosticSnack(e);
      }
    } catch (e, st) {
      debugPrint('DEBUG: AuthScreen._biometricLoginFromVault error: $e $st');
      if (mounted) {
        _showBiometricDiagnosticSnack(e);
      }
    }
  }

  void _showGoldSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: AppColors.cyberGold,
            fontFamily: 'monospace',
          ),
        ),
        backgroundColor: Colors.black87,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static const _logoAsset = 'assets/images/heart_logo_transparent.png';
  /// Exact brand spinner gold (#FFD700) — do not substitute with theme tints.
  static const _spinnerGold = Color(0xFFFFD700);
  static const _pureBlack = Color(0xFF000000);
  static const _neonCyan = Color(0xFF00FFFF);
  static const _bronzeBorder = Color(0xFFB89A5E);
  static const _bronzeText = Color(0xFFD4BC7E);
  static const _inputTextStyle = TextStyle(
    color: _bronzeText,
    fontFamily: 'monospace',
  );

  void _goToApp() {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(
        builder: (_) => AppShell(key: AppShell.shellKey),
      ),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _bioBreath.dispose();
    _vaultPollTimer?.cancel();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  bool _isStrongPassword(String p) {
    // At least 8 chars, 1 uppercase, 1 number.
    final okLen = p.length >= 8;
    final hasUpper = RegExp(r'[A-Z]').hasMatch(p);
    final hasDigit = RegExp(r'\d').hasMatch(p);
    return okLen && hasUpper && hasDigit;
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    final confirm = _confirmPassword.text;
    final usernameRaw = _username.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showError('Email and Password are required.');
      return;
    }

    if (!_isLogin) {
      if (password != confirm) {
        _showError('Passwords do not match.');
        return;
      }
      if (!_isStrongPassword(password)) {
        _showError(
          'Password must be at least 8 characters, include 1 uppercase letter, and 1 number.',
        );
        return;
      }
    }

    setState(() => _busy = true);
    try {
      if (_isLogin) {
        final res = await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
        final session = res.session;
        final user = res.user ?? session?.user;
        if (session == null || user == null) {
          if (!mounted) return;
          _showError('Sign-in did not return a valid session. Try again.');
          return;
        }
        await SessionVault.saveRefreshToken(session.refreshToken);
        await SessionVault.saveFromCurrentSession(); // fallback
        await ProfileSettings.ensureRemoteProfileRow();
        await _saveCredentials(email, password);
        // ignore: avoid_print
        print('DEBUG: Vault updated after successful manual login (email len=${email.length})');
        final hasStored = await SessionVault.hasRefreshToken();
        // ignore: avoid_print
        print('DEBUG: After manual login, stored refresh token: $hasStored');
        if (!mounted) return;
        _goToApp();
      } else {
        final generatedUsername = usernameRaw.isNotEmpty
            ? usernameRaw
            : (email.contains('@') ? email.split('@').first : email);
        await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
          data: {'username': generatedUsername},
        );
        if (!mounted) return;
        // Depending on Supabase auth settings, signUp may require email confirmation
        // and not create an active session immediately.
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Account created. Please check your email to confirm, then log in.',
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }
        await SessionVault.saveRefreshToken(session.refreshToken);
        await SessionVault.saveFromCurrentSession();
        await ProfileSettings.ensureRemoteProfileRow();
        await _saveCredentials(email, password);
        // ignore: avoid_print
        print('DEBUG: Vault updated after successful sign-up with session');
        if (!mounted) return;
        _goToApp();
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      final m = e.message.toLowerCase();
      if (m.contains('already') &&
          (m.contains('registered') || m.contains('exists'))) {
        _showError('An account with this email already exists. Please Log In.');
      } else {
        _showError(e.message);
      }
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _authFieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: _bronzeText.withValues(alpha: 0.9)),
      floatingLabelStyle: const TextStyle(color: _bronzeText),
      filled: true,
      fillColor: Colors.black.withValues(alpha: 0.3),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: _bronzeBorder, width: 1),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.cyberGold, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.redAccent.withValues(alpha: 0.9)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.redAccent.withValues(alpha: 0.95)),
      ),
    );
  }

  Widget _buildStaticHeartLogo() {
    return Center(
      child: Image.asset(
        _logoAsset,
        height: 292,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }

  /// Login tab: tappable row re-probes vault; styling reflects creds + biometric setting.
  Widget _buildBiometricSignInRow() {
    const gold = AppColors.cyberGold;
    final muted = AppColors.cyberGold.withValues(alpha: 0.38);
    final hasCreds = _vaultHasCredentials == true;
    final emailLenPositive = (_vaultSavedEmailLength ?? 0) > 0;
    // Gold when parsed creds, email length, or physical file vault is present.
    final looksEnabled =
        hasCreds || emailLenPositive || _biometricLinked;
    final canTap = !_busy;

    final icon = ScaleTransition(
      scale: Tween<double>(begin: 0.96, end: 1.0).animate(
        CurvedAnimation(parent: _bioBreath, curve: Curves.easeInOut),
      ),
      child: Icon(
        Icons.fingerprint,
        size: 52,
        color: looksEnabled ? gold : muted,
        shadows: looksEnabled
            ? [
                Shadow(color: gold.withValues(alpha: 0.75), blurRadius: 18),
                Shadow(color: gold.withValues(alpha: 0.4), blurRadius: 28),
              ]
            : null,
      ),
    );

    // Standalone icon on black — no bordered button, no decorated container.
    final button = Center(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: canTap ? _onBiometricButtonPressed : null,
          splashColor: gold.withValues(alpha: 0.12),
          highlightColor: gold.withValues(alpha: 0.06),
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: icon,
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        // Hidden as soon as file vault is linked or creds/email are known.
        Visibility(
          visible: !_biometricLinked &&
              _vaultHasCredentials != true &&
              (_vaultSavedEmailLength ?? 0) == 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
            child: Text(
              _kLinkBiometricsSnack,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.cyberGold.withValues(alpha: 0.82),
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.45,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _cyberPrimaryButton({
    required String label,
    required VoidCallback? onPressed,
    required bool busy,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Ink(
          height: 54,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            border: Border.all(color: _bronzeBorder, width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.cyberGold,
                    ),
                  )
                : Text(
                    label.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.cyberGold,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      fontFamily: 'monospace',
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const frameCyan = Color(0xFF00FFFF);
    const outerEdgeBlack = Color(0xFF000000);
    const innerIndigo = Color(0xFF4B0082);

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        const ColoredBox(color: _pureBlack),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: outerEdgeBlack, width: 2),
              ),
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  // Mystical neon aura — diffuse cyan field (no Border.all).
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _AuthNeonAuraFramePainter(
                        cyan: frameCyan,
                        innerPurple: innerIndigo,
                      ),
                    ),
                  ),
                  // Content plate: flat black; edge read comes from painter + shadows only.
                  Positioned.fill(
                    child: Container(
                      margin: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _pureBlack,
                        boxShadow: [
                          BoxShadow(
                            color: frameCyan.withValues(alpha: 0.28),
                            blurRadius: 32,
                            spreadRadius: 4,
                          ),
                          BoxShadow(
                            color: frameCyan.withValues(alpha: 0.12),
                            blurRadius: 48,
                            spreadRadius: 8,
                          ),
                          BoxShadow(
                            color: innerIndigo.withValues(alpha: 0.42),
                            blurRadius: 22,
                            spreadRadius: -6,
                          ),
                          BoxShadow(
                            color: innerIndigo.withValues(alpha: 0.22),
                            blurRadius: 28,
                            spreadRadius: -8,
                          ),
                        ],
                      ),
                      child: Scaffold(
                  backgroundColor: _pureBlack,
                  resizeToAvoidBottomInset: true,
                  body: Theme(
                    data: Theme.of(context).copyWith(
                      scaffoldBackgroundColor: _pureBlack,
                      canvasColor: _pureBlack,
                      colorScheme: Theme.of(context).colorScheme.copyWith(
                        surface: _pureBlack,
                        onSurface: _bronzeText,
                        outline: _bronzeBorder,
                      ),
                    ),
                    child: SafeArea(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(horizontal: 22),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: constraints.maxWidth,
                                minHeight: constraints.maxHeight,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const SizedBox(height: 28),
                                  _buildStaticHeartLogo(),
                                  const SizedBox(height: 88),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 440,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (!_isLogin) ...[
                                          TextField(
                                            controller: _username,
                                            style: _inputTextStyle,
                                            cursorColor: AppColors.cyberGold,
                                            decoration: _authFieldDecoration(
                                              'Username (Optional)',
                                            ),
                                            textInputAction:
                                                TextInputAction.next,
                                          ),
                                          const SizedBox(height: 14),
                                        ],
                                        TextField(
                                          controller: _email,
                                          keyboardType:
                                              TextInputType.emailAddress,
                                          style: _inputTextStyle,
                                          cursorColor: AppColors.cyberGold,
                                          decoration: _authFieldDecoration(
                                            'Email',
                                          ),
                                          textInputAction: TextInputAction.next,
                                        ),
                                        const SizedBox(height: 14),
                                        TextField(
                                          controller: _password,
                                          obscureText: true,
                                          style: _inputTextStyle,
                                          cursorColor: AppColors.cyberGold,
                                          decoration: _authFieldDecoration(
                                            'Password',
                                          ),
                                          textInputAction: _isLogin
                                              ? TextInputAction.done
                                              : TextInputAction.next,
                                          onSubmitted: (_) =>
                                              (_busy || !_isLogin)
                                              ? null
                                              : _submit(),
                                        ),
                                        if (!_isLogin) ...[
                                          const SizedBox(height: 14),
                                          TextField(
                                            controller: _confirmPassword,
                                            obscureText: true,
                                            style: _inputTextStyle,
                                            cursorColor: AppColors.cyberGold,
                                            decoration: _authFieldDecoration(
                                              'Confirm Password',
                                            ),
                                            onSubmitted: (_) =>
                                                _busy ? null : _submit(),
                                            textInputAction:
                                                TextInputAction.done,
                                          ),
                                        ],
                                        if (_isLogin) ...[
                                          const SizedBox(height: 20),
                                          _buildBiometricSignInRow(),
                                          const SizedBox(height: 18),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: TextButton(
                                              onPressed: _busy
                                                  ? null
                                                  : () {
                                                      Navigator.of(
                                                        context,
                                                      ).push(
                                                        MaterialPageRoute<void>(
                                                          builder: (_) =>
                                                              const ForgotPasswordScreen(),
                                                        ),
                                                      );
                                                    },
                                              style: TextButton.styleFrom(
                                                foregroundColor: _neonCyan,
                                                padding: EdgeInsets.zero,
                                                minimumSize: Size.zero,
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ),
                                              child: const Text(
                                                'Forgot Password?',
                                                style: TextStyle(
                                                  fontFamily: 'monospace',
                                                  decoration:
                                                      TextDecoration.underline,
                                                  decorationColor: _neonCyan,
                                                  shadows: [
                                                    Shadow(
                                                      color: _neonCyan,
                                                      blurRadius: 12,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 22),
                                        _cyberPrimaryButton(
                                          label: _isLogin
                                              ? 'LOG IN'
                                              : 'CREATE ACCOUNT',
                                          onPressed: _busy ? null : _submit,
                                          busy: _busy,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 40),
                                  Center(
                                    child: TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => setState(
                                              () => _isLogin = !_isLogin,
                                            ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: _neonCyan,
                                      ),
                                      child: Text(
                                        _isLogin
                                            ? 'Need an account? Sign up'
                                            : 'Have an account? Log in',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          decoration: TextDecoration.underline,
                                          decorationColor: _neonCyan,
                                          shadows: [
                                            Shadow(
                                              color: _neonCyan,
                                              blurRadius: 14,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    height:
                                        MediaQuery.paddingOf(context).bottom +
                                        20,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
        ),
        if (_busy) ...[
          const ModalBarrier(dismissible: false, color: Color(0x99000000)),
          Center(
            child: CircularProgressIndicator(
              color: _spinnerGold,
            ),
          ),
        ],
      ],
    );
  }
}

/// Mystical neon frame: diffuse outer cyan (#00FFFF) + soft inner indigo (#4B0082).
/// Uses blurred strokes only — no `Border.all` on the aura path.
class _AuthNeonAuraFramePainter extends CustomPainter {
  _AuthNeonAuraFramePainter({
    required this.cyan,
    required this.innerPurple,
  });

  final Color cyan;
  final Color innerPurple;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Offset.zero & size;

    void haze(
      Rect r,
      Color color,
      double blurSigma,
      double strokeWidth,
      double opacity,
    ) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = color.withValues(alpha: opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma);
      canvas.drawRect(r, paint);
    }

    // Outer energy field — cyan, wide blur (layers build a soft halo).
    haze(outer, cyan, 30, 8, 0.2);
    haze(outer.deflate(4), cyan, 24, 5, 0.14);
    haze(outer.deflate(8), cyan, 18, 3, 0.09);

    // Inner veil — deep purple, tighter blur (reads as inner rim glow).
    const inset = 12.0;
    final inner = outer.deflate(inset);
    haze(inner, innerPurple, 16, 2, 0.48);
    haze(inner.deflate(2), innerPurple, 12, 1, 0.3);
  }

  @override
  bool shouldRepaint(covariant _AuthNeonAuraFramePainter oldDelegate) {
    return oldDelegate.cyan != cyan || oldDelegate.innerPurple != innerPurple;
  }
}
