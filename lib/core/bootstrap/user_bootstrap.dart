import 'package:supabase_flutter/supabase_flutter.dart';

/// Runs before [runApp] so auth session is hydrated from storage and optional
/// user rows are touched once (warms connection, reduces first-frame null user).
class UserBootstrap {
  UserBootstrap._();

  static Future<void> initialize() async {
    final client = Supabase.instance.client;
    // Yield so Supabase can finish hydrating the session from storage (web/desktop).
    await Future<void>.delayed(Duration.zero);

    final uid = client.auth.currentUser?.id;
    if (uid == null) return;

    try {
      await Future.wait([
        client.from('profiles').select('id').eq('id', uid).maybeSingle(),
        client
            .from('user_targets')
            .select('user_id')
            .eq('user_id', uid)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle(),
      ]);
    } catch (_) {}
  }
}
