import 'package:flutter/material.dart';
import 'package:waiting_room_app/models/app_connectivity.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.status});

  final AppConnectivity status;

  @override
  Widget build(BuildContext context) {
    if (status == AppConnectivity.online) {
      return const SizedBox.shrink();
    }

    final (message, color) = switch (status) {
      AppConnectivity.offline => ('No network connection', Colors.red),
      AppConnectivity.backendUnavailable => (
          'Waiting-room server unavailable',
          Colors.orange,
        ),
      AppConnectivity.checking => ('Checking connection...', Colors.blue),
      AppConnectivity.online => ('Connected', Colors.green),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      color: color,
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
