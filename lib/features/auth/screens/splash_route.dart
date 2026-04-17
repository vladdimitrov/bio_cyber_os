import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app_shell.dart';
import '../../../core/settings/profile_settings.dart';
import 'auth_screen.dart';
import 'update_password_screen.dart';

class SplashRoute extends StatefulWidget {
  const SplashRoute({super.key});

  @override
  State<SplashRoute> createState() => _SplashRouteState();
}

class _SplashRouteState extends State<SplashRoute> {
  StreamSubscription<AuthState>? _sub;
  Timer? _fallbackTimer;

  /// True after we have successfully called [Navigator.pushReplacement].
  bool _exitedSplash = false;

  /// Prevents overlapping bootstrap runs from auth stream + post-frame.
  bool _bootstrapInFlight = false;
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    debugPrint('DEBUG: SplashRoute mounted');

    // Race condition logic:
    // - Give Supabase up to 3s to emit INITIAL_SESSION / SIGNED_IN.
    // - Otherwise, force AuthScreen (no infinite black splash).
    _fallbackTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _exitedSplash) return;
      debugPrint('DEBUG: Splash fallback timer hit (3s) — AuthScreen');
      unawaited(_exitOnce(const AuthScreen()));
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrapFromSession().then((ok) async {
        if (!mounted || _exitedSplash) return;
        // If session exists immediately, proceed fast.
        if (ok) {
          _fallbackTimer?.cancel();
          _fallbackTimer = null;
          await _exitOnce(AppShell(key: AppShell.shellKey));
        }
      }));
    });

    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (!mounted || _exitedSplash) return;
      if (_isPasswordRecovery(state)) {
        unawaited(_exitOnce(const UpdatePasswordScreen()));
        return;
      }

      if (state.event == AuthChangeEvent.signedOut) {
        debugPrint('DEBUG: Auth stream SIGNED_OUT — AuthScreen');
        _fallbackTimer?.cancel();
        _fallbackTimer = null;
        unawaited(_exitOnce(const AuthScreen()));
        return;
      }

      if (state.event == AuthChangeEvent.initialSession ||
          state.event == AuthChangeEvent.signedIn) {
        debugPrint('DEBUG: Auth stream ${state.event} — bootstrap');
        unawaited(() async {
          final sessionNow = Supabase.instance.client.auth.currentSession;
          if (state.event == AuthChangeEvent.initialSession &&
              sessionNow == null &&
              mounted &&
              !_exitedSplash) {
            debugPrint(
              'DEBUG: Auth stream INITIAL_SESSION but session is null — AuthScreen',
            );
            _fallbackTimer?.cancel();
            _fallbackTimer = null;
            await _exitOnce(const AuthScreen());
            return;
          }
          final ok = await _bootstrapFromSession();
          if (!mounted || _exitedSplash) return;
          if (ok) {
            _fallbackTimer?.cancel();
            _fallbackTimer = null;
            await _exitOnce(AppShell(key: AppShell.shellKey));
          } else {
            // Session signal without a usable session -> route to Auth.
            _fallbackTimer?.cancel();
            _fallbackTimer = null;
            await _exitOnce(const AuthScreen());
          }
        }());
      }
    });
  }

  bool _isPasswordRecovery(AuthState state) {
    return state.event == AuthChangeEvent.passwordRecovery ||
        state.event.toString().toLowerCase().contains('passwordrecovery');
  }

  Future<void> _exitOnce(Widget next) async {
    if (_exitedSplash || _isNavigating) return;
    _exitedSplash = true;
    _isNavigating = true;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _sub?.cancel();
    _sub = null;
    if (!mounted) return;
    try {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => next),
      );
    } catch (e, st) {
      debugPrint('DEBUG: Splash navigation failed: $e $st');
    }
  }

  /// Returns true if a session was found and bootstrap succeeded enough to
  /// proceed to the dashboard. Returns false if no session (or bootstrap failed).
  Future<bool> _bootstrapFromSession() async {
    if (!mounted || _exitedSplash) return false;
    if (_bootstrapInFlight) return false;
    _bootstrapInFlight = true;
    try {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      debugPrint('DEBUG: _bootstrapFromSession: session is null');
      _fallbackTimer?.cancel();
      _fallbackTimer = null;
      // Must always navigate somewhere on null session.
      await _exitOnce(const AuthScreen());
      return false;
    }

    try {
      debugPrint('DEBUG: Fetching profile for UID: ${session.user.id}');
      // If hydrate fails (prefs/network), we should still escape splash and show login
      // rather than hanging on a black screen.
      var data = await ProfileSettings.hydrateFromSupabase().timeout(
        const Duration(seconds: 10),
      );
      debugPrint('DEBUG: Profile fetch result: $data');
      if (data == null) {
        debugPrint(
          'DEBUG: Profile null — best-effort ensureRemoteProfileRow + retry',
        );
        await ProfileSettings.ensureRemoteProfileRow();
        if (!mounted || _exitedSplash) return false;
        data = await ProfileSettings.hydrateFromSupabase().timeout(
          const Duration(seconds: 6),
        );
        debugPrint('DEBUG: Profile fetch result (retry): $data');
      }
      if (data == null) {
        debugPrint(
          'DEBUG: Profile still null after retry — continuing to AppShell (session preserved)',
        );
      }
    } on TimeoutException catch (e) {
      debugPrint('DEBUG: Profile fetch timed out: $e — AuthScreen');
      return false;
    } catch (e, st) {
      debugPrint('DEBUG: Profile fetch failed: $e $st — AuthScreen');
      return false;
    }

    if (!mounted || _exitedSplash) return false;
    debugPrint('DEBUG: Session bootstrap OK');
    return true;
    } finally {
      _bootstrapInFlight = false;
    }
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFF000000),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(height: 6),
            _SplashLogo(),
            SizedBox(height: 18),
            CircularProgressIndicator(
              color: Color(0xFFCBAB67),
              strokeWidth: 2.5,
            ),
          ],
        ),
      ),
    );
  }
}

class _SplashLogo extends StatelessWidget {
  const _SplashLogo();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Image.asset(
        'assets/images/heart_logo_transparent.png',
        height: 180,
        fit: BoxFit.contain,
      ),
    );
  }
}
