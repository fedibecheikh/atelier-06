import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:waiting_room_app/models/client.dart';
import 'package:waiting_room_app/models/queue_state.dart';
import 'package:waiting_room_app/models/sync_status.dart';
import 'package:waiting_room_app/repositories/queue_repository.dart';
import 'package:waiting_room_app/services/geolocation_service.dart';
import 'package:waiting_room_app/services/sync_service.dart';
import 'package:waiting_room_app/storage/local_queue_storage.dart';

/// Orchestre la file d'attente :
/// - affichage immédiat depuis SQLite (offline-first) ;
/// - pagination de la source distante ;
/// - synchronisation des inscriptions locales ;
/// - fusion des insertions Realtime sans doublon.
class QueueProvider extends ChangeNotifier {
  QueueProvider({
    required QueueRepository repository,
    required LocalQueueStorage storage,
    required SyncService syncService,
    required GeolocationService geolocationService,
    this.pageSize = 20,
    this.isDemo = false,
  })  : _repository = repository,
        _storage = storage,
        _syncService = syncService,
        _geolocationService = geolocationService;

  final QueueRepository _repository;
  final LocalQueueStorage _storage;
  final SyncService _syncService;
  final GeolocationService _geolocationService;

  final int pageSize;
  final bool isDemo;

  final List<Client> _clients = [];
  QueueState _state = QueueState.initial;
  String? _errorMessage;

  int _page = 0;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool _isSyncing = false;
  bool _disposed = false;

  StreamSubscription<Client>? _realtimeSubscription;

  List<Client> get clients => List<Client>.unmodifiable(_clients);

  QueueState get state => _state;

  bool get hasMore => _hasMore;

  bool get isLoadingMore => _isLoadingMore;

  bool get isSyncing => _isSyncing;

  String? get errorMessage => _errorMessage;

  int get page => _page;

  Future<void> initialize() async {
    await _loadLocalQueue();

    // En mode démo, la source de vérité est la base locale : le repository
    // mémoire repart vide à chaque lancement.
    if (!isDemo) {
      await fetchInitialQueue();
    }

    await syncPending();
    _subscribeToRealtime();
  }

  Future<void> fetchInitialQueue() async {
    final hadClients = _clients.isNotEmpty;
    _state = hadClients ? QueueState.refreshing : QueueState.loading;
    _errorMessage = null;
    _notify();

    try {
      final data = await _repository.fetchPage(offset: 0, limit: pageSize);
      final localById = await _localClientsById();
      final remoteIds = data.map((client) => client.id).toSet();

      final localOnlyPending = localById.values.where(
        (client) =>
            !remoteIds.contains(client.id) &&
            client.syncStatus != SyncStatus.synced,
      );

      _clients
        ..clear()
        ..addAll(data)
        ..addAll(localOnlyPending);
      _sortClients();

      _page = 0;
      _hasMore = data.length >= pageSize;
      _state = _clients.isEmpty ? QueueState.empty : QueueState.loaded;
    } catch (error) {
      debugPrint('Chargement de la file impossible : $error');
      _errorMessage = 'Failed to load queue';
      // Offline-first : on conserve la file locale si elle existe.
      _state = _clients.isEmpty ? QueueState.error : QueueState.loaded;
    } finally {
      _notify();
    }
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    _isLoadingMore = true;
    _notify();

    final nextPage = _page + 1;

    try {
      final newClients = await _repository.fetchPage(
        offset: nextPage * pageSize,
        limit: pageSize,
      );

      final existingIds = _clients.map((client) => client.id).toSet();
      _clients.addAll(newClients.where((client) => existingIds.add(client.id)));

      _page = nextPage;
      if (newClients.length < pageSize) _hasMore = false;
    } catch (error) {
      debugPrint('Chargement de la page suivante impossible : $error');
      _errorMessage = 'Failed to load more clients';
    } finally {
      _isLoadingMore = false;
      _notify();
    }
  }

  /// Appelé par la souscription Realtime : ignore les identifiants déjà connus.
  void handleRealtimeInsert(Client client) {
    if (_disposed) return;

    final exists = _clients.any((existing) => existing.id == client.id);
    if (exists) return;

    _upsert(client);
    _sortClients();

    if (_state == QueueState.empty || _state == QueueState.initial) {
      _state = QueueState.loaded;
    }

    _notify();
  }

  /// Inscription offline-first : SQLite d'abord, Supabase ensuite.
  Future<void> addClient(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final location = await _geolocationService.getCurrentLocation();

    final client = Client(
      id: const Uuid().v4(),
      name: trimmed,
      lat: location?.latitude,
      lng: location?.longitude,
      locationAccuracy: location?.accuracy,
      createdAt: DateTime.now(),
      syncStatus: SyncStatus.pending,
    );

    await _storage.saveClient(client.toLocalMap());

    _upsert(client);
    _sortClients();
    _state = QueueState.loaded;
    _errorMessage = null;
    _notify();

    await syncPending();
  }

  Future<void> syncPending() async {
    if (_isSyncing) return;

    _isSyncing = true;
    _notify();

    try {
      await _syncService.synchronize();
      await _mergeLocalStatuses();
    } catch (error) {
      debugPrint('Synchronisation impossible : $error');
      _errorMessage = 'Synchronization failed';
    } finally {
      _isSyncing = false;
      _notify();
    }
  }

  Future<void> removeClient(String id) async {
    final index = _clients.indexWhere((client) => client.id == id);
    if (index == -1) return;

    _clients.removeAt(index);
    if (_clients.isEmpty) _state = QueueState.empty;
    _notify();

    await _storage.deleteClient(id);

    try {
      await _repository.removeClient(id);
    } catch (error) {
      debugPrint('Suppression distante impossible : $error');
      _errorMessage = 'Failed to remove client from the server';
      _notify();
    }
  }

  /// Rejoue les inscriptions en attente puis recharge la première page.
  Future<void> refresh() async {
    await syncPending();
    await fetchInitialQueue();
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    _notify();
  }

  Future<void> _loadLocalQueue() async {
    try {
      final rows = await _storage.getClients();
      for (final row in rows) {
        _upsert(Client.fromLocalMap(row));
      }
      _sortClients();

      if (_state == QueueState.initial) {
        _state = _clients.isEmpty ? QueueState.empty : QueueState.loaded;
      }
    } catch (error) {
      debugPrint('Lecture du stockage local impossible : $error');
      _errorMessage = 'Unable to read local storage';
      _state = QueueState.error;
    } finally {
      _notify();
    }
  }

  Future<void> _mergeLocalStatuses() async {
    final rows = await _storage.getClients();

    for (final row in rows) {
      final local = Client.fromLocalMap(row);
      final index = _clients.indexWhere((client) => client.id == local.id);

      if (index == -1) {
        // Un client purement local (pending/failed) doit rester visible.
        if (local.syncStatus != SyncStatus.synced) _clients.add(local);
      } else {
        _clients[index] =
            _clients[index].copyWith(syncStatus: local.syncStatus);
      }
    }
  }

  Future<Map<String, Client>> _localClientsById() async {
    final rows = await _storage.getClients();
    return {
      for (final row in rows)
        (row['id'] as String): Client.fromLocalMap(row),
    };
  }

  void _subscribeToRealtime() {
    _realtimeSubscription ??= _repository.watchInserts().listen(
      (client) {
        handleRealtimeInsert(client);
        final synced = client.copyWith(syncStatus: SyncStatus.synced);
        unawaited(_storage.saveClient(synced.toLocalMap()));
      },
      onError: (Object error) {
        debugPrint('Flux Realtime indisponible : $error');
        _errorMessage = 'Realtime unavailable';
        _notify();
      },
    );
  }

  void _upsert(Client client) {
    final index = _clients.indexWhere((existing) => existing.id == client.id);
    if (index == -1) {
      _clients.add(client);
    } else {
      _clients[index] = client;
    }
  }

  void _sortClients() {
    _clients.sort((a, b) {
      final byDate = b.createdAt.compareTo(a.createdAt);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _realtimeSubscription?.cancel();
    super.dispose();
  }
}
