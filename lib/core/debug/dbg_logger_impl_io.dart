import 'dart:convert';
import 'dart:io';

Future<void> dbgLogImpl(Map<String, dynamic> payload) async {
  try {
    final f = File('debug-824365.log');
    await f.writeAsString('${jsonEncode(payload)}\n',
        mode: FileMode.append, flush: true);
  } catch (_) {
    // ignore
  }
}

