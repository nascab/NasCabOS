import { relationalStore } from '@kit.ArkData';
import { WindowStore } from '../../common/WindowStore';
import { DownloadedFileEntry } from '../models/DownloadModels';

const DB_NAME = 'download_history.db';
const DB_VERSION = 1;

/**
 * 下载历史本地存储（对齐 Flutter download_history_storage.dart）：
 * download_history 表，local_path UNIQUE；完成记录按 completed_at_ms DESC 分页。
 */
export class DownloadHistoryStorage {
  private static db: relationalStore.RdbStore | undefined;

  private static async openDb(): Promise<relationalStore.RdbStore> {
    if (DownloadHistoryStorage.db !== undefined) {
      return DownloadHistoryStorage.db;
    }
    const ctx = WindowStore.appContext;
    if (ctx === undefined) {
      throw new Error('download_history_context_missing');
    }
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store = await relationalStore.getRdbStore(ctx, config);
    await store.executeSql(
      'CREATE TABLE IF NOT EXISTS download_history (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT,' +
      'local_path TEXT NOT NULL UNIQUE,' +
      'remote_path TEXT NOT NULL DEFAULT "",' +
      'display_name TEXT NOT NULL DEFAULT "",' +
      'size INTEGER NOT NULL DEFAULT 0,' +
      'completed_at_ms INTEGER NOT NULL,' +
      'task_id TEXT NOT NULL DEFAULT ""' +
      ')');
    await store.executeSql(
      'CREATE INDEX IF NOT EXISTS idx_download_history_completed ' +
      'ON download_history(completed_at_ms DESC)');
    if (store.version < DB_VERSION) {
      store.version = DB_VERSION;
    }
    DownloadHistoryStorage.db = store;
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

  private static parseEntry(rs: relationalStore.ResultSet): DownloadedFileEntry {
    const e = new DownloadedFileEntry();
    e.id = DownloadHistoryStorage.rsLong(rs, 'id');
    e.path = DownloadHistoryStorage.rsString(rs, 'local_path');
    e.remotePath = DownloadHistoryStorage.rsString(rs, 'remote_path');
    e.name = DownloadHistoryStorage.rsString(rs, 'display_name');
    e.size = DownloadHistoryStorage.rsLong(rs, 'size');
    e.completedTimeMs = DownloadHistoryStorage.rsLong(rs, 'completed_at_ms');
    return e;
  }

  // ============================================================
  // 记录 CRUD
  // ============================================================

  /** 记录完成的下载（同 local_path 冲突时替换，对齐 Flutter REPLACE 策略） */
  async recordCompletedFile(localPath: string, remotePath: string, displayName: string,
    size: number, taskId: string): Promise<void> {
    const store = await DownloadHistoryStorage.openDb();
    const values: relationalStore.ValuesBucket = {
      'local_path': localPath,
      'remote_path': remotePath,
      'display_name': displayName,
      'size': size,
      'completed_at_ms': Date.now(),
      'task_id': taskId
    };
    await store.insert('download_history', values,
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  /** 分页查询（offset/limit，按完成时间倒序） */
  async page(offset: number, limit: number): Promise<DownloadedFileEntry[]> {
    const store = await DownloadHistoryStorage.openDb();
    const pred = new relationalStore.RdbPredicates('download_history');
    pred.orderByDesc('completed_at_ms').orderByDesc('id');
    pred.limitAs(limit).offsetAs(offset);
    const out: DownloadedFileEntry[] = [];
    const rs = await store.query(pred);
    try {
      while (rs.goToNextRow()) {
        out.push(DownloadHistoryStorage.parseEntry(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  /** 按主键删除记录 */
  async deleteById(id: number): Promise<void> {
    const store = await DownloadHistoryStorage.openDb();
    const pred = new relationalStore.RdbPredicates('download_history');
    pred.equalTo('id', id);
    await store.delete(pred);
  }

  /** 清空全部记录（对齐 Flutter clearAllRecords） */
  async clearAllRecords(): Promise<void> {
    const store = await DownloadHistoryStorage.openDb();
    await store.executeSql('DELETE FROM download_history');
  }

  /** 查询全部记录的本地文件路径（「清理全部且删除文件」时使用） */
  async allLocalPaths(): Promise<string[]> {
    const store = await DownloadHistoryStorage.openDb();
    const pred = new relationalStore.RdbPredicates('download_history');
    const out: string[] = [];
    const rs = await store.query(pred);
    try {
      while (rs.goToNextRow()) {
        out.push(DownloadHistoryStorage.rsString(rs, 'local_path'));
      }
    } finally {
      rs.close();
    }
    return out;
  }
}
