import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app_shell.dart';
import '../../../core/security/biometric_auth_service.dart';
import '../../../core/security/session_vault.dart';
import '../../../core/settings/profile_settings.dart';
import 'forgot_password_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _PulsingLogo extends StatefulWidget {
  const _PulsingLogo();

  @override
  State<_PulsingLogo> createState() => _PulsingLogoState();
}

class _PulsingLogoState extends State<_PulsingLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic)
        .drive(Tween<double>(begin: 0.86, end: 1.0));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic)
        .drive(Tween<double>(begin: 0.98, end: 1.02));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
        builder: (context, opacity, child) {
          return Opacity(opacity: opacity, child: child);
        },
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Image.asset(
              'assets/images/heart_logo_transparent.png',
              height: 180,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.favorite,
                  color: Colors.redAccent,
                  size: 120,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthScreenState extends State<AuthScreen> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _isLogin = true;
  bool _busy = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _hasStoredSession = false;

  void _goToApp() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => AppShell(key: AppShell.shellKey)),
    );
  }

  @override
  void initState() {
    super.initState();
    _initBiometrics();
  }

  Future<void> _initBiometrics() async {
    final available = await BiometricAuthService.isAvailable();
    final enabled = await BiometricAuthService.isEnabled();
    final hasStored = await SessionVault.hasRefreshToken();
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _biometricEnabled = enabled;
      _hasStoredSession = hasStored;
    });

    final session = Supabase.instance.client.auth.currentSession;
    if (_isLogin && available && enabled && session != null) {
      await _tryBiometricUnlock();
    }
  }

  Future<void> _tryBiometricUnlock() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await BiometricAuthService.authenticate();
      if (!mounted) return;
      if (ok) {
        final client = Supabase.instance.client;
        final session = client.auth.currentSession;
        if (session != null) {
          if (!mounted) return;
          // ignore: avoid_print
          print('VAULT_DEBUG: Authentication successful, launching session...');
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            // Let the Android biometric sheet fully dismiss before navigating.
            await Future<void>.delayed(const Duration(milliseconds: 300));
            if (!mounted) return;
            await Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => AppShell(key: AppShell.shellKey),
              ),
            );
          });
          return;
        }

        final refreshToken = await SessionVault.readRefreshToken();
        if ((refreshToken ?? '').trim().isEmpty) {
          // ignore: avoid_print
          print('TOKEN MISSING');
          // ignore: avoid_print
          print(
            'DEBUG: Biometric unlock: no refresh token in secure storage. '
            'After manual login, expected it to be persisted.',
          );
          _showError('No saved session. Please log in once with email & password.');
          return;
        }
        // ignore: avoid_print
        print('TOKEN FOUND');

        await client.auth.setSession(refreshToken!.trim());
        if (!mounted) return;

        // Give auth state a brief moment to hydrate user/session after setSession.
        final start = DateTime.now();
        while (client.auth.currentSession == null &&
            DateTime.now().difference(start) <
                const Duration(milliseconds: 1200)) {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        }
        debugPrint(
          'DEBUG: After biometric setSession: '
          'currentSession=${client.auth.currentSession != null} '
          'currentUser=${client.auth.currentUser != null}',
        );

        // Best-effort: ensure profile row exists; never block navigation.
        await ProfileSettings.ensureRemoteProfileRow();
        // ignore: avoid_print
        print('VAULT_DEBUG: Forcing jump to AppShell regardless of profile state');
        // ignore: avoid_print
        print('VAULT_DEBUG: Authentication successful, launching session...');
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          await Future<void>.delayed(const Duration(milliseconds: 300));
          if (!mounted) return;
          await Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => AppShell(key: AppShell.shellKey),
            ),
          );
        });
        return;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.redAccent,
      ),
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
        await SessionVault.saveRefreshToken(res.session?.refreshToken);
        await SessionVault.saveFromCurrentSession(); // fallback
        await ProfileSettings.ensureRemoteProfileRow();
        final hasStored = await SessionVault.hasRefreshToken();
        // ignore: avoid_print
        print('DEBUG: After manual login, stored refresh token: $hasStored');
        if (mounted) setState(() => _hasStoredSession = hasStored);
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
        _goToApp();
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      final m = e.message.toLowerCase();
      if (m.contains('already') && (m.contains('registered') || m.contains('exists'))) {
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

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF000000);
    // Extracted from assets/images/heart_logo.png
    const logoCyan = Color(0xFF43B8DC);
    const logoGold = Color(0xFFCBAB67);
    final hasSession = Supabase.instance.client.auth.currentSession != null;
    final showBiometric = _isLogin && _biometricAvailable;
    final canUseBiometric = _biometricEnabled && (_hasStoredSession || hasSession);

    return Stack(
      children: [
        Scaffold(
          backgroundColor: bg,
          resizeToAvoidBottomInset: false,
          body: SafeArea(
            child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _PulsingLogo(),
                    const SizedBox(height: 18),
                if (!_isLogin) ...[
                  TextField(
                    controller: _username,
                    style:
                        const TextStyle(color: logoCyan, fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      labelText: 'Username (Optional)',
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  style:
                      const TextStyle(color: logoCyan, fontFamily: 'monospace'),
                  decoration: const InputDecoration(labelText: 'Email'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  style:
                      const TextStyle(color: logoCyan, fontFamily: 'monospace'),
                  decoration: const InputDecoration(labelText: 'Password'),
                  textInputAction:
                      _isLogin ? TextInputAction.done : TextInputAction.next,
                  onSubmitted: (_) => (_busy || !_isLogin) ? null : _submit(),
                ),
                if (!_isLogin) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmPassword,
                    obscureText: true,
                    style: const TextStyle(
                      color: logoCyan,
                      fontFamily: 'monospace',
                    ),
                    decoration:
                        const InputDecoration(labelText: 'Confirm Password'),
                    onSubmitted: (_) => _busy ? null : _submit(),
                    textInputAction: TextInputAction.done,
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_isLogin ? 'LOG IN' : 'CREATE ACCOUNT'),
                  ),
                ),
                if (_isLogin) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ForgotPasswordScreen(),
                                ),
                              );
                            },
                      child: const Text(
                        'Forgot Password?',
                        style: TextStyle(color: logoCyan),
                      ),
                    ),
                  ),
                ],
                if (showBiometric) ...[
                  const SizedBox(height: 10),
                  IconButton(
                    tooltip: 'Log in with biometrics',
                    onPressed: _busy
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final supported =
                                await BiometricAuthService.isAvailable();
                            if (!supported) {
                              if (!mounted) return;
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'This device does not support biometrics.',
                                  ),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                              return;
                            }
                            if (!_biometricEnabled) {
                              _showError(
                                'Enable biometrics in Settings → SECURITY first.',
                              );
                              return;
                            }
                            if (!canUseBiometric) {
                              _showError(
                                'No saved session. Please log in once with email & password.',
                              );
                              return;
                            }
                            await _tryBiometricUnlock();
                          },
                    icon: Icon(
                      Icons.fingerprint,
                      size: 34,
                      color: canUseBiometric
                          ? logoGold
                          : logoGold.withValues(alpha: 0.35),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _isLogin = !_isLogin),
                  child: Text(
                    _isLogin ? 'Need an account? Sign up' : 'Have an account? Log in',
                    style: const TextStyle(color: logoCyan),
                  ),
                ),
                  ],
                ),
              ),
            ),
          ),
          ),
        ),
        if (_busy) ...[
          const ModalBarrier(dismissible: false, color: Color(0x99000000)),
          const Center(child: CircularProgressIndicator()),
        ],
      ],
    );
  }
}

