import 'dbg_logger_impl_stub.dart'
    if (dart.library.html) 'dbg_logger_impl_web.dart'
    if (dart.library.io) 'dbg_logger_impl_io.dart';

/// Minimal debug logger that works on web (HTTP ingest) and io (file append).
Future<void> dbgLog(Map<String, dynamic> payload) => dbgLogImpl(payload);

