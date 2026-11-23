import 'package:flutter/foundation.dart';
import 'package:waiting_room_app/models/client.dart';
import 'package:waiting_room_app/models/sync_status.dart';
import 'package:waiting_room_app/repositories/queue_repository.dart';
import 'package:waiting_room_app/storage/local_queue_storage.dart';

/// Rejoue les inscriptions locales (`pending` / `failed`) vers Supabase.
///
/// L'identifiant est généré sur le device : le RPC côté serveur fait un
/// `ON CONFLICT (id) DO UPDATE`, ce qui rend la synchronisation idempotente
/// et empêche les doublons.
class SyncService {
  SyncService(this._storage, this._repository);

  final LocalQueueStorage _storage;
  final QueueRepository _repository;

  bool _isSyncing = false;

  bool get isSyncing => _isSyncing;

  /// Retourne le nombre d'enregistrements synchronisés avec succès.
  Future<int> synchronize() async {
    if (_isSyncing) return 0;
    _isSyncing = true;

    var syncedCount = 0;

    try {
      final pendingRecords = await _storage.getPendingClients();

      for (final record in pendingRecords) {
        final id = record['id'] as String;

        try {
          await _storage.updateSyncStatus(id, SyncStatus.syncing);

          final client = Client.fromLocalMap(record);
          await _repository.registerOnServer(client);

          await _storage.updateSyncStatus(id, SyncStatus.synced);
          syncedCount++;
        } catch (error) {
          debugPrint('Synchronisation échouée pour $id : $error');
          await _storage.updateSyncStatus(id, SyncStatus.failed);
        }
      }
    } finally {
      _isSyncing = false;
    }

    return syncedCount;
  }
}
