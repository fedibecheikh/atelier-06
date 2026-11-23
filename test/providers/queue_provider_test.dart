import 'package:flutter_test/flutter_test.dart';
import 'package:waiting_room_app/models/location_sample.dart';
import 'package:waiting_room_app/models/queue_state.dart';
import 'package:waiting_room_app/models/sync_status.dart';
import 'package:waiting_room_app/providers/queue_provider.dart';
import 'package:waiting_room_app/services/sync_service.dart';

import '../helpers/fakes.dart';

QueueProvider buildQueueProvider({
  required FakeQueueRepository repository,
  required FakeLocalQueueStorage storage,
  FakeGeolocationService? geolocation,
}) {
  return QueueProvider(
    repository: repository,
    storage: storage,
    syncService: SyncService(storage, repository),
    geolocationService: geolocation ?? FakeGeolocationService(),
  );
}

void main() {
  group('QueueProvider pagination', () {
    test('loads the first page then the next pages without duplicates',
        () async {
      final repository = FakeQueueRepository([
        for (var i = 0; i < 25; i++)
          makeClient(
            'client-$i',
            createdAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
          ),
      ]);
      final provider = buildQueueProvider(
        repository: repository,
        storage: FakeLocalQueueStorage(),
      );
      addTearDown(provider.dispose);

      await provider.initialize();

      expect(provider.state, QueueState.loaded);
      expect(provider.clients.length, 20);
      expect(provider.hasMore, isTrue);
      expect(provider.page, 0);

      await provider.loadMore();

      expect(provider.clients.length, 25);
      expect(provider.clients.map((client) => client.id).toSet().length, 25);
      expect(provider.hasMore, isFalse);
      expect(provider.page, 1);
    });

    test('deduplicates a page item already received through Realtime',
        () async {
      final repository = FakeQueueRepository([
        for (var i = 0; i < 25; i++)
          makeClient(
            'client-$i',
            createdAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
          ),
      ]);
      final provider = buildQueueProvider(
        repository: repository,
        storage: FakeLocalQueueStorage(),
      );
      addTearDown(provider.dispose);

      await provider.initialize();
      provider.handleRealtimeInsert(makeClient('client-0'));
      expect(provider.clients.length, 21);

      await provider.loadMore();

      expect(provider.clients.length, 25);
      expect(provider.clients.where((c) => c.id == 'client-0').length, 1);
    });

    test('does not request more pages when everything is loaded', () async {
      final repository = FakeQueueRepository([makeClient('only-one')]);
      final provider = buildQueueProvider(
        repository: repository,
        storage: FakeLocalQueueStorage(),
      );
      addTearDown(provider.dispose);

      await provider.initialize();
      expect(provider.hasMore, isFalse);

      await provider.loadMore();

      expect(repository.fetchCalls, 1);
      expect(provider.clients.length, 1);
    });
  });

  group('QueueProvider offline-first', () {
    test('displays local clients when the remote queue is unreachable',
        () async {
      final storage = FakeLocalQueueStorage()
        ..seed(makeClient('local-1', name: 'Local Alice',
            syncStatus: SyncStatus.pending));
      final repository = FakeQueueRepository()
        ..failFetch = true
        ..failRegistration = true;
      final provider = buildQueueProvider(
        repository: repository,
        storage: storage,
      );
      addTearDown(provider.dispose);

      await provider.initialize();

      expect(provider.state, QueueState.loaded);
      expect(provider.clients.single.name, 'Local Alice');
      expect(provider.errorMessage, 'Failed to load queue');
      expect(provider.clients.single.syncStatus, SyncStatus.failed);
    });

    test('addClient persists locally before synchronizing', () async {
      final storage = FakeLocalQueueStorage();
      final repository = FakeQueueRepository();
      final geolocation = FakeGeolocationService(
        sample: const LocationSample(
          latitude: 36.8065,
          longitude: 10.1815,
          accuracy: 5.5,
        ),
      );
      final provider = buildQueueProvider(
        repository: repository,
        storage: storage,
        geolocation: geolocation,
      );
      addTearDown(provider.dispose);

      await provider.initialize();
      await provider.addClient('  Alice  ');

      expect(geolocation.calls, 1);
      expect(provider.clients.single.name, 'Alice');
      expect(provider.clients.single.lat, 36.8065);
      expect(provider.clients.single.lng, 10.1815);
      expect(provider.clients.single.locationAccuracy, 5.5);
      expect(provider.clients.single.syncStatus, SyncStatus.synced);
      expect(repository.registered.single.name, 'Alice');
      expect(storage.rowFor(provider.clients.single.id)?['sync_status'],
          'synced');
    });

    test('registration still works when geolocation is denied', () async {
      final repository = FakeQueueRepository();
      final provider = buildQueueProvider(
        repository: repository,
        storage: FakeLocalQueueStorage(),
        geolocation: FakeGeolocationService(),
      );
      addTearDown(provider.dispose);

      await provider.initialize();
      await provider.addClient('Bob');

      expect(provider.clients.single.name, 'Bob');
      expect(provider.clients.single.hasLocation, isFalse);
      expect(provider.clients.single.locationText, 'Location not captured');
      expect(provider.clients.single.syncStatus, SyncStatus.synced);
    });

    test('an offline registration stays visible as failed then retries',
        () async {
      final storage = FakeLocalQueueStorage();
      final repository = FakeQueueRepository()..failRegistration = true;
      final provider = buildQueueProvider(
        repository: repository,
        storage: storage,
      );
      addTearDown(provider.dispose);

      await provider.initialize();
      await provider.addClient('Offline Bob');

      final id = provider.clients.single.id;
      expect(provider.clients.single.syncStatus, SyncStatus.failed);
      expect(storage.rowFor(id)?['sync_status'], 'failed');

      repository.failRegistration = false;
      await provider.syncPending();

      expect(provider.clients.single.syncStatus, SyncStatus.synced);
      expect(storage.rowFor(id)?['sync_status'], 'synced');
      expect(repository.registered.single.id, id);
    });

    test('initialize synchronizes records left pending by a previous run',
        () async {
      final storage = FakeLocalQueueStorage()
        ..seed(makeClient('leftover-1', syncStatus: SyncStatus.pending));
      final repository = FakeQueueRepository();
      final provider = buildQueueProvider(
        repository: repository,
        storage: storage,
      );
      addTearDown(provider.dispose);

      await provider.initialize();

      expect(provider.clients.single.id, 'leftover-1');
      expect(provider.clients.single.syncStatus, SyncStatus.synced);
      expect(repository.registered.single.id, 'leftover-1');
    });

    test('ignores an empty client name', () async {
      final geolocation = FakeGeolocationService();
      final provider = buildQueueProvider(
        repository: FakeQueueRepository(),
        storage: FakeLocalQueueStorage(),
        geolocation: geolocation,
      );
      addTearDown(provider.dispose);

      await provider.initialize();
      await provider.addClient('   ');

      expect(provider.clients, isEmpty);
      expect(geolocation.calls, 0);
    });
  });

  group('QueueProvider realtime', () {
    test('inserts a new client once and switches empty to loaded', () async {
      final provider = buildQueueProvider(
        repository: FakeQueueRepository(),
        storage: FakeLocalQueueStorage(),
      );
      addTearDown(provider.dispose);

      await provider.initialize();
      expect(provider.state, QueueState.empty);

      provider.handleRealtimeInsert(makeClient('rt-1', name: 'Realtime'));

      expect(provider.state, QueueState.loaded);
      expect(provider.clients.single.name, 'Realtime');

      provider.handleRealtimeInsert(makeClient('rt-1', name: 'Realtime'));

      expect(provider.clients.length, 1);
    });

    test('receives inserts from the repository stream', () async {
      final repository = FakeQueueRepository();
      final provider = buildQueueProvider(
        repository: repository,
        storage: FakeLocalQueueStorage(),
      );
      addTearDown(provider.dispose);

      await provider.initialize();
      repository.emitRealtimeInsert(makeClient('rt-2', name: 'Streamed'));
      await Future<void>.delayed(Duration.zero);

      expect(provider.clients.single.name, 'Streamed');
    });
  });

  group('QueueProvider removal', () {
    test('removes a client from memory, SQLite and Supabase', () async {
      final storage = FakeLocalQueueStorage()..seed(makeClient('remove-1'));
      final repository = FakeQueueRepository([makeClient('remove-1')]);
      final provider = buildQueueProvider(
        repository: repository,
        storage: storage,
      );
      addTearDown(provider.dispose);

      await provider.initialize();
      await provider.removeClient('remove-1');

      expect(provider.clients, isEmpty);
      expect(provider.state, QueueState.empty);
      expect(storage.rowFor('remove-1'), isNull);
      expect(repository.removed, ['remove-1']);
    });

    test('keeps the UI consistent when remote removal fails', () async {
      final storage = FakeLocalQueueStorage()..seed(makeClient('remove-2'));
      final repository = FakeQueueRepository([makeClient('remove-2')])
        ..failRemove = true;
      final provider = buildQueueProvider(
        repository: repository,
        storage: storage,
      );
      addTearDown(provider.dispose);

      await provider.initialize();
      await provider.removeClient('remove-2');

      expect(provider.clients, isEmpty);
      expect(storage.rowFor('remove-2'), isNull);
      expect(provider.errorMessage, 'Failed to remove client from the server');
    });
  });
}
