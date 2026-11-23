import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:waiting_room_app/providers/connectivity_provider.dart';
import 'package:waiting_room_app/providers/queue_provider.dart';
import 'package:waiting_room_app/screens/queue_screen.dart';
import 'package:waiting_room_app/services/sync_service.dart';

import '../helpers/fakes.dart';

void main() {
  Widget buildApp({
    required QueueProvider queue,
    required ConnectivityProvider connectivity,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<QueueProvider>.value(value: queue),
        ChangeNotifierProvider<ConnectivityProvider>.value(value: connectivity),
      ],
      child: const MaterialApp(home: QueueScreen()),
    );
  }

  testWidgets('shows the empty state and registers a client', (tester) async {
    final storage = FakeLocalQueueStorage();
    final repository = FakeQueueRepository();
    final queue = QueueProvider(
      repository: repository,
      storage: storage,
      syncService: SyncService(storage, repository),
      geolocationService: FakeGeolocationService(),
    );
    final connectivityService = FakeConnectivityService();
    final connectivity = ConnectivityProvider(
      connectivityService,
      debounceDuration: Duration.zero,
    );

    addTearDown(() async {
      queue.dispose();
      connectivity.dispose();
      await connectivityService.close();
    });

    await queue.initialize();
    await connectivity.checkNow();

    await tester.pumpWidget(
      buildApp(queue: queue, connectivity: connectivity),
    );

    expect(find.text('The waiting queue is empty'), findsOneWidget);
    expect(find.text('Clients in Queue: 0'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('client-name-field')),
      'Alice',
    );
    await tester.tap(find.byKey(const Key('add-client-button')));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Clients in Queue: 1'), findsOneWidget);
    expect(repository.registered.single.name, 'Alice');
  });

  testWidgets('shows the offline banner when there is no network',
      (tester) async {
    final storage = FakeLocalQueueStorage();
    final repository = FakeQueueRepository();
    final queue = QueueProvider(
      repository: repository,
      storage: storage,
      syncService: SyncService(storage, repository),
      geolocationService: FakeGeolocationService(),
    );
    final connectivityService = FakeConnectivityService(network: false);
    final connectivity = ConnectivityProvider(
      connectivityService,
      debounceDuration: Duration.zero,
    );

    addTearDown(() async {
      queue.dispose();
      connectivity.dispose();
      await connectivityService.close();
    });

    await queue.initialize();
    await connectivity.initialize();

    await tester.pumpWidget(
      buildApp(queue: queue, connectivity: connectivity),
    );

    expect(find.text('No network connection'), findsOneWidget);
    expect(find.text('The waiting queue is empty'), findsOneWidget);
  });

  testWidgets('shows the demo banner in demo mode', (tester) async {
    final storage = FakeLocalQueueStorage();
    final repository = FakeQueueRepository();
    final queue = QueueProvider(
      repository: repository,
      storage: storage,
      syncService: SyncService(storage, repository),
      geolocationService: FakeGeolocationService(),
      isDemo: true,
    );
    final connectivityService = FakeConnectivityService();
    final connectivity = ConnectivityProvider(
      connectivityService,
      debounceDuration: Duration.zero,
    );

    addTearDown(() async {
      queue.dispose();
      connectivity.dispose();
      await connectivityService.close();
    });

    await queue.initialize();
    await connectivity.checkNow();

    await tester.pumpWidget(
      buildApp(queue: queue, connectivity: connectivity),
    );

    expect(
      find.text(
        'Demo mode: registrations are stored locally and synchronized in memory.',
      ),
      findsOneWidget,
    );
  });
}
