import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Stores Supabase auth session in encrypted storage (Android/iOS) where possible.
///
/// This helps biometric "unlock" flows because a prior manual login session is
/// reliably persisted between restarts without using plain SharedPreferences.
class SupabaseSecureLocalStorage extends LocalStorage {
  SupabaseSecureLocalStorage();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<String?> accessToken() => _storage.read(key: supabasePersistSessionKey);

  @override
  Future<void> initialize() async {
    // No-op for secure storage.
  }

  @override
  Future<bool> hasAccessToken() async {
    final v = await accessToken();
    return (v ?? '').trim().isNotEmpty;
  }

  @override
  Future<void> persistSession(String persistSessionString) {
    return _storage.write(key: supabasePersistSessionKey, value: persistSessionString);
  }

  @override
  Future<void> removePersistedSession() {
    return _storage.delete(key: supabasePersistSessionKey);
  }
}

