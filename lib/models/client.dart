import 'sync_status.dart';

/// Client de la file d'attente.
///
/// `toSupabaseMap()` ne contient que les données métier ;
/// `toLocalMap()` ajoute `sync_status`, propre au device.
class Client {
  const Client({
    required this.id,
    required this.name,
    required this.createdAt,
    this.lat,
    this.lng,
    this.locationAccuracy,
    this.syncStatus = SyncStatus.synced,
  });

  final String id;
  final String name;
  final double? lat;
  final double? lng;
  final double? locationAccuracy;
  final DateTime createdAt;
  final SyncStatus syncStatus;

  bool get hasLocation => lat != null && lng != null;

  String get locationText {
    if (!hasLocation) return 'Location not captured';
    return '${lat!.toStringAsFixed(4)}, ${lng!.toStringAsFixed(4)}';
  }

  Map<String, dynamic> toSupabaseMap() {
    return {
      'id': id,
      'name': name,
      'lat': lat,
      'lng': lng,
      'location_accuracy_m': locationAccuracy,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> toLocalMap() {
    return {
      ...toSupabaseMap(),
      'sync_status': syncStatus.name,
    };
  }

  factory Client.fromSupabaseMap(Map<String, dynamic> map) {
    return Client(
      id: map['id'].toString(),
      name: map['name'] as String,
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
      locationAccuracy: (map['location_accuracy_m'] as num?)?.toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      syncStatus: SyncStatus.synced,
    );
  }

  factory Client.fromLocalMap(Map<String, dynamic> map) {
    return Client(
      id: map['id'] as String,
      name: map['name'] as String,
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
      locationAccuracy: (map['location_accuracy_m'] as num?)?.toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      syncStatus: SyncStatus.values.firstWhere(
        (status) => status.name == map['sync_status'],
        orElse: () => SyncStatus.pending,
      ),
    );
  }

  Client copyWith({SyncStatus? syncStatus}) {
    return Client(
      id: id,
      name: name,
      lat: lat,
      lng: lng,
      locationAccuracy: locationAccuracy,
      createdAt: createdAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  @override
  String toString() =>
      'Client(id: $id, name: $name, syncStatus: ${syncStatus.name})';
}
