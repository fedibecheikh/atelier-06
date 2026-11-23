import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:waiting_room_app/models/client.dart';
import 'package:waiting_room_app/models/sync_status.dart';

/// Accès aux données distantes de la file d'attente.
///
/// L'abstraction permet de tester les providers sans réseau et de faire
/// tourner l'application en mode démo sans Supabase.
abstract class QueueRepository {
  /// Une page de clients, du plus récent au plus ancien.
  Future<List<Client>> fetchPage({required int offset, required int limit});

  /// Enregistrement idempotent : le même `id` ne crée jamais de doublon.
  Future<void> registerOnServer(Client client);

  Future<void> removeClient(String id);

  /// Émet uniquement les nouveaux clients (Realtime), jamais les mises à jour.
  Stream<Client> watchInserts();

  Future<void> close();
}

class SupabaseQueueRepository implements QueueRepository {
  SupabaseQueueRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Client>> fetchPage({
    required int offset,
    required int limit,
  }) async {
    final rows = await _client
        .from('clients')
        .select()
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .range(offset, offset + limit - 1);

    return rows.map(Client.fromSupabaseMap).toList(growable: false);
  }

  @override
  Future<void> registerOnServer(Client client) async {
    try {
      await _client.rpc('register_queue_client', params: {
        'p_id': client.id,
        'p_name': client.name,
        'p_lat': client.lat,
        'p_lng': client.lng,
        'p_accuracy': client.locationAccuracy,
        'p_created_at': client.createdAt.toUtc().toIso8601String(),
      });
    } on PostgrestException catch (error) {
      // La fonction SQL n'est pas encore déployée : on retombe sur un upsert
      // idempotent pour que l'atelier reste utilisable.
      if (error.code == 'PGRST202' ||
          error.message.contains('register_queue_client')) {
        await _client.from('clients').upsert(
              client.toSupabaseMap(),
              onConflict: 'id',
            );
        return;
      }
      rethrow;
    }
  }

  @override
  Future<void> removeClient(String id) async {
    await _client.from('clients').delete().eq('id', id);
  }

  @override
  Stream<Client> watchInserts() {
    final seenIds = <String>{};

    return _client
        .from('clients')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .expand((rows) {
      final inserts = <Client>[];
      for (final row in rows) {
        final client = Client.fromSupabaseMap(row);
        if (seenIds.add(client.id)) inserts.add(client);
      }
      return inserts;
    });
  }

  @override
  Future<void> close() async {}
}

/// Mode démo : file en mémoire, aucun réseau requis.
class InMemoryQueueRepository implements QueueRepository {
  InMemoryQueueRepository([Iterable<Client> seed = const []]) {
    _clients.addAll(seed);
    _sort();
  }

  final List<Client> _clients = [];
  final StreamController<Client> _inserts =
      StreamController<Client>.broadcast();

  @override
  Future<List<Client>> fetchPage({
    required int offset,
    required int limit,
  }) async {
    if (offset >= _clients.length) return const [];
    final end = (offset + limit).clamp(0, _clients.length);
    return List<Client>.unmodifiable(_clients.sublist(offset, end));
  }

  @override
  Future<void> registerOnServer(Client client) async {
    final synced = client.copyWith(syncStatus: SyncStatus.synced);
    final index = _clients.indexWhere((existing) => existing.id == client.id);
    if (index == -1) {
      _clients.add(synced);
      _sort();
      if (!_inserts.isClosed) _inserts.add(synced);
    } else {
      _clients[index] = synced;
    }
  }

  @override
  Future<void> removeClient(String id) async {
    _clients.removeWhere((client) => client.id == id);
  }

  @override
  Stream<Client> watchInserts() => _inserts.stream;

  @override
  Future<void> close() async {
    await _inserts.close();
  }

  /// Ajoute un client comme le ferait un autre appareil (utile aux tests).
  Future<void> emitForTest(Client client) async {
    final synced = client.copyWith(syncStatus: SyncStatus.synced);
    _clients.add(synced);
    _sort();
    if (!_inserts.isClosed) _inserts.add(synced);
  }

  void _sort() {
    _clients.sort((a, b) {
      final byDate = b.createdAt.compareTo(a.createdAt);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });
  }

  int get length => _clients.length;
}
