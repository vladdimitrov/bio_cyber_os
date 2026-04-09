import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bio_cyber_os/l10n/app_localizations.dart';

import '../../../app_shell.dart';
import '../../../core/security/biometric_auth_service.dart';
import '../../../core/security/session_vault.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
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
          _goToApp();
          return;
        }

        final refreshToken = await SessionVault.readRefreshToken();
        if ((refreshToken ?? '').trim().isEmpty) {
          // ignore: avoid_print
          print(
            'DEBUG: Biometric unlock: no refresh token in secure storage. '
            'After manual login, expected it to be persisted.',
          );
          _showError('No saved session. Please log in once with email & password.');
          return;
        }

        final res = await client.auth.setSession(refreshToken!.trim());
        final restored = res.session ?? client.auth.currentSession;
        if (restored != null) {
          if (!mounted) return;
          _goToApp();
          return;
        }
        _showError('Session restore failed. Please log in with email & password.');
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
        await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
        await SessionVault.saveFromCurrentSession();
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
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    const amber = Color(0xFFFFC107);
    final l10n = AppLocalizations.of(context)!;
    final hasSession = Supabase.instance.client.auth.currentSession != null;
    final showBiometric = _isLogin && _biometricAvailable;
    final canUseBiometric = _biometricEnabled && (_hasStoredSession || hasSession);

    return Stack(
      children: [
        Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            title: Text(_isLogin ? l10n.logIn : l10n.signUp),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                if (!_isLogin) ...[
                  TextField(
                    controller: _username,
                    style: const TextStyle(color: cyan, fontFamily: 'monospace'),
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
                  style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                  decoration: const InputDecoration(labelText: 'Email'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  style: const TextStyle(color: cyan, fontFamily: 'monospace'),
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
                    style: const TextStyle(color: cyan, fontFamily: 'monospace'),
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
                if (showBiometric) ...[
                  const SizedBox(height: 10),
                  IconButton(
                    tooltip: 'Log in with biometrics',
                    onPressed: _busy
                        ? null
                        : () async {
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
                      color: canUseBiometric ? amber : amber.withOpacity(0.35),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _isLogin = !_isLogin),
                  child: Text(
                    _isLogin ? 'Need an account? Sign up' : 'Have an account? Log in',
                    style: const TextStyle(color: cyan),
                  ),
                ),
                  ],
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

