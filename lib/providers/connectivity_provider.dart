import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:waiting_room_app/models/app_connectivity.dart';
import 'package:waiting_room_app/services/connectivity_service.dart';

/// Expose l'état réseau + backend à l'UI.
///
/// Un debounce évite de marteler Supabase quand le réseau oscille
/// (Wi-Fi instable, bascule 4G, etc.).
class ConnectivityProvider extends ChangeNotifier {
  ConnectivityProvider(
    this._service, {
    this.debounceDuration = const Duration(milliseconds: 700),
  });

  final ConnectivityService _service;
  final Duration debounceDuration;

  StreamSubscription<bool>? _subscription;
  Timer? _debounceTimer;

  AppConnectivity _status = AppConnectivity.checking;
  bool _checkingBackend = false;
  bool _checkAgain = false;
  bool _disposed = false;

  AppConnectivity get status => _status;

  bool get isOnline => _status == AppConnectivity.online;

  bool get isOffline => _status == AppConnectivity.offline;

  Future<void> initialize() async {
    _subscription?.cancel();
    _subscription = _service.networkChanges.listen(
      _handleNetworkChange,
      onError: (Object _) => _setStatus(AppConnectivity.checking),
    );

    final connected = await _service.hasNetwork();
    if (_disposed) return;
    _handleNetworkChange(connected);
  }

  /// Vérifie immédiatement le backend, sans attendre le debounce.
  Future<void> checkNow() async {
    _debounceTimer?.cancel();
    await _checkBackend();
  }

  void _handleNetworkChange(bool connected) {
    _debounceTimer?.cancel();

    if (!connected) {
      _setStatus(AppConnectivity.offline);
      return;
    }

    _debounceTimer = Timer(debounceDuration, _checkBackend);
  }

  Future<void> _checkBackend() async {
    if (_disposed) return;

    if (_checkingBackend) {
      _checkAgain = true;
      return;
    }

    _checkingBackend = true;

    try {
      do {
        _checkAgain = false;
        final available = await _service.isSupabaseAvailable();
        if (_disposed) return;

        _setStatus(
          available
              ? AppConnectivity.online
              : AppConnectivity.backendUnavailable,
        );
      } while (_checkAgain && !_disposed);
    } finally {
      _checkingBackend = false;
    }
  }

  void _setStatus(AppConnectivity newStatus) {
    if (_disposed || _status == newStatus) return;
    _status = newStatus;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
