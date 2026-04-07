// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

const _endpoint =
    'http://127.0.0.1:7443/ingest/c0af96f7-f01e-497e-910b-0b3053975100';

Future<void> dbgLogImpl(Map<String, dynamic> payload) async {
  try {
    await html.HttpRequest.request(
      _endpoint,
      method: 'POST',
      requestHeaders: const <String, String>{
        'Content-Type': 'application/json',
        'X-Debug-Session-Id': '824365',
      },
      sendData: jsonEncode(payload),
    );
  } catch (_) {
    // ignore
  }
}

