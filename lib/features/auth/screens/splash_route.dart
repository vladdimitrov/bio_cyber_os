import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app_shell.dart';
import 'auth_screen.dart';

class SplashRoute extends StatefulWidget {
  const SplashRoute({super.key});

  @override
  State<SplashRoute> createState() => _SplashRouteState();
}

class _SplashRouteState extends State<SplashRoute> {
  StreamSubscription<AuthState>? _sub;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _route());
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (!mounted) return;
      _route();
    });
  }

  void _route() {
    if (_navigating) return;
    final session = Supabase.instance.client.auth.currentSession;
    final next = session == null
        ? const AuthScreen()
        : AppShell(key: AppShell.shellKey);
    _navigating = true;
    _sub?.cancel();
    _sub = null;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => next),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF050510),
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

