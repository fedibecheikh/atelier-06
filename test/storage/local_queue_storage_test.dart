import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:waiting_room_app/models/sync_status.dart';
import 'package:waiting_room_app/storage/local_queue_storage.dart';

import '../helpers/fakes.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SqliteLocalQueueStorage', () {
    test('saves and reads clients from the most recent to the oldest',
        () async {
      final storage = SqliteLocalQueueStorage(inMemory: true);
      addTearDown(storage.close);

      await storage.saveClient(
        makeClient('old', createdAt: DateTime(2026, 1, 1)).toLocalMap(),
      );
      await storage.saveClient(
        makeClient('new', createdAt: DateTime(2026, 1, 2)).toLocalMap(),
      );

      final rows = await storage.getClients();

      expect(rows.map((row) => row['id']), ['new', 'old']);
      expect(rows.first['sync_status'], 'synced');
      expect(rows.first['location_accuracy_m'], isNull);
    });

    test('returns pending and failed records, oldest first', () async {
      final storage = SqliteLocalQueueStorage(inMemory: true);
      addTearDown(storage.close);

      await storage.saveClient(makeClient('synced-1').toLocalMap());
      await storage.saveClient(
        makeClient(
          'failed-1',
          createdAt: DateTime(2026, 1, 1),
          syncStatus: SyncStatus.failed,
        ).toLocalMap(),
      );
      await storage.saveClient(
        makeClient(
          'pending-1',
          createdAt: DateTime(2026, 1, 2),
          syncStatus: SyncStatus.pending,
        ).toLocalMap(),
      );

      final rows = await storage.getPendingClients();

      expect(rows.map((row) => row['id']), ['failed-1', 'pending-1']);
    });

    test('updates the sync status without touching business data', () async {
      final storage = SqliteLocalQueueStorage(inMemory: true);
      addTearDown(storage.close);

      await storage.saveClient(
        makeClient(
          'client-1',
          name: 'Alice',
          lat: 36.8065,
          lng: 10.1815,
          accuracy: 4.2,
          syncStatus: SyncStatus.pending,
        ).toLocalMap(),
      );

      await storage.updateSyncStatus('client-1', SyncStatus.synced);

      final row = (await storage.getClients()).single;
      expect(row['sync_status'], 'synced');
      expect(row['name'], 'Alice');
      expect(row['lat'], 36.8065);
      expect(row['lng'], 10.1815);
      expect(row['location_accuracy_m'], 4.2);
    });

    test('replaces a row with the same id and deletes rows', () async {
      final storage = SqliteLocalQueueStorage(inMemory: true);
      addTearDown(storage.close);

      await storage.saveClient(
        makeClient('client-1', name: 'Alice').toLocalMap(),
      );
      await storage.saveClient(
        makeClient('client-1', name: 'Alice Updated').toLocalMap(),
      );

      expect((await storage.getClients()).length, 1);
      expect((await storage.getClients()).single['name'], 'Alice Updated');

      await storage.deleteClient('client-1');
      expect(await storage.getClients(), isEmpty);
    });
  });
}
