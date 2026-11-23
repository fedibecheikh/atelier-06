import 'package:flutter_test/flutter_test.dart';
import 'package:waiting_room_app/models/client.dart';
import 'package:waiting_room_app/models/sync_status.dart';

void main() {
  group('Client Model Tests', () {
    test('client without location reports hasLocation as false', () {
      final client = Client(
        id: '1',
        name: 'Test Client',
        createdAt: DateTime(2026, 1, 1),
      );

      expect(client.hasLocation, isFalse);
      expect(client.locationText, 'Location not captured');
      expect(client.syncStatus, SyncStatus.synced);
    });

    test('client with location exposes formatted coordinates', () {
      final client = Client(
        id: '1',
        name: 'Test Client',
        lat: 36.8065,
        lng: 10.1815,
        locationAccuracy: 5.5,
        createdAt: DateTime(2026, 1, 1),
      );

      expect(client.hasLocation, isTrue);
      expect(client.locationText, '36.8065, 10.1815');
    });

    test('toLocalMap preserves accuracy and syncStatus', () {
      final client = Client(
        id: '1',
        name: 'Test Client',
        lat: 36.8065,
        lng: 10.1815,
        locationAccuracy: 5.5,
        createdAt: DateTime(2026, 1, 1),
        syncStatus: SyncStatus.pending,
      );

      final map = client.toLocalMap();

      expect(map['location_accuracy_m'], 5.5);
      expect(map['lat'], 36.8065);
      expect(map['sync_status'], 'pending');
    });

    test('toSupabaseMap excludes local sync_status', () {
      final client = Client(
        id: '1',
        name: 'Test Client',
        createdAt: DateTime(2026, 1, 1),
        syncStatus: SyncStatus.pending,
      );

      final map = client.toSupabaseMap();

      expect(map.containsKey('sync_status'), isFalse);
      expect(map.keys.toSet(), {
        'id',
        'name',
        'lat',
        'lng',
        'location_accuracy_m',
        'created_at',
      });
    });

    test('fromSupabaseMap always marks the client as synced', () {
      final map = Client(
        id: 'remote-1',
        name: 'Alice',
        lat: 48.8566,
        lng: 2.3522,
        locationAccuracy: 10,
        createdAt: DateTime.utc(2026, 2, 3, 4, 5),
      ).toSupabaseMap();

      final client = Client.fromSupabaseMap(map);

      expect(client.id, 'remote-1');
      expect(client.name, 'Alice');
      expect(client.locationAccuracy, 10);
      expect(client.syncStatus, SyncStatus.synced);
      expect(client.createdAt.toUtc(), DateTime.utc(2026, 2, 3, 4, 5));
    });

    test('fromLocalMap restores a failed synchronization status', () {
      final map = Client(
        id: 'local-1',
        name: 'Bob',
        createdAt: DateTime(2026, 2, 3),
        syncStatus: SyncStatus.failed,
      ).toLocalMap();

      final client = Client.fromLocalMap(map);

      expect(client.syncStatus, SyncStatus.failed);
    });

    test('fromLocalMap falls back to pending for an unknown status', () {
      final client = Client.fromLocalMap({
        'id': 'local-2',
        'name': 'Charlie',
        'created_at': '2026-01-01T00:00:00.000Z',
        'sync_status': 'unknown',
      });

      expect(client.syncStatus, SyncStatus.pending);
    });

    test('copyWith only changes the sync status', () {
      final client = Client(
        id: '1',
        name: 'Alice',
        lat: 1,
        lng: 2,
        createdAt: DateTime(2026, 1, 1),
        syncStatus: SyncStatus.pending,
      );

      final synced = client.copyWith(syncStatus: SyncStatus.synced);

      expect(synced.id, client.id);
      expect(synced.name, client.name);
      expect(synced.lat, client.lat);
      expect(synced.lng, client.lng);
      expect(synced.createdAt, client.createdAt);
      expect(synced.syncStatus, SyncStatus.synced);
      expect(client.syncStatus, SyncStatus.pending);
    });
  });
}
