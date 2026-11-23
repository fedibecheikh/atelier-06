import 'package:flutter/material.dart';
import 'package:waiting_room_app/models/client.dart';
import 'package:waiting_room_app/models/sync_status.dart';

class ClientCard extends StatelessWidget {
  const ClientCard({super.key, required this.client, this.onDelete});

  final Client client;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(
            client.hasLocation ? Icons.location_on : Icons.person,
            color: client.hasLocation ? Colors.green : null,
          ),
        ),
        title: Text(client.name),
        subtitle: Text(
          client.hasLocation
              ? 'Location available (${client.locationText})'
              : 'Location not captured',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: _syncLabel(client.syncStatus),
              child: Icon(
                _syncIcon(client.syncStatus),
                color: _syncColor(client.syncStatus),
                size: 20,
              ),
            ),
            IconButton(
              tooltip: 'Remove ${client.name}',
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  static String _syncLabel(SyncStatus status) {
    return switch (status) {
      SyncStatus.pending => 'Waiting for synchronization',
      SyncStatus.syncing => 'Synchronizing...',
      SyncStatus.synced => 'Synchronized',
      SyncStatus.failed => 'Synchronization failed - will retry',
    };
  }

  static IconData _syncIcon(SyncStatus status) {
    return switch (status) {
      SyncStatus.pending => Icons.cloud_upload,
      SyncStatus.syncing => Icons.cloud_sync,
      SyncStatus.synced => Icons.cloud_done,
      SyncStatus.failed => Icons.cloud_off,
    };
  }

  static Color _syncColor(SyncStatus status) {
    return switch (status) {
      SyncStatus.pending => Colors.orange,
      SyncStatus.syncing => Colors.blue,
      SyncStatus.synced => Colors.green,
      SyncStatus.failed => Colors.red,
    };
  }
}
