import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Distingue deux notions différentes :
/// - le réseau du device (Wi-Fi / cellulaire) ;
/// - la disponibilité réelle du backend Supabase.
abstract class ConnectivityService {
  Future<bool> hasNetwork();

  /// Émet `true` quand un réseau est disponible, `false` sinon.
  Stream<bool> get networkChanges;

  Future<bool> isSupabaseAvailable();
}

/// Implémentation réelle basée sur `connectivity_plus` et Supabase.
class DefaultConnectivityService implements ConnectivityService {
  DefaultConnectivityService(
    this._supabase, {
    Connectivity? connectivity,
  }) : _connectivity = connectivity ?? Connectivity();

  final SupabaseClient _supabase;
  final Connectivity _connectivity;

  @override
  Future<bool> hasNetwork() async {
    final results = await _connectivity.checkConnectivity();
    return results.any((result) => result != ConnectivityResult.none);
  }

  @override
  Stream<bool> get networkChanges {
    return _connectivity.onConnectivityChanged.map(
      (results) => results.any((result) => result != ConnectivityResult.none),
    );
  }

  @override
  Future<bool> isSupabaseAvailable() async {
    try {
      await _supabase
          .from('clients')
          .select('id')
          .limit(1)
          .timeout(const Duration(seconds: 5));
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Mode démo : pas de Supabase, mais le repository local répond toujours.
class DemoConnectivityService implements ConnectivityService {
  const DemoConnectivityService();

  @override
  Future<bool> hasNetwork() async => true;

  @override
  Stream<bool> get networkChanges => const Stream<bool>.empty();

  @override
  Future<bool> isSupabaseAvailable() async => true;
}
