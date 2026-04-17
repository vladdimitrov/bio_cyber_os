import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SessionVault {
  SessionVault._();

  static const _kRefreshToken = 'sb_refresh_token';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<void> saveFromCurrentSession() async {
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.refreshToken;
    if (token == null || token.trim().isEmpty) {
      // ignore: avoid_print
      print(
        'DEBUG: SessionVault.saveFromCurrentSession: refreshToken is null/empty '
        '(session=${session != null})',
      );
      return;
    }
    await _storage.write(key: _kRefreshToken, value: token);
  }

  static Future<void> saveRefreshToken(String? refreshToken) async {
    final t = (refreshToken ?? '').trim();
    if (t.isEmpty) {
      // ignore: avoid_print
      print('DEBUG: SessionVault.saveRefreshToken: token empty (not saved)');
      return;
    }
    await _storage.write(key: _kRefreshToken, value: t);
  }

  static Future<String?> readRefreshToken() => _storage.read(key: _kRefreshToken);

  static Future<bool> hasRefreshToken() async {
    final v = await readRefreshToken();
    return (v ?? '').trim().isNotEmpty;
  }
}

