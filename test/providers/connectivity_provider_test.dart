import 'package:flutter_test/flutter_test.dart';
import 'package:waiting_room_app/models/app_connectivity.dart';
import 'package:waiting_room_app/providers/connectivity_provider.dart';

import '../helpers/fakes.dart';

void main() {
  group('ConnectivityProvider', () {
    test('reports offline when the device has no network', () async {
      final service = FakeConnectivityService(network: false);
      final provider = ConnectivityProvider(
        service,
        debounceDuration: Duration.zero,
      );
      addTearDown(() async {
        provider.dispose();
        await service.close();
      });

      await provider.initialize();

      expect(provider.status, AppConnectivity.offline);
      expect(provider.isOnline, isFalse);
    });

    test('reports backendUnavailable when Supabase cannot be reached',
        () async {
      final service = FakeConnectivityService(backendAvailable: false);
      final provider = ConnectivityProvider(
        service,
        debounceDuration: Duration.zero,
      );
      addTearDown(() async {
        provider.dispose();
        await service.close();
      });

      await provider.initialize();
      await provider.checkNow();

      expect(provider.status, AppConnectivity.backendUnavailable);
    });

    test('becomes online when network and backend are available', () async {
      final service = FakeConnectivityService();
      final provider = ConnectivityProvider(
        service,
        debounceDuration: Duration.zero,
      );
      addTearDown(() async {
        provider.dispose();
        await service.close();
      });

      await provider.initialize();
      await provider.checkNow();

      expect(provider.status, AppConnectivity.online);
      expect(provider.isOnline, isTrue);
    });

    test('reacts to network changes', () async {
      final service = FakeConnectivityService();
      final provider = ConnectivityProvider(
        service,
        debounceDuration: Duration.zero,
      );
      addTearDown(() async {
        provider.dispose();
        await service.close();
      });

      await provider.initialize();
      await provider.checkNow();
      expect(provider.status, AppConnectivity.online);

      service.setNetwork(false);
      await Future<void>.delayed(Duration.zero);
      expect(provider.status, AppConnectivity.offline);

      service.setNetwork(true);
      await Future<void>.delayed(Duration.zero);
      await provider.checkNow();
      expect(provider.status, AppConnectivity.online);
    });

    test('notifies listeners only when the status really changes', () async {
      final service = FakeConnectivityService();
      final provider = ConnectivityProvider(
        service,
        debounceDuration: Duration.zero,
      );
      addTearDown(() async {
        provider.dispose();
        await service.close();
      });

      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.initialize();
      await provider.checkNow();
      await provider.checkNow();

      expect(notifications, 1);
    });
  });
}
