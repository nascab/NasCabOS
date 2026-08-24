import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/photo_backup_models.dart';

class PhotoBackupCursor {
  final int lastCreatedAtMs;
  final String lastUniqueId;

  const PhotoBackupCursor({
    required this.lastCreatedAtMs,
    required this.lastUniqueId,
  });
}

class PhotoBackupStorage {
  static final PhotoBackupStorage instance = PhotoBackupStorage._();
  PhotoBackupStorage._();

  Database? _db;

  Future<Database> _openDb() async {
    if (_db != null) return _db!;
    sqfliteFfiInit();
    final base = await getApplicationSupportDirectory();
    final dbPath = p.join(base.path, 'photo_backup.db');
    final factory = databaseFactoryFfi;
    _db = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS photo_backup_task ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT,'
            'server_id TEXT NOT NULL DEFAULT "",'
            'user_id INTEGER NOT NULL DEFAULT 0,'
            'name TEXT NOT NULL,'
            'source_type TEXT NOT NULL,'
            'source_id TEXT NOT NULL,'
            'source_name TEXT NOT NULL,'
            'target_dir TEXT NOT NULL,'
            'name_strategy TEXT NOT NULL DEFAULT "skip",'
            'save_type TEXT NOT NULL DEFAULT "",'
            'upload_live_photo_video INTEGER NOT NULL DEFAULT 0,'
            'auto_start_on_launch INTEGER NOT NULL DEFAULT 0,'
            'created_at_ms INTEGER NOT NULL,'
            'updated_at_ms INTEGER NOT NULL'
            ')',
          );
          await db.execute(
            'CREATE TABLE IF NOT EXISTS photo_backup_run_record ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT,'
            'task_id INTEGER NOT NULL,'
            'trigger_type TEXT NOT NULL,'
            'started_at_ms INTEGER NOT NULL,'
            'finished_at_ms INTEGER NOT NULL DEFAULT 0,'
            'success_count INTEGER NOT NULL DEFAULT 0,'
            'failed_count INTEGER NOT NULL DEFAULT 0,'
            'total_bytes INTEGER NOT NULL DEFAULT 0,'
            'FOREIGN KEY(task_id) REFERENCES photo_backup_task(id) ON DELETE CASCADE'
            ')',
          );
          await db.execute(
            'CREATE TABLE IF NOT EXISTS photo_backup_file_record ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT,'
            'task_id INTEGER NOT NULL,'
            'run_id INTEGER NOT NULL,'
            'source_unique_id TEXT NOT NULL,'
            'display_name TEXT NOT NULL,'
            'local_path TEXT NOT NULL,'
            'size INTEGER NOT NULL DEFAULT 0,'
            'source_create_at_ms INTEGER NOT NULL DEFAULT 0,'
            'uploaded_at_ms INTEGER NOT NULL,'
            'status TEXT NOT NULL,'
            'error TEXT NOT NULL,'
            'FOREIGN KEY(task_id) REFERENCES photo_backup_task(id) ON DELETE CASCADE,'
            'FOREIGN KEY(run_id) REFERENCES photo_backup_run_record(id) ON DELETE CASCADE'
            ')',
          );
          await db.execute(
            'CREATE TABLE IF NOT EXISTS photo_backup_cursor ('
            'task_id INTEGER PRIMARY KEY,'
            'last_created_at_ms INTEGER NOT NULL DEFAULT 0,'
            'last_unique_id TEXT NOT NULL DEFAULT "",'
            'updated_at_ms INTEGER NOT NULL,'
            'FOREIGN KEY(task_id) REFERENCES photo_backup_task(id) ON DELETE CASCADE'
            ')',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_photo_backup_task_updated '
            'ON photo_backup_task(updated_at_ms DESC)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_photo_backup_task_owner '
            'ON photo_backup_task(server_id, user_id, updated_at_ms DESC)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_photo_backup_run_task '
            'ON photo_backup_run_record(task_id, started_at_ms DESC)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_photo_backup_file_run '
            'ON photo_backup_file_record(run_id, uploaded_at_ms DESC)',
          );
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE photo_backup_task ADD COLUMN server_id TEXT NOT NULL DEFAULT ""',
            );
            await db.execute(
              'ALTER TABLE photo_backup_task ADD COLUMN user_id INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_photo_backup_task_owner '
              'ON photo_backup_task(server_id, user_id, updated_at_ms DESC)',
            );
          }
        },
        onOpen: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );
    return _db!;
  }

  Future<List<PhotoBackupTask>> listTasks({
    required String serverId,
    required int userId,
  }) async {
    final db = await _openDb();
    final rows = await db.query(
      'photo_backup_task',
      where: 'server_id = ? AND user_id = ?',
      whereArgs: [serverId.trim(), userId],
      orderBy: 'updated_at_ms DESC, id DESC',
    );
    return rows.map((e) => PhotoBackupTask.fromMap(e)).toList();
  }

  Future<int> upsertTask({
    int? id,
    required String serverId,
    required int userId,
    required String name,
    required String sourceType,
    required String sourceId,
    required String sourceName,
    required String targetDir,
    required String nameStrategy,
    required String saveType,
    required bool uploadLivePhotoVideo,
    required bool autoStartOnLaunch,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final db = await _openDb();
    if (id != null && id > 0) {
      await db.update(
        'photo_backup_task',
        {
          'server_id': serverId,
          'user_id': userId,
          'name': name,
          'source_type': sourceType,
          'source_id': sourceId,
          'source_name': sourceName,
          'target_dir': targetDir,
          'name_strategy': nameStrategy,
          'save_type': saveType,
          'upload_live_photo_video': uploadLivePhotoVideo ? 1 : 0,
          'auto_start_on_launch': autoStartOnLaunch ? 1 : 0,
          'updated_at_ms': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }
    return await db.insert('photo_backup_task', {
      'server_id': serverId,
      'user_id': userId,
      'name': name,
      'source_type': sourceType,
      'source_id': sourceId,
      'source_name': sourceName,
      'target_dir': targetDir,
      'name_strategy': nameStrategy,
      'save_type': saveType,
      'upload_live_photo_video': uploadLivePhotoVideo ? 1 : 0,
      'auto_start_on_launch': autoStartOnLaunch ? 1 : 0,
      'created_at_ms': now,
      'updated_at_ms': now,
    });
  }

  Future<void> deleteTask(int taskId) async {
    final db = await _openDb();
    await db.delete('photo_backup_task', where: 'id = ?', whereArgs: [taskId]);
  }

  Future<int> createRun({
    required int taskId,
    required String triggerType,
    required int startedAtMs,
  }) async {
    final db = await _openDb();
    return await db.insert('photo_backup_run_record', {
      'task_id': taskId,
      'trigger_type': triggerType,
      'started_at_ms': startedAtMs,
      'finished_at_ms': 0,
      'success_count': 0,
      'failed_count': 0,
      'total_bytes': 0,
    });
  }

  Future<void> finishRun({
    required int runId,
    required int finishedAtMs,
    required int successCount,
    required int failedCount,
    required int totalBytes,
  }) async {
    final db = await _openDb();
    await db.update(
      'photo_backup_run_record',
      {
        'finished_at_ms': finishedAtMs,
        'success_count': successCount,
        'failed_count': failedCount,
        'total_bytes': totalBytes,
      },
      where: 'id = ?',
      whereArgs: [runId],
    );
  }

  Future<void> insertFileRecord({
    required int taskId,
    required int runId,
    required String sourceUniqueId,
    required String displayName,
    required String localPath,
    required int size,
    required int sourceCreateAtMs,
    required int uploadedAtMs,
    required String status,
    required String error,
  }) async {
    final db = await _openDb();
    await db.insert('photo_backup_file_record', {
      'task_id': taskId,
      'run_id': runId,
      'source_unique_id': sourceUniqueId,
      'display_name': displayName,
      'local_path': localPath,
      'size': size,
      'source_create_at_ms': sourceCreateAtMs,
      'uploaded_at_ms': uploadedAtMs,
      'status': status,
      'error': error,
    });
  }

  Future<List<PhotoBackupRunRecord>> listRuns(int taskId) async {
    final db = await _openDb();
    final rows = await db.query(
      'photo_backup_run_record',
      where: 'task_id = ?',
      whereArgs: [taskId],
      orderBy: 'started_at_ms DESC, id DESC',
    );
    return rows.map((e) => PhotoBackupRunRecord.fromMap(e)).toList();
  }

  Future<List<PhotoBackupFileRecord>> listRunFiles(int runId) async {
    final db = await _openDb();
    final rows = await db.query(
      'photo_backup_file_record',
      where: 'run_id = ?',
      whereArgs: [runId],
      orderBy: 'uploaded_at_ms DESC, id DESC',
    );
    return rows.map((e) => PhotoBackupFileRecord.fromMap(e)).toList();
  }

  Future<void> deleteRun(int runId) async {
    final db = await _openDb();
    await db.delete(
      'photo_backup_run_record',
      where: 'id = ?',
      whereArgs: [runId],
    );
  }

  Future<void> clearTaskRecords(int taskId) async {
    final db = await _openDb();
    await db.delete(
      'photo_backup_run_record',
      where: 'task_id = ?',
      whereArgs: [taskId],
    );
    await db.delete(
      'photo_backup_file_record',
      where: 'task_id = ?',
      whereArgs: [taskId],
    );
    await db.delete(
      'photo_backup_cursor',
      where: 'task_id = ?',
      whereArgs: [taskId],
    );
  }

  Future<PhotoBackupCursor?> loadCursor(int taskId) async {
    final db = await _openDb();
    final rows = await db.query(
      'photo_backup_cursor',
      where: 'task_id = ?',
      whereArgs: [taskId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    int asInt(Object? value, int fallback) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? fallback;
    }

    return PhotoBackupCursor(
      lastCreatedAtMs: asInt(row['last_created_at_ms'], 0),
      lastUniqueId: (row['last_unique_id']?.toString() ?? '').trim(),
    );
  }

  Future<void> upsertCursor({
    required int taskId,
    required int lastCreatedAtMs,
    required String lastUniqueId,
  }) async {
    final db = await _openDb();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('photo_backup_cursor', {
      'task_id': taskId,
      'last_created_at_ms': lastCreatedAtMs,
      'last_unique_id': lastUniqueId,
      'updated_at_ms': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
