import 'package:geolocator/geolocator.dart';
import 'package:waiting_room_app/models/location_sample.dart';

/// Capture la position du device sans jamais bloquer l'inscription.
///
/// Toute erreur, un GPS désactivé ou une permission refusée renvoie `null` :
/// la géolocalisation reste optionnelle et informative.
class GeolocationService {
  Future<LocationSample?> getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );

      return LocationSample(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );
    } catch (_) {
      return null;
    }
  }
}
