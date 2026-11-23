import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waiting_room_app/models/sync_status.dart';
import 'package:waiting_room_app/widgets/client_card.dart';

import '../helpers/fakes.dart';

void main() {
  testWidgets('ClientCard shows location information', (tester) async {
    final client = makeClient(
      '1',
      name: 'Alice',
      lat: 36.8065,
      lng: 10.1815,
      syncStatus: SyncStatus.synced,
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ClientCard(client: client))),
    );

    expect(find.text('Alice'), findsOneWidget);
    expect(
      find.text('Location available (36.8065, 10.1815)'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.cloud_done), findsOneWidget);
  });

  testWidgets('ClientCard handles a missing location and a failed sync',
      (tester) async {
    final client = makeClient(
      '2',
      name: 'Bob',
      syncStatus: SyncStatus.failed,
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ClientCard(client: client))),
    );

    expect(find.text('Location not captured'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    expect(find.byIcon(Icons.delete), findsOneWidget);
  });

  testWidgets('ClientCard forwards the delete action', (tester) async {
    var deleted = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClientCard(
            client: makeClient('3', name: 'Charlie'),
            onDelete: () => deleted = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.delete));

    expect(deleted, isTrue);
  });
}
