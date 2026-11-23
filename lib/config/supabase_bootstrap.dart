import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';

class SupabaseBootstrap {
  const SupabaseBootstrap._();

  static bool _initialized = false;

  static bool get isInitialized => _initialized;

  static Future<bool> initialize({String? url, String? anonKey}) async {
    if (_initialized) return true;

    final resolvedUrl = url ?? Env.supabaseUrl;
    final resolvedKey = anonKey ?? Env.supabaseAnonKey;

    if (resolvedUrl.isEmpty || resolvedKey.isEmpty) {
      debugPrint(
        'Supabase non configuré : lancement en mode démo local. '
        'Utilisez --dart-define=SUPABASE_URL=... et '
        '--dart-define=SUPABASE_ANON_KEY=...',
      );
      return false;
    }

    try {
      await Supabase.initialize(url: resolvedUrl, publishableKey: resolvedKey);
      _initialized = true;
      return true;
    } catch (error, stackTrace) {
      debugPrint('Échec de l\'initialisation Supabase : $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }
}
