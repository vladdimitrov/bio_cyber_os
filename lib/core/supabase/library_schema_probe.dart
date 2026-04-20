import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Lightweight PostgREST checks for library `barcode` columns (debug builds).
///
/// PostgREST does not require a client-side “schema refresh”; after you run the
/// SQL migrations on Supabase, new columns are visible immediately. This probe
/// only helps catch a missing migration during development.
class LibrarySchemaProbe {
  LibrarySchemaProbe._();

  static Future<void> verifyBarcodeColumnsVisible(SupabaseClient client) async {
    if (!kDebugMode) return;
    try {
      await client.from('ingredients').select('barcode').limit(1);
      await client.from('supplements').select('barcode').limit(1);
      await client.from('medications').select('barcode').limit(1);
      debugPrint(
        'DEBUG: [SUPABASE] PostgREST sees library barcode columns on ingredients, supplements, medications.',
      );
    } catch (e) {
      debugPrint(
        'DEBUG: [SUPABASE] Barcode column probe failed — run '
        'supabase/migrations/20260420120000_add_barcode_columns_and_indexes.sql '
        'in the Supabase SQL editor (or `supabase db push`), then restart: $e',
      );
    }
  }
}
