import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 单条下载完成记录（本地数据库）
class DownloadHistoryRow {
  final int id;
  final String localPath;
  final String remotePath;
  final String displayName;
  final int size;
  final int completedAtMs;
  final String? taskId;

  const DownloadHistoryRow({
    required this.id,
    required this.localPath,
    required this.remotePath,
    required this.displayName,
    required this.size,
    required this.completedAtMs,
    required this.taskId,
  });

  factory DownloadHistoryRow.fromMap(Map<String, Object?> m) {
    return DownloadHistoryRow(
      id: m['id']! as int,
      localPath: m['local_path']! as String,
      remotePath: m['remote_path']! as String,
      displayName: m['display_name']! as String,
      size: m['size']! as int,
      completedAtMs: m['completed_at_ms']! as int,
      taskId: m['task_id'] as String?,
    );
  }
}

/// 下载完成记录持久化（与「下载中心 - 已完成」列表对应）
class DownloadHistoryStorage {
  DownloadHistoryStorage._();
  static final DownloadHistoryStorage instance = DownloadHistoryStorage._();

  /// 调试用：Xcode / `flutter run` 控制台搜 `[DownloadHistory]`
  static void trace(String msg, [Object? detail]) {
    // ignore: avoid_print
    print(
      '[DownloadHistory] $msg${detail != null ? ': $detail' : ''}',
    );
  }

  Database? _db;
  Future<Database>? _opening;
  Future<void> _writeTail = Future<void>.value();

  /// 并发下只执行一次 open，避免多路同时 `openDatabase` 抢锁或卡住。
  Future<Database> _openDatabaseOnce() async {
    trace('_openDb start sqfliteFfiInit');
    sqfliteFfiInit();
    trace('_openDb getApplicationSupportDirectory...');
    final base = await getApplicationSupportDirectory();
    final dbPath = p.join(base.path, 'download_history.db');
    trace('_openDb path', dbPath);
    final factory = databaseFactoryFfi;
    trace('_openDb openDatabase...');
    final db = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS download_history ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT,'
            'local_path TEXT NOT NULL UNIQUE,'
            'remote_path TEXT NOT NULL,'
            'display_name TEXT NOT NULL,'
            'size INTEGER NOT NULL,'
            'completed_at_ms INTEGER NOT NULL,'
            'task_id TEXT'
            ')',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_download_history_completed '
            'ON download_history(completed_at_ms DESC)',
          );
        },
        onOpen: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );
    trace('_openDb openDatabase done');
    return db;
  }

  Future<Database> _openDb() async {
    if (_db != null) {
      trace('_openDb reuse existing instance');
      return _db!;
    }
    _opening ??= _openDatabaseOnce();
    try {
      _db = await _opening!;
      return _db!;
    } finally {
      _opening = null;
    }
  }

  /// 下载成功落库；同一路径重复写入时替换为最新信息
  Future<void> recordCompletedFile({
    required String localPath,
    required String remotePath,
    required String displayName,
    required int size,
    String? taskId,
  }) async {
    if (kIsWeb) {
      trace('recordCompletedFile skip kIsWeb');
      return;
    }
    final lp = localPath.trim();
    if (lp.isEmpty) {
      trace('recordCompletedFile skip empty localPath');
      return;
    }
    trace(
      'recordCompletedFile enqueue',
      'local=$lp remote=${remotePath.trim().isEmpty ? '(fallback lp)' : remotePath.trim()} size=$size taskId=$taskId',
    );
    // 串行化写入，避免并发 insert 在 iOS 上出现偶发落库丢失。
    _writeTail = _writeTail.catchError((Object e, StackTrace st) {
      trace('writeTail previous op error (continuing chain)', '$e\n$st');
    }).then((_) async {
      final sw = Stopwatch()..start();
      trace('writeTail job start', lp);
      try {
        final db = await _openDb();
        trace('writeTail after _openDb', '${sw.elapsedMilliseconds}ms');
        final now = DateTime.now().millisecondsSinceEpoch;
        final row = <String, Object?>{
          'local_path': lp,
          'remote_path': remotePath.trim().isEmpty ? lp : remotePath.trim(),
          'display_name': displayName.trim().isEmpty
              ? p.basename(lp)
              : displayName.trim(),
          'size': size < 0 ? 0 : size,
          'completed_at_ms': now,
          'task_id': taskId,
        };
        trace('writeTail insert...', row);
        final id = await db.insert(
          'download_history',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        trace(
          'writeTail insert ok',
          'id=$id elapsed=${sw.elapsedMilliseconds}ms',
        );
      } catch (e, st) {
        trace('writeTail insert FAILED', '$e\n$st');
        rethrow;
      }
    });
    try {
      await _writeTail;
      trace('recordCompletedFile await _writeTail done', lp);
    } catch (e, st) {
      // 仅打日志，不中断下载后续流程（insert 失败时便于在控制台看到栈）
      trace('recordCompletedFile await _writeTail FAILED', '$e\n$st');
    }
  }

  Future<int> count() async {
    if (kIsWeb) return 0;
    final db = await _openDb();
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM download_history');
    final n = r.first['c'];
    if (n is int) return n;
    if (n is num) return n.toInt();
    return 0;
  }

  /// 按完成时间倒序分页
  Future<List<DownloadHistoryRow>> page({
    required int offset,
    required int limit,
  }) async {
    if (kIsWeb) return [];
    final db = await _openDb();
    final rows = await db.query(
      'download_history',
      orderBy: 'completed_at_ms DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(DownloadHistoryRow.fromMap).toList();
  }

  Future<void> deleteById(int id) async {
    if (kIsWeb) return;
    final db = await _openDb();
    await db.delete('download_history', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAllRecords() async {
    if (kIsWeb) return;
    final db = await _openDb();
    await db.delete('download_history');
  }

  /// 返回所有记录的本地路径（用于「同时删除文件」）
  Future<List<String>> allLocalPaths() async {
    if (kIsWeb) return [];
    final db = await _openDb();
    final rows = await db.query('download_history', columns: ['local_path']);
    return rows
        .map((e) => e['local_path'] as String?)
        .whereType<String>()
        .toList();
  }
}
