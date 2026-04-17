import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _showSnack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  Future<void> _sendResetLink() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      _showSnack('Email is required.', color: Colors.redAccent);
      return;
    }

    setState(() => _busy = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'io.supabase.biocyberos://reset-password',
      );
      if (!mounted) return;
      _showSnack(
        'Reset link sent. Check your email.',
        color: Colors.green,
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

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(title: const Text('Forgot Password')),
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
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'you@example.com',
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _busy ? null : _sendResetLink(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _busy ? null : _sendResetLink,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('SEND RESET LINK'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

