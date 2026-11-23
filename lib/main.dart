import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:waiting_room_app/config/supabase_bootstrap.dart';
import 'package:waiting_room_app/providers/connectivity_provider.dart';
import 'package:waiting_room_app/providers/queue_provider.dart';
import 'package:waiting_room_app/repositories/queue_repository.dart';
import 'package:waiting_room_app/screens/queue_screen.dart';
import 'package:waiting_room_app/services/connectivity_service.dart';
import 'package:waiting_room_app/services/geolocation_service.dart';
import 'package:waiting_room_app/services/sync_service.dart';
import 'package:waiting_room_app/storage/local_queue_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final supabaseReady = await SupabaseBootstrap.initialize();
  final supabase = supabaseReady ? Supabase.instance.client : null;

  final storage = SqliteLocalQueueStorage();
  final QueueRepository repository =
      supabase != null ? SupabaseQueueRepository(supabase) : InMemoryQueueRepository();
  final ConnectivityService connectivityService = supabase != null
      ? DefaultConnectivityService(supabase)
      : const DemoConnectivityService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) {
            final provider = ConnectivityProvider(connectivityService);
            unawaited(provider.initialize());
            return provider;
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            final provider = QueueProvider(
              repository: repository,
              storage: storage,
              syncService: SyncService(storage, repository),
              geolocationService: GeolocationService(),
              isDemo: !supabaseReady,
            );
            unawaited(provider.initialize());
            return provider;
          },
        ),
      ],
      child: const WaitingRoomApp(),
    ),
  );
}

class WaitingRoomApp extends StatelessWidget {
  const WaitingRoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Resilient Waiting Room',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const QueueScreen(),
    );
  }
}
