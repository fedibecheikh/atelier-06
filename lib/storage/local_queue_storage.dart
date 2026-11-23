import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:waiting_room_app/models/sync_status.dart';

/// Persistance locale de la file d'attente.
///
/// Le statut de synchronisation (`sync_status`) est une métadonnée propre au
/// device : il n'est jamais envoyé à Supabase.
abstract class LocalQueueStorage {
  Future<void> saveClient(Map<String, dynamic> client);

  Future<List<Map<String, dynamic>>> getClients();

  /// Enregistrements `pending` **et** `failed`, triés du plus ancien au plus
  /// récent pour être rejoués dans l'ordre d'inscription.
  Future<List<Map<String, dynamic>>> getPendingClients();

  Future<void> updateSyncStatus(String id, SyncStatus status);

  Future<void> deleteClient(String id);

  Future<void> close();
}

class SqliteLocalQueueStorage implements LocalQueueStorage {
  SqliteLocalQueueStorage({
    this.databaseName = 'waiting_queue_v6.db',
    this.inMemory = false,
  });

  static const String tableName = 'clients';

  final String databaseName;
  final bool inMemory;

  Database? _database;

  Future<Database> get database async => _database ??= await _open();

  Future<Database> _open() async {
    final path = inMemory
        ? inMemoryDatabasePath
        : join(await getDatabasesPath(), databaseName);

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $tableName (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            lat REAL,
            lng REAL,
            location_accuracy_m REAL,
            created_at TEXT NOT NULL,
            sync_status TEXT NOT NULL
          )
        ''');
      },
    );
  }

  @override
  Future<void> saveClient(Map<String, dynamic> client) async {
    final db = await database;
    await db.insert(
      tableName,
      client,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getClients() async {
    final db = await database;
    return db.query(tableName, orderBy: 'created_at DESC, id DESC');
  }

  @override
  Future<List<Map<String, dynamic>>> getPendingClients() async {
    final db = await database;
    return db.query(
      tableName,
      where: 'sync_status = ? OR sync_status = ?',
      whereArgs: [SyncStatus.pending.name, SyncStatus.failed.name],
      orderBy: 'created_at ASC, id ASC',
    );
  }

  @override
  Future<void> updateSyncStatus(String id, SyncStatus status) async {
    final db = await database;
    await db.update(
      tableName,
      {'sync_status': status.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> deleteClient(String id) async {
    final db = await database;
    await db.delete(tableName, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
