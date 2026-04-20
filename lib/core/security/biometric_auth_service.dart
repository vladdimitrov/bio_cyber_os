import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class BiometricAuthService {
  BiometricAuthService._();

  static const _kBiometricEnabled = 'biometric_enabled';

  static final LocalAuthentication _auth = LocalAuthentication();
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Future<bool> isEnabled() async {
    final v = await _storage.read(key: _kBiometricEnabled);
    return v == 'true';
  }

  static Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      await _storage.write(key: _kBiometricEnabled, value: 'true');
    } else {
      await _storage.delete(key: _kBiometricEnabled);
    }
  }

  static Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    if (!(Platform.isAndroid || Platform.isIOS)) return false;
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      if (!canCheck && !supported) return false;
      final types = await _auth.getAvailableBiometrics();
      return types.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      debugPrint(
        'DEBUG: BiometricAuthService.authenticate: pre-check '
        'canCheckBiometrics=$canCheck isDeviceSupported=$supported',
      );
      if (!canCheck && !supported) {
        debugPrint(
          'DEBUG: BiometricAuthService.authenticate: skipping authenticate() — '
          'both canCheckBiometrics and isDeviceSupported are false',
        );
        return false;
      }
      final types = await _auth.getAvailableBiometrics();
      debugPrint(
        'DEBUG: BiometricAuthService.authenticate: getAvailableBiometrics=$types',
      );
      if (types.isEmpty) {
        debugPrint(
          'DEBUG: BiometricAuthService.authenticate: skipping authenticate() — '
          'no enrolled biometrics',
        );
        return false;
      }

      final ok = await _auth.authenticate(
        localizedReason: 'Please authenticate to access Bio-Cyber OS',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      return ok;
    } on PlatformException catch (e, st) {
      debugPrint(
        'DEBUG: BiometricAuthService.authenticate PlatformException: '
        'code=${e.code} message=${e.message} details=${e.details} stack=$st',
      );
      return false;
    } catch (e, st) {
      debugPrint('DEBUG: BiometricAuthService.authenticate failed: $e $st');
      return false;
    }
  }
}

