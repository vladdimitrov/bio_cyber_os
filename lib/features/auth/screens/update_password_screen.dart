import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_screen.dart';

class UpdatePasswordScreen extends StatefulWidget {
  const UpdatePasswordScreen({super.key});

  @override
  State<UpdatePasswordScreen> createState() => _UpdatePasswordScreenState();
}

class _UpdatePasswordScreenState extends State<UpdatePasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _showSnack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  bool _isStrongPassword(String p) {
    final okLen = p.length >= 8;
    final hasUpper = RegExp(r'[A-Z]').hasMatch(p);
    final hasDigit = RegExp(r'\d').hasMatch(p);
    return okLen && hasUpper && hasDigit;
  }

  Future<void> _updatePassword() async {
    final p = _password.text;
    final c = _confirm.text;
    if (p.isEmpty) {
      _showSnack('New password is required.', color: Colors.redAccent);
      return;
    }
    if (p != c) {
      _showSnack('Passwords do not match.', color: Colors.redAccent);
      return;
    }
    if (!_isStrongPassword(p)) {
      _showSnack(
        'Password must be at least 8 characters, include 1 uppercase letter, and 1 number.',
        color: Colors.redAccent,
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: p),
      );
      if (!mounted) return;
      _showSnack('Password updated. Please log in.', color: Colors.green);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (route) => false,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      _showSnack(e.message, color: Colors.redAccent);
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString(), color: Colors.redAccent);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);

    return Stack(
      children: [
        Scaffold(
          backgroundColor: bg,
          appBar: AppBar(title: const Text('Update Password')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _password,
                      obscureText: true,
                      style:
                          const TextStyle(color: cyan, fontFamily: 'monospace'),
                      decoration:
                          const InputDecoration(labelText: 'New Password'),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirm,
                      obscureText: true,
                      style:
                          const TextStyle(color: cyan, fontFamily: 'monospace'),
                      decoration:
                          const InputDecoration(labelText: 'Confirm Password'),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _busy ? null : _updatePassword(),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: _busy ? null : _updatePassword,
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('UPDATE PASSWORD'),
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

