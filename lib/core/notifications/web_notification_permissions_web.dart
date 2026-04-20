// Web-only implementation (safe via conditional import).
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart';

Future<bool> requestWebNotificationPermission() async {
  if (!window.has('Notification')) return false;
  final status = (await Notification.requestPermission().toDart).toDart;
  return status == 'granted';
}
