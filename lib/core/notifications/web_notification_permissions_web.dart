// Web-only implementation (safe via conditional import).
import 'dart:html' as html;

Future<bool> requestWebNotificationPermission() async {
  if (!html.Notification.supported) return false;
  final status = await html.Notification.requestPermission();
  return status == 'granted';
}

