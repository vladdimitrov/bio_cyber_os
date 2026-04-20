import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Email/password for optional biometric quick sign-in (after [local_auth]).
/// Filled on each successful password sign-in; cleared on sign-out or when
/// biometrics are disabled in settings.
///
/// **Android:** AES-encrypted JSON in app **documents** (`cyber_vault.json`) —
/// bypasses SharedPreferences / cache isolation on Pixel debug.
/// **Other platforms:** unchanged [FlutterSecureStorage] keys.
class AuthCredentialsVault {
  AuthCredentialsVault._();

  static const _vaultFileName = 'cyber_vault.json';

  /// Same logical keys for iOS / desktop [FlutterSecureStorage].
  static const _kEmail = 'bio_auth_biometric_email';
  static const _kPassword = 'bio_auth_biometric_password';

  /// True when credentials use the Android file vault (not secure storage).
  static bool get usesManualPreferencesVault =>
      !kIsWeb && Platform.isAndroid;

  /// 32-byte AES-256 key derived from a fixed app secret (not device-unique).
  static final enc.Key _aesKey = enc.Key(
    Uint8List.fromList(
      sha256
          .convert(
            utf8.encode(
              'bio_cyber_os.credential_vault.v1|sha256_derived|do-not-reuse',
            ),
          )
          .bytes,
    ),
  );

  static final enc.Encrypter _encrypter = enc.Encrypter(enc.AES(_aesKey));

  static final FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static Future<File> _vaultFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_vaultFileName');
  }

  /// Whether `cyber_vault.json` exists (Android file vault only).
  static Future<bool> physicalVaultFileExists() async {
    if (!usesManualPreferencesVault) return false;
    final f = await _vaultFile();
    return f.existsSync();
  }

  /// UI "linked" state: Android = physical vault file present; else saved creds.
  static Future<bool> isBiometricVaultLinked() async {
    if (usesManualPreferencesVault) {
      return physicalVaultFileExists();
    }
    return hasSavedCredentials();
  }

  static void _logFileVaultSync(File file) {
    // ignore: avoid_print
    print('DEBUG: [FILE VAULT] Physical file exists: ${file.existsSync()}');
    // ignore: avoid_print
    print('DEBUG: [FILE VAULT] File path: ${file.path}');
  }

  static String _pack(enc.IV iv, enc.Encrypted e) =>
      jsonEncode({'i': iv.base64, 'd': e.base64});

  static String? _decryptOuterEnvelope(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final iv = enc.IV.fromBase64(m['i'] as String);
      final e = enc.Encrypted.fromBase64(m['d'] as String);
      return _encrypter.decrypt(e, iv: iv);
    } catch (_) {
      return null;
    }
  }

  /// Writes via temp file + rename so a failed encrypt/write never truncates
  /// an existing vault on disk.
  static Future<void> _writeAndroidVaultFile(String email, String password) async {
    final file = await _vaultFile();
    final dir = file.parent;
    final tmp = File('${dir.path}/.$_vaultFileName.tmp');
    final plain = jsonEncode({'email': email.trim(), 'password': password});
    final iv = enc.IV.fromSecureRandom(16);
    final encrypted = _encrypter.encrypt(plain, iv: iv);
    final outer = _pack(iv, encrypted);
    try {
      await tmp.writeAsString(outer, flush: true);
      final sz = tmp.statSync().size;
      if (sz <= 0) {
        throw StateError('vault temp file empty after write');
      }
      if (file.existsSync()) {
        await file.delete();
      }
      await tmp.rename(file.path);
    } catch (e, st) {
      try {
        if (tmp.existsSync()) await tmp.delete();
      } catch (_) {}
      debugPrint('DEBUG: [VAULT] Android write failed (original untouched): $e $st');
      rethrow;
    }
  }

  /// Logs physical vault path/exists (for [AuthScreen] init / diagnostics).
  static Future<void> logPhysicalVaultForAuthScreen() async {
    if (!usesManualPreferencesVault) return;
    final file = await _vaultFile();
    _logFileVaultSync(file);
  }

  /// Debug: saved email character count only (never the address).
  static Future<int?> debugSavedEmailCharLength() async {
    try {
      final e = (await read()).email;
      return e?.length;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String email, String password) async {
    if (usesManualPreferencesVault) {
      await _writeAndroidVaultFile(email, password);
      return;
    }
    await _secureStorage.write(key: _kEmail, value: email.trim());
    await _secureStorage.write(key: _kPassword, value: password);
  }

  /// Persists credentials; on Android verifies non-empty file on disk.
  static Future<void> saveCredentials(String email, String password) async {
    await save(email, password);
    if (usesManualPreferencesVault) {
      final file = await _vaultFile();
      if (!file.existsSync()) {
        throw StateError('vault file missing after saveCredentials');
      }
      final size = file.statSync().size;
      if (size <= 0) {
        throw StateError('vault file size is 0 after saveCredentials');
      }
    }
  }

  static Future<({String? email, String? password})> read() async {
    if (usesManualPreferencesVault) {
      final file = await _vaultFile();
      if (!file.existsSync()) {
        return (email: null, password: null);
      }
      try {
        final raw = await file.readAsString();
        final inner = _decryptOuterEnvelope(raw);
        if (inner == null || inner.isEmpty) {
          return (email: null, password: null);
        }
        final map = jsonDecode(inner) as Map<String, dynamic>;
        return (
          email: map['email'] as String?,
          password: map['password'] as String?,
        );
      } catch (_) {
        return (email: null, password: null);
      }
    }
    final email = await _secureStorage.read(key: _kEmail);
    final password = await _secureStorage.read(key: _kPassword);
    return (email: email, password: password);
  }

  /// Alias for [read] — used by the biometric → Supabase password bridge.
  static Future<({String? email, String? password})> readCredentials() async =>
      read();

  /// Checks vault file on disk (Android) and decrypts; logs physical state.
  static Future<bool> hasSavedCredentials() async {
    if (usesManualPreferencesVault) {
      final file = await _vaultFile();
      _logFileVaultSync(file);
      if (!file.existsSync()) return false;
      try {
        final raw = await file.readAsString();
        final inner = _decryptOuterEnvelope(raw);
        if (inner == null || inner.isEmpty) return false;
        final map = jsonDecode(inner) as Map<String, dynamic>;
        final em = map['email'] as String?;
        final pw = map['password'] as String?;
        return (em ?? '').trim().isNotEmpty && (pw ?? '').isNotEmpty;
      } catch (_) {
        return false;
      }
    }
    final r = await read();
    return (r.email ?? '').trim().isNotEmpty && (r.password ?? '').isNotEmpty;
  }

  /// Clears stored credentials. Only runs when [explicitUserRequest] is true
  /// (e.g. user pressed Sign Out). Never auto-called for null/expired sessions.
  static Future<void> clear({bool explicitUserRequest = false}) async {
    if (!explicitUserRequest) {
      debugPrint(
        'DEBUG: [VAULT] clear() skipped (explicitUserRequest=false): ${StackTrace.current}',
      );
      return;
    }
    debugPrint('DEBUG: [VAULT] Delete requested by: ${StackTrace.current}');
    if (usesManualPreferencesVault) {
      final file = await _vaultFile();
      if (file.existsSync()) {
        await file.delete();
      }
      return;
    }
    await _secureStorage.delete(key: _kEmail);
    await _secureStorage.delete(key: _kPassword);
  }

  /// Wipes all secure-storage keys for this app (non-Android). Same explicit gate as [clear].
  static Future<void> clearAll({bool explicitUserRequest = false}) async {
    if (!explicitUserRequest) {
      debugPrint(
        'DEBUG: [VAULT] clearAll() skipped (explicitUserRequest=false): ${StackTrace.current}',
      );
      return;
    }
    debugPrint('DEBUG: [VAULT] Delete requested by: ${StackTrace.current}');
    if (usesManualPreferencesVault) {
      await clear(explicitUserRequest: true);
      return;
    }
    await _secureStorage.deleteAll();
  }
}
