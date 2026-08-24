import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:convert';

class LocalBackupProfile {
  final int id;
  final String name;
  final String sourceDir;
  final String sourceBookmark;
  final String targetDir;
  final List<String> excludeItems;
  final bool realtime;
  final int intervalMinutes;
  final int debounceSeconds;
  final String nameStrategy;
  final bool enabled;
  final int lastRunAtMs;
  final int lastSuccessAtMs;
  final int createdAtMs;
  final int updatedAtMs;

  /// 创建该备份任务时当前登录的 serverId，仅当当前登录 serverId 一致时才运行
  final String serverId;

  const LocalBackupProfile({
    required this.id,
    required this.name,
    required this.sourceDir,
    required this.sourceBookmark,
    required this.targetDir,
    required this.excludeItems,
    required this.realtime,
    required this.intervalMinutes,
    required this.debounceSeconds,
    required this.nameStrategy,
    required this.enabled,
    required this.lastRunAtMs,
    required this.lastSuccessAtMs,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.serverId = '',
  });

  LocalBackupProfile copyWith({
    int? id,
    String? name,
    String? sourceDir,
    String? sourceBookmark,
    String? targetDir,
    List<String>? excludeItems,
    bool? realtime,
    int? intervalMinutes,
    int? debounceSeconds,
    String? nameStrategy,
    bool? enabled,
    int? lastRunAtMs,
    int? lastSuccessAtMs,
    int? createdAtMs,
    int? updatedAtMs,
    String? serverId,
  }) {
    return LocalBackupProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      sourceDir: sourceDir ?? this.sourceDir,
      sourceBookmark: sourceBookmark ?? this.sourceBookmark,
      targetDir: targetDir ?? this.targetDir,
      excludeItems: excludeItems ?? this.excludeItems,
      realtime: realtime ?? this.realtime,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      debounceSeconds: debounceSeconds ?? this.debounceSeconds,
      nameStrategy: nameStrategy ?? this.nameStrategy,
      enabled: enabled ?? this.enabled,
      lastRunAtMs: lastRunAtMs ?? this.lastRunAtMs,
      lastSuccessAtMs: lastSuccessAtMs ?? this.lastSuccessAtMs,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      serverId: serverId ?? this.serverId,
    );
  }

  static LocalBackupProfile fromMap(Map<String, Object?> row) {
    int asInt(Object? v, int d) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? d;
    }

    bool asBool(Object? v, bool d) {
      final i = asInt(v, d ? 1 : 0);
      return i == 1;
    }

    List<String> asExcludeItems(Object? v) {
      final raw = v?.toString().trim() ?? '';
      if (raw.isEmpty) return const [];
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! List) return const [];
        final out = <String>[];
        for (final e in decoded) {
          final s = e?.toString().trim() ?? '';
          if (s.isNotEmpty) out.add(s);
        }
        return out;
      } catch (_) {
        return const [];
      }
    }

    return LocalBackupProfile(
      id: asInt(row['id'], 0),
      name: (row['name']?.toString() ?? '').trim(),
      sourceDir: (row['source_dir']?.toString() ?? '').trim(),
      sourceBookmark: (row['source_bookmark']?.toString() ?? '').trim(),
      targetDir: (row['target_dir']?.toString() ?? '').trim(),
      excludeItems: asExcludeItems(row['exclude_items']),
      realtime: asBool(row['realtime'], false),
      intervalMinutes: asInt(row['interval_minutes'], 60),
      debounceSeconds: asInt(row['debounce_seconds'], 30),
      nameStrategy: (row['name_strategy']?.toString() ?? 'skip').trim(),
      enabled: asBool(row['enabled'], true),
      lastRunAtMs: asInt(row['last_run_at_ms'], 0),
      lastSuccessAtMs: asInt(row['last_success_at_ms'], 0),
      createdAtMs: asInt(row['created_at_ms'], 0),
      updatedAtMs: asInt(row['updated_at_ms'], 0),
      serverId: (row['server_id']?.toString() ?? '').trim(),
    );
  }

  Map<String, Object?> toMapForUpsert() {
    return {
      'id': id > 0 ? id : null,
      'name': name,
      'source_dir': sourceDir,
      'source_bookmark': sourceBookmark,
      'target_dir': targetDir,
      'exclude_items': jsonEncode(excludeItems),
      'realtime': realtime ? 1 : 0,
      'interval_minutes': intervalMinutes,
      'debounce_seconds': debounceSeconds,
      'name_strategy': nameStrategy,
      'enabled': enabled ? 1 : 0,
      'last_run_at_ms': lastRunAtMs,
      'last_success_at_ms': lastSuccessAtMs,
      'created_at_ms': createdAtMs,
      'updated_at_ms': updatedAtMs,
      'server_id': serverId,
    };
  }
}

class LocalBackupFileState {
  final int profileId;
  final String relPath;
  final int size;
  final int mtimeMs;
  final int uploadedAtMs;

  const LocalBackupFileState({
    required this.profileId,
    required this.relPath,
    required this.size,
    required this.mtimeMs,
    required this.uploadedAtMs,
  });

  static LocalBackupFileState fromMap(Map<String, Object?> row) {
    int asInt(Object? v, int d) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? d;
    }

    return LocalBackupFileState(
      profileId: asInt(row['profile_id'], 0),
      relPath: (row['rel_path']?.toString() ?? '').trim(),
      size: asInt(row['size'], 0),
      mtimeMs: asInt(row['mtime_ms'], 0),
      uploadedAtMs: asInt(row['uploaded_at_ms'], 0),
    );
  }
}

class LocalBackupUploadLog {
  final int id;
  final int profileId;
  final String relPath;
  final String localPath;
  final int size;
  final int mtimeMs;
  final int startedAtMs;
  final int finishedAtMs;
  final String status;
  final String error;

  const LocalBackupUploadLog({
    required this.id,
    required this.profileId,
    required this.relPath,
    required this.localPath,
    required this.size,
    required this.mtimeMs,
    required this.startedAtMs,
    required this.finishedAtMs,
    required this.status,
    required this.error,
  });

  static LocalBackupUploadLog fromMap(Map<String, Object?> row) {
    int asInt(Object? v, int d) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? d;
    }

    return LocalBackupUploadLog(
      id: asInt(row['id'], 0),
      profileId: asInt(row['profile_id'], 0),
      relPath: (row['rel_path']?.toString() ?? '').trim(),
      localPath: (row['local_path']?.toString() ?? '').trim(),
      size: asInt(row['size'], 0),
      mtimeMs: asInt(row['mtime_ms'], 0),
      startedAtMs: asInt(row['started_at_ms'], 0),
      finishedAtMs: asInt(row['finished_at_ms'], 0),
      status: (row['status']?.toString() ?? '').trim(),
      error: (row['error']?.toString() ?? '').trim(),
    );
  }
}

class LocalBackupStorage {
  static final LocalBackupStorage instance = LocalBackupStorage._();
  LocalBackupStorage._();

  Database? _db;
  Future<Database> _openDb() async {
    if (_db != null) return _db!;
    sqfliteFfiInit();
    final base = await getApplicationSupportDirectory();
    final dbPath = p.join(base.path, 'local_backup.db');
    final factory = databaseFactoryFfi;
    _db = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS local_backup_config ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT,'
            'name TEXT NOT NULL,'
            'source_dir TEXT NOT NULL,'
            'source_bookmark TEXT NOT NULL,'
            'target_dir TEXT NOT NULL,'
            'exclude_items TEXT NOT NULL DEFAULT "[]",'
            'realtime INTEGER NOT NULL,'
            'interval_minutes INTEGER NOT NULL,'
            'debounce_seconds INTEGER NOT NULL,'
            'name_strategy TEXT NOT NULL,'
            'enabled INTEGER NOT NULL,'
            'last_run_at_ms INTEGER NOT NULL DEFAULT 0,'
            'last_success_at_ms INTEGER NOT NULL DEFAULT 0,'
            'created_at_ms INTEGER NOT NULL,'
            'updated_at_ms INTEGER NOT NULL,'
            'server_id TEXT NOT NULL DEFAULT ""'
            ')',
          );
          await db.execute(
            'CREATE TABLE IF NOT EXISTS local_backup_file_state ('
            'profile_id INTEGER NOT NULL,'
            'rel_path TEXT NOT NULL,'
            'size INTEGER NOT NULL,'
            'mtime_ms INTEGER NOT NULL,'
            'uploaded_at_ms INTEGER NOT NULL,'
            'PRIMARY KEY (profile_id, rel_path)'
            ')',
          );
          await db.execute(
            'CREATE TABLE IF NOT EXISTS local_backup_upload_log ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT,'
            'profile_id INTEGER NOT NULL,'
            'rel_path TEXT NOT NULL,'
            'local_path TEXT NOT NULL,'
            'size INTEGER NOT NULL,'
            'mtime_ms INTEGER NOT NULL,'
            'started_at_ms INTEGER NOT NULL,'
            'finished_at_ms INTEGER NOT NULL,'
            'status TEXT NOT NULL,'
            'error TEXT NOT NULL'
            ')',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_local_backup_file_state_pid '
            'ON local_backup_file_state(profile_id)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_local_backup_upload_log_pid '
            'ON local_backup_upload_log(profile_id)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_local_backup_upload_log_time '
            'ON local_backup_upload_log(finished_at_ms)',
          );
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE local_backup_config ADD COLUMN server_id TEXT NOT NULL DEFAULT ""',
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

  /// 返回所有任务；若传入 [serverId] 则仅返回该服务器下的任务
  Future<List<LocalBackupProfile>> listProfiles({String? serverId}) async {
    final db = await _openDb();
    final rows = serverId != null && serverId.isNotEmpty
        ? await db.query(
            'local_backup_config',
            where: 'server_id = ?',
            whereArgs: [serverId],
            orderBy: 'updated_at_ms DESC',
          )
        : await db.query('local_backup_config', orderBy: 'updated_at_ms DESC');
    return rows.map((e) => LocalBackupProfile.fromMap(e)).toList();
  }

  Future<int> upsertProfile({
    int? id,
    required String name,
    required String sourceDir,
    required String sourceBookmark,
    required String targetDir,
    required List<String> excludeItems,
    required bool realtime,
    required int intervalMinutes,
    required int debounceSeconds,
    required String nameStrategy,
    required bool enabled,
    required String serverId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final db = await _openDb();
    final sid = serverId.trim();
    if (id != null && id > 0) {
      await db.update(
        'local_backup_config',
        {
          'name': name,
          'source_dir': sourceDir,
          'source_bookmark': sourceBookmark,
          'target_dir': targetDir,
          'exclude_items': jsonEncode(excludeItems),
          'realtime': realtime ? 1 : 0,
          'interval_minutes': intervalMinutes,
          'debounce_seconds': debounceSeconds,
          'name_strategy': nameStrategy,
          'enabled': enabled ? 1 : 0,
          'server_id': sid,
          'updated_at_ms': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }
    final newId = await db.insert('local_backup_config', {
      'name': name,
      'source_dir': sourceDir,
      'source_bookmark': sourceBookmark,
      'target_dir': targetDir,
      'exclude_items': jsonEncode(excludeItems),
      'realtime': realtime ? 1 : 0,
      'interval_minutes': intervalMinutes,
      'debounce_seconds': debounceSeconds,
      'name_strategy': nameStrategy,
      'enabled': enabled ? 1 : 0,
      'last_run_at_ms': 0,
      'last_success_at_ms': 0,
      'created_at_ms': now,
      'updated_at_ms': now,
      'server_id': sid,
    });
    return newId;
  }

  Future<void> updateProfileRunTimes({
    required int profileId,
    int? lastRunAtMs,
    int? lastSuccessAtMs,
  }) async {
    final db = await _openDb();
    final data = <String, Object?>{};
    if (lastRunAtMs != null) data['last_run_at_ms'] = lastRunAtMs;
    if (lastSuccessAtMs != null) {
      data['last_success_at_ms'] = lastSuccessAtMs;
    }
    if (data.isEmpty) return;
    await db.update(
      'local_backup_config',
      data,
      where: 'id = ?',
      whereArgs: [profileId],
    );
  }

  Future<void> deleteProfile(int id) async {
    final db = await _openDb();
    await db.delete(
      'local_backup_file_state',
      where: 'profile_id = ?',
      whereArgs: [id],
    );
    await db.delete(
      'local_backup_upload_log',
      where: 'profile_id = ?',
      whereArgs: [id],
    );
    await db.delete('local_backup_config', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearFileState(int profileId) async {
    final db = await _openDb();
    await db.delete(
      'local_backup_file_state',
      where: 'profile_id = ?',
      whereArgs: [profileId],
    );
  }

  Future<Map<String, LocalBackupFileState>> loadFileStateMap(
    int profileId,
  ) async {
    final db = await _openDb();
    final rows = await db.query(
      'local_backup_file_state',
      where: 'profile_id = ?',
      whereArgs: [profileId],
    );
    final map = <String, LocalBackupFileState>{};
    for (final r in rows) {
      final st = LocalBackupFileState.fromMap(r);
      if (st.relPath.isNotEmpty) map[st.relPath] = st;
    }
    return map;
  }

  Future<void> upsertFileState(LocalBackupFileState st) async {
    final db = await _openDb();
    await db.insert('local_backup_file_state', {
      'profile_id': st.profileId,
      'rel_path': st.relPath,
      'size': st.size,
      'mtime_ms': st.mtimeMs,
      'uploaded_at_ms': st.uploadedAtMs,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> insertUploadLog({
    required int profileId,
    required String relPath,
    required String localPath,
    required int size,
    required int mtimeMs,
    required int startedAtMs,
    required int finishedAtMs,
    required String status,
    required String error,
  }) async {
    final db = await _openDb();
    return await db.insert('local_backup_upload_log', {
      'profile_id': profileId,
      'rel_path': relPath,
      'local_path': localPath,
      'size': size,
      'mtime_ms': mtimeMs,
      'started_at_ms': startedAtMs,
      'finished_at_ms': finishedAtMs,
      'status': status,
      'error': error,
    });
  }

  Future<List<LocalBackupUploadLog>> listUploadLogs({
    required int profileId,
    int limit = 200,
    int offset = 0,
  }) async {
    final db = await _openDb();
    final rows = await db.query(
      'local_backup_upload_log',
      where: 'profile_id = ?',
      whereArgs: [profileId],
      orderBy: 'finished_at_ms DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map((e) => LocalBackupUploadLog.fromMap(e)).toList();
  }

  Future<void> clearUploadLogs(int profileId) async {
    final db = await _openDb();
    await db.delete(
      'local_backup_upload_log',
      where: 'profile_id = ?',
      whereArgs: [profileId],
    );
  }

  Future<void> pruneUploadLogs({
    required int profileId,
    int maxCount = 3000,
  }) async {
    if (maxCount <= 0) return;
    final db = await _openDb();
    await db.rawDelete(
      'DELETE FROM local_backup_upload_log WHERE id IN ('
      'SELECT id FROM local_backup_upload_log '
      'WHERE profile_id = ? '
      'ORDER BY finished_at_ms DESC, id DESC '
      'LIMIT -1 OFFSET ?'
      ')',
      [profileId, maxCount],
    );
  }
}
