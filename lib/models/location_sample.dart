/// Position simplifiée, indépendante de `geolocator` pour les tests.
class LocationSample {
  const LocationSample({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
}
