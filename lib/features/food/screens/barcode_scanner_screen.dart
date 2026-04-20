import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/services/barcode_scanner_session_coordinator.dart';
import '../../../core/services/open_food_facts_service.dart';
import '../../../core/theme/app_colors.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key, this.pickCodeOnly = false});

  /// When true, first valid scan pops with `{'barcode': code}` only (no Open Food Facts flow).
  final bool pickCodeOnly;

  /// Stops any previous session, then pushes a fresh scanner (new [State] + surface key).
  static Future<Map<String, dynamic>?> pushForResult(
    BuildContext context, {
    bool pickCodeOnly = false,
  }) async {
    await BarcodeScannerSessionCoordinator.instance.shutdownActiveSession();
    if (!context.mounted) return null;
    return Navigator.of(context).push<Map<String, dynamic>?>(
      MaterialPageRoute(
        builder: (_) => BarcodeScannerScreen(
          key: ValueKey(
            Object.hash(pickCodeOnly, DateTime.now().microsecondsSinceEpoch),
          ),
          pickCodeOnly: pickCodeOnly,
        ),
      ),
    );
  }

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen>
    with SingleTickerProviderStateMixin {
  late final MobileScannerController _scannerController;
  late final int _surfaceGeneration;

  bool _busy = false;
  String? _status;

  late final AnimationController _scanLineCtrl;

  bool _isBufferQueueIssue(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('bufferqueue') || s.contains('abandon');
  }

  Future<void> _recoverFromBufferIssue() async {
    debugPrint(
      'DEBUG: [SCANNER] Attempting camera reset due to BufferQueue abandonment.',
    );
    if (!mounted) return;
    try {
      await _scannerController.stop();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 160));
    if (!mounted) return;
    try {
      await _scannerController.start();
    } catch (e) {
      debugPrint('DEBUG: [SCANNER] Camera restart after BufferQueue failed: $e');
    }
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _surfaceGeneration = DateTime.now().microsecondsSinceEpoch;
    _scannerController = MobileScannerController(
      facing: CameraFacing.back,
      detectionSpeed: DetectionSpeed.normal,
    );
    BarcodeScannerSessionCoordinator.instance.registerActive(_scannerController);

    _scanLineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scanLineCtrl.dispose();
    BarcodeScannerSessionCoordinator.instance.disposeIfActive(_scannerController);
    super.dispose();
  }

  Future<void> _handleCode(String raw) async {
    if (_busy) return;
    final code = raw.trim();
    if (code.isEmpty) return;

    if (widget.pickCodeOnly) {
      setState(() => _busy = true);
      try {
        await _scannerController.stop();
      } catch (e) {
        if (_isBufferQueueIssue(e)) {
          await _recoverFromBufferIssue();
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(<String, dynamic>{'barcode': code});
      return;
    }

    setState(() {
      _busy = true;
      _status = 'Fetching product…';
    });

    try {
      await _scannerController.stop();
    } catch (e) {
      if (_isBufferQueueIssue(e)) {
        await _recoverFromBufferIssue();
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Camera error — try again.';
      });
      return;
    }

    try {
      final data = await OpenFoodFactsService.fetchByBarcode(code);
      if (!mounted) return;
      if (data == null) {
        setState(() {
          _busy = false;
          _status = 'Product not found. Please enter manually.';
        });
        try {
          await _scannerController.start();
        } catch (e) {
          if (_isBufferQueueIssue(e)) {
            await _recoverFromBufferIssue();
          }
        }
        return;
      }

      final name = (data['name'] ?? '').toString().trim();
      if (!mounted) return;
      final add = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          const bg = Color(0xFF050510);
          const cyan = Color(0xFF00F3FF);
          const gold = AppColors.cyberGold;
          return AlertDialog(
            backgroundColor: bg,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            title: Text(
              'ADD TO LIBRARY?',
              style: TextStyle(color: gold, fontFamily: 'monospace'),
            ),
            content: Text(
              name.isEmpty
                  ? 'A product was found for this barcode. Add it to your library?'
                  : 'Found: $name\n\nAdd to your library?',
              style: const TextStyle(
                color: cyan,
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.35,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text(
                  'CANCEL',
                  style: TextStyle(
                    color: Color(0xFF88CCFF),
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text(
                  'ADD',
                  style: TextStyle(
                    color: gold,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          );
        },
      );
      if (add != true) {
        setState(() {
          _busy = false;
          _status = null;
        });
        try {
          await _scannerController.start();
        } catch (e) {
          if (_isBufferQueueIssue(e)) {
            await _recoverFromBufferIssue();
          }
        }
        return;
      }

      if (!mounted) return;
      Navigator.of(context).pop(<String, dynamic>{
        'barcode': code,
        ...data,
      });
    } catch (e) {
      if (_isBufferQueueIssue(e)) {
        debugPrint(
          'DEBUG: [SCANNER] Attempting camera reset due to BufferQueue abandonment.',
        );
        if (mounted) {
          setState(() {
            _busy = false;
            _status = null;
          });
        }
        await _recoverFromBufferIssue();
        return;
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Lookup failed: $e';
      });
      try {
        await _scannerController.start();
      } catch (e2) {
        if (_isBufferQueueIssue(e2)) {
          await _recoverFromBufferIssue();
        }
      }
    }
  }

  Future<void> _onDetectSafe(BarcodeCapture capture) async {
    if (_busy) return;
    try {
      final barcodes = capture.barcodes;
      if (barcodes.isEmpty) return;
      final raw = barcodes.first.rawValue ?? '';
      await _handleCode(raw);
    } catch (e, _) {
      if (_isBufferQueueIssue(e)) {
        await _recoverFromBufferIssue();
      }
    }
  }

  void _onDetectError(Object error, StackTrace stackTrace) {
    if (_isBufferQueueIssue(error)) {
      unawaited(_recoverFromBufferIssue());
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    const gold = AppColors.cyberGold;
    const ruby = Color(0xFFE91E63);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(
          widget.pickCodeOnly ? 'SCAN TO FILTER' : 'SCAN BARCODE',
          style: const TextStyle(fontFamily: 'monospace', letterSpacing: 1.1),
        ),
        actions: [
          IconButton(
            tooltip: 'Torch',
            onPressed: _busy ? null : () => _scannerController.toggleTorch(),
            icon: const Icon(Icons.flash_on),
            color: gold,
          ),
          IconButton(
            tooltip: 'Flip',
            onPressed: _busy ? null : () => _scannerController.switchCamera(),
            icon: const Icon(Icons.cameraswitch),
            color: cyan,
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            key: ValueKey(_surfaceGeneration),
            controller: _scannerController,
            onDetect: (capture) => unawaited(_onDetectSafe(capture)),
            onDetectError: _onDetectError,
          ),
          // Frame + scanning line
          Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                margin: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  border: Border.all(color: cyan, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x3300F3FF),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: AnimatedBuilder(
                  animation: _scanLineCtrl,
                  builder: (context, _) {
                    final t = _scanLineCtrl.value;
                    return Stack(
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          top: (t * 0.92) * (MediaQuery.of(context).size.width * 0.7),
                          child: Container(
                            height: 2,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color(0x0000F3FF),
                                  Color(0xFF00F3FF),
                                  Color(0x00FFD700),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x5500F3FF),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          // Bottom status
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Color(0xAA050510),
                border: Border(top: BorderSide(color: cyan, width: 2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _busy ? Icons.downloading : Icons.qr_code_2,
                    color: _busy ? gold : cyan,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _status ??
                          (widget.pickCodeOnly
                              ? 'Scan a barcode to filter your ingredients list.'
                              : 'Point the camera at a barcode.\nWe will auto-fill macros per 100g.'),
                      style: TextStyle(
                        color: (_status?.contains('not found') ?? false)
                            ? ruby
                            : cyan,
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_busy)
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Color(0x66050510)),
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
