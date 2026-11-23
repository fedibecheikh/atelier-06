import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waiting_room_app/widgets/loading_widget.dart';
import 'package:waiting_room_app/widgets/queue_empty_widget.dart';

void main() {
  testWidgets('LoadingWidget displays its message and a spinner',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LoadingWidget(message: 'Loading queue...')),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading queue...'), findsOneWidget);
  });

  testWidgets('QueueEmptyWidget explains the empty state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: QueueEmptyWidget())),
    );

    expect(find.text('The waiting queue is empty'), findsOneWidget);
    expect(find.text('New registrations will appear here.'), findsOneWidget);
    expect(find.byIcon(Icons.people_outline), findsOneWidget);
  });
}
