# Atelier 6 — File d'attente résiliente : offline, pagination et Realtime

## Réalisation

L'application reprend la waiting room des ateliers précédents et la structure en
couches, avec un vrai moteur de synchronisation.

```text
lib/
├── main.dart
├── config/          # --dart-define + initialisation Supabase
├── models/          # Client, SyncStatus, AppConnectivity, QueueState
├── providers/       # QueueProvider, ConnectivityProvider
├── services/        # GeolocationService, ConnectivityService, SyncService
├── repositories/    # QueueRepository (Supabase + mémoire)
├── storage/         # LocalQueueStorage (SQLite)
├── screens/         # QueueScreen
└── widgets/         # ClientCard, OfflineBanner, LoadingWidget, QueueEmptyWidget
```

### Cycle d'une inscription

1. La position est capturée par `GeolocationService` (ou `null` si refus/timeout).
2. Le client est créé avec un `id` UUID **généré sur le device** et le statut
   `SyncStatus.pending`.
3. Il est écrit immédiatement dans SQLite (`LocalQueueStorage`) et affiché.
4. `SyncService` rejoue les enregistrements `pending` / `failed` un par un :
   `syncing` → RPC Supabase → `synced`, ou `failed` en cas d'échec.
5. Le RPC `register_queue_client` fait un `ON CONFLICT (id) DO UPDATE` :
   la synchronisation est idempotente, donc sans doublon.

### Pagination et Realtime

- `QueueRepository.fetchPage(offset, limit)` charge 20 clients par page
  (`created_at DESC`).
- `loadMore()` ajoute la page suivante en filtrant les identifiants déjà connus.
- `watchInserts()` n'émet que les **nouveaux** ids (déduplication locale).
- `handleRealtimeInsert()` ignore un client déjà présent et bascule l'état
  `empty` vers `loaded`.

### Connectivité

`ConnectivityProvider` distingue :

| État | Signification |
| --- | --- |
| `checking` | vérification initiale |
| `online` | réseau + Supabase joignables |
| `offline` | aucun réseau (Wi-Fi / cellulaire) |
| `backendUnavailable` | réseau présent mais Supabase injoignable |

Un debounce de 700 ms évite de marteler le backend quand le réseau oscille.
Chaque retour à `online` déclenche `QueueProvider.syncPending()`.

### États d'interface

`QueueState` pilote : `initial`, `loading`, `loaded`, `empty`, `refreshing`,
`loadingMore`, `error`. L'UI affiche `LoadingWidget`, `QueueEmptyWidget`,
`OfflineBanner`, une bannière d'erreur avec **Retry**, un bouton « Load more »
et le statut de synchronisation de chaque carte.

## Permissions

Android — `android/app/src/main/AndroidManifest.xml` :

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

iOS — `ios/Runner/Info.plist` :

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Cette application utilise votre position pour indiquer où vous avez rejoint la file d'attente.</string>
```

`connectivity_plus` ne demande pas de permission supplémentaire sur Android.
Redémarrer complètement l'application après modification du manifeste.

## Base de données

Exécuter [`supabase/schema.sql`](./supabase/schema.sql) dans le SQL Editor :

- table `clients` + contraintes de latitude/longitude ;
- index `(created_at desc, id desc)` pour la pagination ;
- RLS `select` / `insert` / `update` / `delete` pour `anon` ;
- fonction `register_queue_client(...)` en `SECURITY DEFINER` ;
- ajout de la table à la publication `supabase_realtime`.

## Lancer

```bash
flutter pub get
flutter create . --project-name waiting_room_app --platforms=android,ios,web
flutter run \
  --dart-define=SUPABASE_URL=https://votre-projet.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=votre-cle-anon
```

Sans configuration, l'application démarre en **mode démo** : les inscriptions
sont persistées dans SQLite et synchronisées vers un repository en mémoire.

> SQLite n'est pas disponible sur le web. Utiliser un émulateur, un appareil ou
> le desktop pour cet atelier.

## Tests

```bash
flutter test
```

- `test/models/client_test.dart` : sérialisation locale / distante, `hasLocation`.
- `test/services/sync_service_test.dart` : succès, échec, retry, idempotence.
- `test/providers/connectivity_provider_test.dart` : offline, backend
  indisponible, debounce et notifications.
- `test/providers/queue_provider_test.dart` : pagination, déduplication
  Realtime, offline-first, retry, suppression.
- `test/repositories/queue_repository_test.dart` : pagination et flux d'inserts
  du repository mémoire.
- `test/storage/local_queue_storage_test.dart` : SQLite en mémoire via
  `sqflite_common_ffi`.
- `test/widgets/*` : bannière offline, carte client, états vide/chargement et
  parcours complet d'inscription.

## Scénario de démonstration

1. En ligne : ajouter « Alice » → elle apparaît dans Supabase (`synced`).
2. Couper Wi-Fi/données : ajouter « Bob » → visible immédiatement, statut
   `failed` (retry automatique prévu).
3. Réactiver le réseau : la bannière disparaît, `syncPending()` renvoie Bob,
   son statut passe à `synced`.
4. Ouvrir un second appareil : les nouveaux clients arrivent par Realtime, une
   seule fois.
5. Ajouter plus de 20 clients : le bouton « Load more » charge la page suivante.
6. Refuser la permission GPS : l'inscription reste possible, sans coordonnées.

## Livrables

- [x] Architecture en couches (`models`, `providers`, `services`,
      `repositories`, `storage`, `screens`, `widgets`).
- [x] Géolocalisation optionnelle et gestion des permissions.
- [x] Persistance SQLite et synchronisation automatique des inscriptions.
- [x] Prévention des doublons (UUID local + RPC idempotent).
- [x] Pagination (20 par page) et fusion Realtime sans doublon.
- [x] États loading / empty / error / offline et bannière de connectivité.
- [x] Tests TDD des modèles, services, providers, repository, stockage et widgets.
