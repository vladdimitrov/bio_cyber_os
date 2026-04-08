import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Minimal NDJSON logger for Cursor Debug Mode.
///
/// Writes one JSON object per line to `debug-be15d7.log`.
///
/// NOTE: Some Flutter run modes have an unexpected working directory, so we try
/// multiple candidate locations and fall back to the workspace absolute path.
class AgentDebugLog {
  AgentDebugLog._();

  static const String sessionId = 'be15d7';
  static const String logPath = 'debug-be15d7.log';
  static const String _workspaceAbsoluteLogPath =
      r'c:\Users\wwwre\OneDrive\Documents\bio_cyber_os\debug-be15d7.log';

  static String? _resolvedPath;

  static Future<void> ensureInitialized() async {
    if (_resolvedPath != null) return;
    if (kIsWeb) {
      _resolvedPath = logPath;
      return;
    }
    try {
      final dir = await getApplicationSupportDirectory();
      _resolvedPath = '${dir.path}${Platform.pathSeparator}$logPath';
      return;
    } catch (_) {
      _resolvedPath = null;
    }
  }

  static List<String> _candidates() {
    final cwd = Directory.current.path;
    return <String>{
      logPath,
      '$cwd${Platform.pathSeparator}$logPath',
      _workspaceAbsoluteLogPath,
      ?_resolvedPath,
    }.toList();
  }

  static void log({
    required String runId,
    required String hypothesisId,
    required String location,
    required String message,
    Map<String, dynamic>? data,
  }) {
    try {
      final payload = <String, dynamic>{
        'sessionId': sessionId,
        'runId': runId,
        'hypothesisId': hypothesisId,
        'location': location,
        'message': message,
        'data': data ?? const <String, dynamic>{},
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      final line = '${jsonEncode(payload)}\n';
      for (final path in _candidates()) {
        try {
          if (kIsWeb) {
            // ignore: avoid_print
            print(line);
            return;
          }
          File(path).writeAsStringSync(
            line,
            mode: FileMode.append,
            flush: true,
          );
          return;
        } catch (_) {
          // try next candidate
        }
      }
    } catch (_) {
      // Never crash the app because of debug logging.
    }
  }
}

