import 'dart:async';

import 'package:waiting_room_app/models/client.dart';
import 'package:waiting_room_app/models/location_sample.dart';
import 'package:waiting_room_app/models/sync_status.dart';
import 'package:waiting_room_app/repositories/queue_repository.dart';
import 'package:waiting_room_app/services/connectivity_service.dart';
import 'package:waiting_room_app/services/geolocation_service.dart';
import 'package:waiting_room_app/storage/local_queue_storage.dart';

Client makeClient(
  String id, {
  String? name,
  DateTime? createdAt,
  double? lat,
  double? lng,
  double? accuracy,
  SyncStatus syncStatus = SyncStatus.synced,
}) {
  return Client(
    id: id,
    name: name ?? 'Client $id',
    lat: lat,
    lng: lng,
    locationAccuracy: accuracy,
    createdAt: createdAt ?? DateTime(2026, 1, 1),
    syncStatus: syncStatus,
  );
}

/// Stockage local en mémoire, sans SQLite, pour les tests de providers.
class FakeLocalQueueStorage implements LocalQueueStorage {
  final Map<String, Map<String, dynamic>> _rows = {};

  @override
  Future<void> saveClient(Map<String, dynamic> client) async {
    final id = client['id'] as String;
    _rows[id] = {...?_rows[id], ...client};
  }

  @override
  Future<List<Map<String, dynamic>>> getClients() async {
    final rows = _rows.values.map(Map<String, dynamic>.from).toList();
    rows.sort((a, b) {
      final byDate =
          (b['created_at'] as String).compareTo(a['created_at'] as String);
      return byDate != 0
          ? byDate
          : (b['id'] as String).compareTo(a['id'] as String);
    });
    return rows;
  }

  @override
  Future<List<Map<String, dynamic>>> getPendingClients() async {
    final rows = (await getClients()).where((row) {
      final status = row['sync_status'];
      return status == SyncStatus.pending.name ||
          status == SyncStatus.failed.name;
    }).toList();

    rows.sort(
      (a, b) => (a['created_at'] as String).compareTo(b['created_at'] as String),
    );
    return rows;
  }

  @override
  Future<void> updateSyncStatus(String id, SyncStatus status) async {
    final row = _rows[id];
    if (row != null) row['sync_status'] = status.name;
  }

  @override
  Future<void> deleteClient(String id) async {
    _rows.remove(id);
  }

  @override
  Future<void> close() async {}

  Map<String, dynamic>? rowFor(String id) => _rows[id];

  int get length => _rows.length;

  void seed(Client client) {
    _rows[client.id] = client.toLocalMap();
  }
}

/// Repository contrôlable : pagination, échecs réseau et flux Realtime.
class FakeQueueRepository implements QueueRepository {
  FakeQueueRepository([Iterable<Client> seed = const []]) {
    _clients.addAll(seed);
    _sort();
  }

  final List<Client> _clients = [];
  final List<Client> registered = [];
  final List<String> removed = [];
  final StreamController<Client> _inserts =
      StreamController<Client>.broadcast();

  bool failFetch = false;
  bool failRegistration = false;
  bool failRemove = false;
  int fetchCalls = 0;

  List<Client> get clients => List<Client>.unmodifiable(_clients);

  @override
  Future<List<Client>> fetchPage({
    required int offset,
    required int limit,
  }) async {
    fetchCalls++;
    if (failFetch) throw StateError('network unavailable');
    if (offset >= _clients.length) return const [];

    final end = (offset + limit).clamp(0, _clients.length);
    return _clients.sublist(offset, end);
  }

  @override
  Future<void> registerOnServer(Client client) async {
    if (failRegistration) throw StateError('registration failed');
    registered.add(client);

    final synced = client.copyWith(syncStatus: SyncStatus.synced);
    final index = _clients.indexWhere((existing) => existing.id == client.id);
    if (index == -1) {
      _clients.add(synced);
    } else {
      _clients[index] = synced;
    }
    _sort();
  }

  @override
  Future<void> removeClient(String id) async {
    if (failRemove) throw StateError('remove failed');
    removed.add(id);
    _clients.removeWhere((client) => client.id == id);
  }

  @override
  Stream<Client> watchInserts() => _inserts.stream;

  @override
  Future<void> close() async {
    await _inserts.close();
  }

  void emitRealtimeInsert(Client client) {
    _inserts.add(client.copyWith(syncStatus: SyncStatus.synced));
  }

  void _sort() {
    _clients.sort((a, b) {
      final byDate = b.createdAt.compareTo(a.createdAt);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });
  }
}

class FakeGeolocationService extends GeolocationService {
  FakeGeolocationService({this.sample});

  final LocationSample? sample;
  int calls = 0;

  @override
  Future<LocationSample?> getCurrentLocation() async {
    calls++;
    return sample;
  }
}

class FakeConnectivityService implements ConnectivityService {
  FakeConnectivityService({
    this.network = true,
    this.backendAvailable = true,
  });

  bool network;
  bool backendAvailable;

  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  @override
  Future<bool> hasNetwork() async => network;

  @override
  Stream<bool> get networkChanges => _changes.stream;

  @override
  Future<bool> isSupabaseAvailable() async => backendAvailable;

  void setNetwork(bool value) {
    network = value;
    _changes.add(value);
  }

  void setBackendAvailable(bool value) {
    backendAvailable = value;
  }

  Future<void> close() => _changes.close();
}
