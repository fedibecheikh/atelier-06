import 'package:flutter_test/flutter_test.dart';
import 'package:waiting_room_app/models/sync_status.dart';
import 'package:waiting_room_app/services/sync_service.dart';

import '../helpers/fakes.dart';

void main() {
  group('SyncService', () {
    test('synchronizes pending and failed records', () async {
      final storage = FakeLocalQueueStorage()
        ..seed(makeClient(
          'pending-1',
          createdAt: DateTime(2026, 1, 2),
          syncStatus: SyncStatus.pending,
        ))
        ..seed(makeClient(
          'failed-1',
          createdAt: DateTime(2026, 1, 1),
          syncStatus: SyncStatus.failed,
        ))
        ..seed(makeClient('synced-1'));
      final repository = FakeQueueRepository();
      final service = SyncService(storage, repository);

      final count = await service.synchronize();

      expect(count, 2);
      expect(repository.registered.map((client) => client.id),
          ['failed-1', 'pending-1']);
      expect(storage.rowFor('pending-1')?['sync_status'], 'synced');
      expect(storage.rowFor('failed-1')?['sync_status'], 'synced');
      expect(storage.rowFor('synced-1')?['sync_status'], 'synced');
      expect(service.isSyncing, isFalse);
    });

    test('keeps a record failed when the server rejects it', () async {
      final storage = FakeLocalQueueStorage()
        ..seed(makeClient('ok-1', syncStatus: SyncStatus.pending))
        ..seed(makeClient('ko-1', syncStatus: SyncStatus.pending));
      final repository = FakeQueueRepository()..failRegistration = true;
      final service = SyncService(storage, repository);

      final count = await service.synchronize();

      expect(count, 0);
      expect(storage.rowFor('ok-1')?['sync_status'], 'failed');
      expect(storage.rowFor('ko-1')?['sync_status'], 'failed');
    });

    test('a failed sync can be retried later', () async {
      final storage = FakeLocalQueueStorage()
        ..seed(makeClient('retry-1', syncStatus: SyncStatus.failed));
      final repository = FakeQueueRepository();
      final service = SyncService(storage, repository);

      expect(await service.synchronize(), 1);
      expect(storage.rowFor('retry-1')?['sync_status'], 'synced');
    });

    test('does nothing when there is no pending record', () async {
      final storage = FakeLocalQueueStorage()..seed(makeClient('synced-1'));
      final repository = FakeQueueRepository();
      final service = SyncService(storage, repository);

      expect(await service.synchronize(), 0);
      expect(repository.registered, isEmpty);
    });
  });
}
