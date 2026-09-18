import { relationalStore } from '@kit.ArkData';
import { WindowStore } from '../../../common/WindowStore';
import {
  PhotoBackupCursor, PhotoBackupFileRecord, PhotoBackupRunRecord,
  PhotoBackupSourceType, PhotoBackupTask
} from '../models/PhotoBackupModels';

const DB_NAME = 'photo_backup.db';
const DB_VERSION = 2;

/**
 * 相册备份本地存储（对齐 Flutter photo_backup_storage.dart）：
 * photo_backup_task / photo_backup_run_record / photo_backup_file_record / photo_backup_cursor 四表。
 * 外键级联依赖系统支持不稳定，删除时显式清理子表。
 */
export class PhotoBackupStorage {
  private static db: relationalStore.RdbStore | undefined;

  private static async openDb(): Promise<relationalStore.RdbStore> {
    if (PhotoBackupStorage.db !== undefined) {
      return PhotoBackupStorage.db;
    }
    const ctx = WindowStore.appContext;
    if (ctx === undefined) {
      throw new Error('photo_backup_context_missing');
    }
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store = await relationalStore.getRdbStore(ctx, config);
    await store.executeSql(
      'CREATE TABLE IF NOT EXISTS photo_backup_task (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT,' +
      'server_id TEXT NOT NULL DEFAULT "",' +
      'user_id INTEGER NOT NULL DEFAULT 0,' +
      'name TEXT NOT NULL,' +
      'source_type TEXT NOT NULL,' +
      'source_id TEXT NOT NULL,' +
      'source_name TEXT NOT NULL,' +
      'target_dir TEXT NOT NULL,' +
      'name_strategy TEXT NOT NULL DEFAULT "skip",' +
      'save_type TEXT NOT NULL DEFAULT "",' +
      'upload_live_photo_video INTEGER NOT NULL DEFAULT 0,' +
      'auto_start_on_launch INTEGER NOT NULL DEFAULT 0,' +
      'created_at_ms INTEGER NOT NULL,' +
      'updated_at_ms INTEGER NOT NULL' +
      ')');
    await store.executeSql(
      'CREATE TABLE IF NOT EXISTS photo_backup_run_record (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT,' +
      'task_id INTEGER NOT NULL,' +
      'trigger_type TEXT NOT NULL,' +
      'started_at_ms INTEGER NOT NULL,' +
      'finished_at_ms INTEGER NOT NULL DEFAULT 0,' +
      'success_count INTEGER NOT NULL DEFAULT 0,' +
      'failed_count INTEGER NOT NULL DEFAULT 0,' +
      'total_bytes INTEGER NOT NULL DEFAULT 0' +
      ')');
    await store.executeSql(
      'CREATE TABLE IF NOT EXISTS photo_backup_file_record (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT,' +
      'task_id INTEGER NOT NULL,' +
      'run_id INTEGER NOT NULL,' +
      'source_unique_id TEXT NOT NULL,' +
      'display_name TEXT NOT NULL,' +
      'local_path TEXT NOT NULL,' +
      'size INTEGER NOT NULL DEFAULT 0,' +
      'source_create_at_ms INTEGER NOT NULL DEFAULT 0,' +
      'uploaded_at_ms INTEGER NOT NULL,' +
      'status TEXT NOT NULL,' +
      'error TEXT NOT NULL' +
      ')');
    await store.executeSql(
      'CREATE TABLE IF NOT EXISTS photo_backup_cursor (' +
      'task_id INTEGER PRIMARY KEY,' +
      'last_created_at_ms INTEGER NOT NULL DEFAULT 0,' +
      'last_unique_id TEXT NOT NULL DEFAULT "",' +
      'updated_at_ms INTEGER NOT NULL' +
      ')');
    await store.executeSql(
      'CREATE INDEX IF NOT EXISTS idx_photo_backup_task_updated ' +
      'ON photo_backup_task(updated_at_ms DESC)');
    await store.executeSql(
      'CREATE INDEX IF NOT EXISTS idx_photo_backup_task_owner ' +
      'ON photo_backup_task(server_id, user_id, updated_at_ms DESC)');
    await store.executeSql(
      'CREATE INDEX IF NOT EXISTS idx_photo_backup_run_task ' +
      'ON photo_backup_run_record(task_id, started_at_ms DESC)');
    await store.executeSql(
      'CREATE INDEX IF NOT EXISTS idx_photo_backup_file_run ' +
      'ON photo_backup_file_record(run_id, uploaded_at_ms DESC)');
    if (store.version < DB_VERSION) {
      store.version = DB_VERSION;
    }
    PhotoBackupStorage.db = store;
    return store;
  }

  // ============================================================
  // ResultSet 解析辅助
  // ============================================================

  private static rsString(rs: relationalStore.ResultSet, name: string): string {
    const i = rs.getColumnIndex(name);
    if (i < 0 || rs.isColumnNull(i)) {
      return '';
    }
    const v = rs.getString(i);
    return v === undefined || v === null ? '' : v;
  }

  private static rsLong(rs: relationalStore.ResultSet, name: string): number {
    const i = rs.getColumnIndex(name);
    if (i < 0 || rs.isColumnNull(i)) {
      return 0;
    }
    try {
      const v = rs.getLong(i);
      return v === undefined || v === null ? 0 : v;
    } catch (_e) {
      return 0;
    }
  }

  private static parseTask(rs: relationalStore.ResultSet): PhotoBackupTask {
    const t = new PhotoBackupTask();
    t.id = PhotoBackupStorage.rsLong(rs, 'id');
    t.serverId = PhotoBackupStorage.rsString(rs, 'server_id').trim();
    t.userId = PhotoBackupStorage.rsLong(rs, 'user_id');
    t.name = PhotoBackupStorage.rsString(rs, 'name').trim();
    t.sourceType = PhotoBackupStorage.rsString(rs, 'source_type').trim() === 'album'
      ? PhotoBackupSourceType.ALBUM : PhotoBackupSourceType.FOLDER;
    t.sourceId = PhotoBackupStorage.rsString(rs, 'source_id').trim();
    t.sourceName = PhotoBackupStorage.rsString(rs, 'source_name').trim();
    t.targetDir = PhotoBackupStorage.rsString(rs, 'target_dir').trim();
    t.nameStrategy = PhotoBackupStorage.rsString(rs, 'name_strategy').trim() || 'skip';
    t.saveType = PhotoBackupStorage.rsString(rs, 'save_type').trim();
    t.uploadLivePhotoVideo = PhotoBackupStorage.rsLong(rs, 'upload_live_photo_video') === 1;
    t.autoStartOnLaunch = PhotoBackupStorage.rsLong(rs, 'auto_start_on_launch') === 1;
    t.createdAtMs = PhotoBackupStorage.rsLong(rs, 'created_at_ms');
    t.updatedAtMs = PhotoBackupStorage.rsLong(rs, 'updated_at_ms');
    return t;
  }

  private static parseRun(rs: relationalStore.ResultSet): PhotoBackupRunRecord {
    const r = new PhotoBackupRunRecord();
    r.id = PhotoBackupStorage.rsLong(rs, 'id');
    r.taskId = PhotoBackupStorage.rsLong(rs, 'task_id');
    r.triggerType = PhotoBackupStorage.rsString(rs, 'trigger_type').trim();
    r.startedAtMs = PhotoBackupStorage.rsLong(rs, 'started_at_ms');
    r.finishedAtMs = PhotoBackupStorage.rsLong(rs, 'finished_at_ms');
    r.successCount = PhotoBackupStorage.rsLong(rs, 'success_count');
    r.failedCount = PhotoBackupStorage.rsLong(rs, 'failed_count');
    r.totalBytes = PhotoBackupStorage.rsLong(rs, 'total_bytes');
    return r;
  }

  private static parseFileRecord(rs: relationalStore.ResultSet): PhotoBackupFileRecord {
    const f = new PhotoBackupFileRecord();
    f.id = PhotoBackupStorage.rsLong(rs, 'id');
    f.taskId = PhotoBackupStorage.rsLong(rs, 'task_id');
    f.runId = PhotoBackupStorage.rsLong(rs, 'run_id');
    f.sourceUniqueId = PhotoBackupStorage.rsString(rs, 'source_unique_id').trim();
    f.displayName = PhotoBackupStorage.rsString(rs, 'display_name').trim();
    f.localPath = PhotoBackupStorage.rsString(rs, 'local_path').trim();
    f.size = PhotoBackupStorage.rsLong(rs, 'size');
    f.sourceCreateAtMs = PhotoBackupStorage.rsLong(rs, 'source_create_at_ms');
    f.uploadedAtMs = PhotoBackupStorage.rsLong(rs, 'uploaded_at_ms');
    f.status = PhotoBackupStorage.rsString(rs, 'status').trim();
    f.error = PhotoBackupStorage.rsString(rs, 'error').trim();
    return f;
  }

  private static async queryAll(pred: relationalStore.RdbPredicates): Promise<relationalStore.ResultSet> {
    const store = await PhotoBackupStorage.openDb();
    return store.query(pred);
  }

  // ============================================================
  // 任务表
  // ============================================================

  async listTasks(serverId: string, userId: number): Promise<PhotoBackupTask[]> {
    const pred = new relationalStore.RdbPredicates('photo_backup_task');
    pred.equalTo('server_id', serverId.trim()).and().equalTo('user_id', userId);
    pred.orderByDesc('updated_at_ms').orderByDesc('id');
    const out: PhotoBackupTask[] = [];
    const rs = await PhotoBackupStorage.queryAll(pred);
    try {
      while (rs.goToNextRow()) {
        out.push(PhotoBackupStorage.parseTask(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  async upsertTask(t: PhotoBackupTask): Promise<number> {
    const store = await PhotoBackupStorage.openDb();
    const now = Date.now();
    if (t.id > 0) {
      const values: relationalStore.ValuesBucket = {
        'server_id': t.serverId,
        'user_id': t.userId,
        'name': t.name,
        'source_type': t.sourceType,
        'source_id': t.sourceId,
        'source_name': t.sourceName,
        'target_dir': t.targetDir,
        'name_strategy': t.nameStrategy,
        'save_type': t.saveType,
        'upload_live_photo_video': t.uploadLivePhotoVideo ? 1 : 0,
        'auto_start_on_launch': t.autoStartOnLaunch ? 1 : 0,
        'updated_at_ms': now
      };
      const pred = new relationalStore.RdbPredicates('photo_backup_task');
      pred.equalTo('id', t.id);
      await store.update(values, pred);
      t.updatedAtMs = now;
      return t.id;
    }
    const values: relationalStore.ValuesBucket = {
      'server_id': t.serverId,
      'user_id': t.userId,
      'name': t.name,
      'source_type': t.sourceType,
      'source_id': t.sourceId,
      'source_name': t.sourceName,
      'target_dir': t.targetDir,
      'name_strategy': t.nameStrategy,
      'save_type': t.saveType,
      'upload_live_photo_video': t.uploadLivePhotoVideo ? 1 : 0,
      'auto_start_on_launch': t.autoStartOnLaunch ? 1 : 0,
      'created_at_ms': now,
      'updated_at_ms': now
    };
    const rowId = await store.insert('photo_backup_task', values);
    return rowId;
  }

  async deleteTask(taskId: number): Promise<void> {
    const store = await PhotoBackupStorage.openDb();
    // 显式清理子表（保证级联语义）
    await PhotoBackupStorage.deleteByTaskId(store, 'photo_backup_file_record', taskId);
    await PhotoBackupStorage.deleteByTaskId(store, 'photo_backup_run_record', taskId);
    await PhotoBackupStorage.deleteByTaskId(store, 'photo_backup_cursor', taskId);
    const pred = new relationalStore.RdbPredicates('photo_backup_task');
    pred.equalTo('id', taskId);
    await store.delete(pred);
  }

  private static async deleteByTaskId(store: relationalStore.RdbStore,
    table: string, taskId: number): Promise<void> {
    const pred = new relationalStore.RdbPredicates(table);
    pred.equalTo('task_id', taskId);
    await store.delete(pred);
  }

  // ============================================================
  // 运行记录表
  // ============================================================

  async createRun(taskId: number, triggerType: string, startedAtMs: number): Promise<number> {
    const store = await PhotoBackupStorage.openDb();
    const values: relationalStore.ValuesBucket = {
      'task_id': taskId,
      'trigger_type': triggerType,
      'started_at_ms': startedAtMs,
      'finished_at_ms': 0,
      'success_count': 0,
      'failed_count': 0,
      'total_bytes': 0
    };
    return store.insert('photo_backup_run_record', values);
  }

  async finishRun(runId: number, finishedAtMs: number,
    successCount: number, failedCount: number, totalBytes: number): Promise<void> {
    const store = await PhotoBackupStorage.openDb();
    const values: relationalStore.ValuesBucket = {
      'finished_at_ms': finishedAtMs,
      'success_count': successCount,
      'failed_count': failedCount,
      'total_bytes': totalBytes
    };
    const pred = new relationalStore.RdbPredicates('photo_backup_run_record');
    pred.equalTo('id', runId);
    await store.update(values, pred);
  }

  async listRuns(taskId: number): Promise<PhotoBackupRunRecord[]> {
    const pred = new relationalStore.RdbPredicates('photo_backup_run_record');
    pred.equalTo('task_id', taskId);
    pred.orderByDesc('started_at_ms').orderByDesc('id');
    const out: PhotoBackupRunRecord[] = [];
    const rs = await PhotoBackupStorage.queryAll(pred);
    try {
      while (rs.goToNextRow()) {
        out.push(PhotoBackupStorage.parseRun(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  async deleteRun(runId: number): Promise<void> {
    const store = await PhotoBackupStorage.openDb();
    const pred = new relationalStore.RdbPredicates('photo_backup_file_record');
    pred.equalTo('run_id', runId);
    await store.delete(pred);
    const runPred = new relationalStore.RdbPredicates('photo_backup_run_record');
    runPred.equalTo('id', runId);
    await store.delete(runPred);
  }

  /** 清空任务的运行/文件记录与光标（对齐 Flutter clearTaskRecords，用于「上传全部」） */
  async clearTaskRecords(taskId: number): Promise<void> {
    const store = await PhotoBackupStorage.openDb();
    await PhotoBackupStorage.deleteByTaskId(store, 'photo_backup_file_record', taskId);
    await PhotoBackupStorage.deleteByTaskId(store, 'photo_backup_run_record', taskId);
    await PhotoBackupStorage.deleteByTaskId(store, 'photo_backup_cursor', taskId);
  }

  // ============================================================
  // 文件记录表
  // ============================================================

  async insertFileRecord(f: PhotoBackupFileRecord): Promise<void> {
    const store = await PhotoBackupStorage.openDb();
    const values: relationalStore.ValuesBucket = {
      'task_id': f.taskId,
      'run_id': f.runId,
      'source_unique_id': f.sourceUniqueId,
      'display_name': f.displayName,
      'local_path': f.localPath,
      'size': f.size,
      'source_create_at_ms': f.sourceCreateAtMs,
      'uploaded_at_ms': f.uploadedAtMs,
      'status': f.status,
      'error': f.error
    };
    await store.insert('photo_backup_file_record', values);
  }

  async listRunFiles(runId: number): Promise<PhotoBackupFileRecord[]> {
    const pred = new relationalStore.RdbPredicates('photo_backup_file_record');
    pred.equalTo('run_id', runId);
    pred.orderByDesc('uploaded_at_ms').orderByDesc('id');
    const out: PhotoBackupFileRecord[] = [];
    const rs = await PhotoBackupStorage.queryAll(pred);
    try {
      while (rs.goToNextRow()) {
        out.push(PhotoBackupStorage.parseFileRecord(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  // ============================================================
  // 光标表
  // ============================================================

  async loadCursor(taskId: number): Promise<PhotoBackupCursor | undefined> {
    const pred = new relationalStore.RdbPredicates('photo_backup_cursor');
    pred.equalTo('task_id', taskId);
    pred.limitAs(1);
    const rs = await PhotoBackupStorage.queryAll(pred);
    let result: PhotoBackupCursor | undefined = undefined;
    try {
      if (rs.goToNextRow()) {
        result = new PhotoBackupCursor(
          PhotoBackupStorage.rsLong(rs, 'last_created_at_ms'),
          PhotoBackupStorage.rsString(rs, 'last_unique_id').trim());
      }
    } finally {
      rs.close();
    }
    return result;
  }

  async upsertCursor(taskId: number, lastCreatedAtMs: number, lastUniqueId: string): Promise<void> {
    const store = await PhotoBackupStorage.openDb();
    const values: relationalStore.ValuesBucket = {
      'task_id': taskId,
      'last_created_at_ms': lastCreatedAtMs,
      'last_unique_id': lastUniqueId,
      'updated_at_ms': Date.now()
    };
    await store.insert('photo_backup_cursor', values,
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }
}
