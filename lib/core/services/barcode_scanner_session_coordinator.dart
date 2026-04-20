import 'dart:async';

import 'package:mobile_scanner/mobile_scanner.dart';

/// Ensures only one [MobileScannerController] / camera pipeline is active.
///
/// Call [shutdownActiveSession] before pushing a new [BarcodeScannerScreen] so a
/// previous route’s native camera is stopped (e.g. Food → Supplements).
class BarcodeScannerSessionCoordinator {
  BarcodeScannerSessionCoordinator._();
  static final BarcodeScannerSessionCoordinator instance =
      BarcodeScannerSessionCoordinator._();

  MobileScannerController? _active;
  Future<void>? _pendingRelease;

  static Future<void> _stopAndDispose(MobileScannerController c) async {
    try {
      await c.stop();
    } catch (_) {}
    try {
      await c.dispose();
    } catch (_) {}
  }

  /// Awaits any in-flight release, then stops and disposes the tracked controller.
  Future<void> shutdownActiveSession() async {
    await _pendingRelease;
    _pendingRelease = null;
    final c = _active;
    _active = null;
    if (c != null) {
      await _stopAndDispose(c);
    }
  }

  /// Register the controller for the scanner route that is currently opening.
  void registerActive(MobileScannerController c) {
    _active = c;
  }

  /// Called from scanner [State.dispose]. Releases [c] if it is still the active one.
  void disposeIfActive(MobileScannerController c) {
    if (identical(_active, c)) {
      _active = null;
      _pendingRelease = _stopAndDispose(c);
    } else {
      unawaited(_stopAndDispose(c));
    }
  }
}
