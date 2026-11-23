import 'package:flutter_test/flutter_test.dart';
import 'package:waiting_room_app/models/sync_status.dart';
import 'package:waiting_room_app/repositories/queue_repository.dart';

import '../helpers/fakes.dart';

void main() {
  group('InMemoryQueueRepository', () {
    test('paginates clients from the most recent to the oldest', () async {
      final repository = InMemoryQueueRepository([
        for (var i = 0; i < 25; i++)
          makeClient(
            'client-$i',
            createdAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
          ),
      ]);
      addTearDown(repository.close);

      final firstPage =
          await repository.fetchPage(offset: 0, limit: 20);
      final secondPage =
          await repository.fetchPage(offset: 20, limit: 20);

      expect(firstPage.length, 20);
      expect(firstPage.first.id, 'client-24');
      expect(secondPage.length, 5);
      expect(secondPage.last.id, 'client-0');
      expect(await repository.fetchPage(offset: 40, limit: 20), isEmpty);
    });

    test('registerOnServer is idempotent on the client id', () async {
      final repository = InMemoryQueueRepository();
      addTearDown(repository.close);

      final client = makeClient('same-id', syncStatus: SyncStatus.pending);

      await repository.registerOnServer(client);
      await repository.registerOnServer(client);

      expect(repository.length, 1);
    });

    test('watchInserts emits new clients only', () async {
      final repository = InMemoryQueueRepository([
        makeClient('existing'),
      ]);
      addTearDown(repository.close);

      final received = <String>[];
      final subscription =
          repository.watchInserts().listen((client) => received.add(client.id));
      addTearDown(subscription.cancel);

      await repository.registerOnServer(makeClient('new-one'));
      await repository.registerOnServer(makeClient('new-one'));
      await Future<void>.delayed(Duration.zero);

      expect(received, ['new-one']);
    });

    test('removeClient deletes the client', () async {
      final repository = InMemoryQueueRepository([makeClient('to-remove')]);
      addTearDown(repository.close);

      await repository.removeClient('to-remove');

      expect(repository.length, 0);
      expect(await repository.fetchPage(offset: 0, limit: 20), isEmpty);
    });
  });
}
