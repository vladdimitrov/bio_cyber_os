import 'package:supabase_flutter/supabase_flutter.dart';

/// User-facing text for failed Supabase writes (RLS, validation, etc.).
String supabaseWriteErrorMessage(Object e) {
  if (e is PostgrestException) {
    final msg = e.message;
    final code = e.code;
    final buf = StringBuffer();
    if (msg.isNotEmpty) buf.write(msg);
    if (code != null && code.isNotEmpty) {
      if (buf.isNotEmpty) buf.write(' ');
      buf.write('($code)');
    }
    if (e.details != null && e.details.toString().isNotEmpty) {
      buf.write('\n${e.details}');
    }
    final s = buf.toString();
    final low = s.toLowerCase();
    if (low.contains('permission') ||
        low.contains('rls') ||
        low.contains('policy') ||
        code == '42501') {
      return 'Permission denied — $s';
    }
    return s.isEmpty ? e.toString() : s;
  }
  return e.toString();
}
