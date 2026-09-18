import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { dataSharePredicates } from '@kit.ArkData';
import { abilityAccessCtrl } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { WindowStore } from '../../../common/WindowStore';
import { ToastUtil } from '../../../common/ToastUtil';
import { L10n } from '../../../core/localization/L10n';
import { UploadTransferHelper } from '../../../transfer/utils/UploadTransferHelper';
import {
  PhotoAlbumInfo, PhotoBackupCursor, PhotoBackupSourceType,
  PhotoBackupTask, PhotoSourceEntry
} from '../models/PhotoBackupModels';

/** 全量扫描分页大小（对齐 Flutter _scanAlbum pageSize=200） */
const SCAN_PAGE_SIZE = 200;
/** 流式上传分页大小（对齐 Flutter _scanAlbumBatched pageSize=80） */
const STREAM_PAGE_SIZE = 80;
/** 上传新增 Meta 扫描分页大小（对齐 Flutter _scanAlbumPendingMeta pageSize=500） */
const META_PAGE_SIZE = 500;
/** 实况视频导出超时（毫秒） */
const LIVE_EXPORT_TIMEOUT_MS = 60000;

/** 实况照片视频轨导出结果 */
class LiveVideoExport {
  /** 沙盒文件路径（可被 fileIo 直接读取） */
  path: string = '';
  size: number = 0;
}

/** 待上传的相册资源 Meta（对齐 Flutter _AlbumAssetMeta） */
export class PhotoAlbumAssetMeta {
  asset: photoAccessHelper.PhotoAsset;
  orderMs: number = 0;

  constructor(asset: photoAccessHelper.PhotoAsset, orderMs: number) {
    this.asset = asset;
    this.orderMs = orderMs;
  }
}

/** requestMovingPhoto 的 MediaAssetDataHandler：把 onDataPrepared 包装为 Promise */
class MovingPhotoDataHandler implements photoAccessHelper.MediaAssetDataHandler<photoAccessHelper.MovingPhoto> {
  private resolver: ((data: photoAccessHelper.MovingPhoto) => void) | undefined = undefined;
  private rejecter: ((err: Error) => void) | undefined = undefined;
  readonly promise: Promise<photoAccessHelper.MovingPhoto>;

  constructor() {
    this.promise = new Promise<photoAccessHelper.MovingPhoto>((resolve, reject) => {
      this.resolver = resolve;
      this.rejecter = reject;
    });
  }

  onDataPrepared(data: photoAccessHelper.MovingPhoto, _map?: Map<string, string>): void {
    if (this.resolver) {
      this.resolver(data);
    }
  }

  fail(err: Error): void {
    if (this.rejecter) {
      this.rejecter(err);
    }
  }
}

/**
 * 相册/文件夹来源扫描服务（对齐 Flutter photo_backup_controller.dart 中的扫描逻辑）：
 * - 权限：READ_IMAGEVIDEO（requestPermissionsFromUser，已授权时系统直接返回不弹窗）
 * - 相册枚举：用户相册 + 系统相册，按 albumUri 去重
 * - 三种扫描：全量（页 200）/ 流式逐批（页 80）/ 上传新增 Meta（页 500 + cursor 过滤）
 * - 实况照片：subtype==MOVING_PHOTO 时导出视频轨到沙盒 cache 目录（用完即删）
 * - 资源主体直接用 asset.uri（file://media/... 在有权限时可被 fileIo 读取），无需先导出
 */
export class PhotoAlbumService {
  private static helper: photoAccessHelper.PhotoAccessHelper | undefined = undefined;

  private static readonly FETCH_COLUMNS: string[] = [
    photoAccessHelper.PhotoKeys.DISPLAY_NAME,
    photoAccessHelper.PhotoKeys.SIZE,
    photoAccessHelper.PhotoKeys.DATE_ADDED,
    photoAccessHelper.PhotoKeys.DATE_MODIFIED,
    photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE
  ];

  // ============================================================
  // 权限
  // ============================================================

  /** 请求照片读取权限；已授权时系统直接返回 granted，不弹窗 */
  static async requestPermission(): Promise<boolean> {
    try {
      const ctx = WindowStore.appContext;
      if (!ctx) {
        return false;
      }
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(ctx, ['ohos.permission.READ_IMAGEVIDEO']);
      const results = result.authResults;
      if (results.length === 0) {
        return false;
      }
      for (const r of results) {
        if (r !== 0) {
          return false;
        }
      }
      return true;
    } catch (_e) {
      return false;
    }
  }

  /**
   * 扫描前确保权限（对齐 Flutter _ensurePhotoPermission）：
   * 未授权时 toast 引导，与相册枚举同源判断。
   */
  static async ensurePermission(): Promise<boolean> {
    const ok = await PhotoAlbumService.requestPermission();
    if (!ok) {
      ToastUtil.show(L10n.t('photo_library_permission_missing', '未获得相册访问权限'));
    }
    return ok;
  }

  // ============================================================
  // 相册枚举
  // ============================================================

  private static async getHelper(): Promise<photoAccessHelper.PhotoAccessHelper> {
    if (PhotoAlbumService.helper !== undefined) {
      return PhotoAlbumService.helper;
    }
    const ctx = WindowStore.appContext;
    if (!ctx) {
      throw new Error('photo_backup_context_missing');
    }
    PhotoAlbumService.helper = photoAccessHelper.getPhotoAccessHelper(ctx);
    return PhotoAlbumService.helper;
  }

  /** 便捷方法：相册备份页直接用 asset uri 构造条目（外部无需感知） */
  static isAlbumSource(task: PhotoBackupTask): boolean {
    return task.sourceType === PhotoBackupSourceType.ALBUM;
  }

  /**
   * 枚举全部相册（用户 + 系统收藏/视频/图片等），按 albumUri 去重（对齐 Flutter getAssetPathList）。
   */
  static async listAlbums(): Promise<PhotoAlbumInfo[]> {
    const helper = await PhotoAlbumService.getHelper();
    const out: PhotoAlbumInfo[] = [];
    const seen = new Set<string>();
    const groups: photoAccessHelper.Album[][] = [];
    const userRes = await helper.getAlbums(photoAccessHelper.AlbumType.USER,
      photoAccessHelper.AlbumSubtype.USER_GENERIC);
    try {
      groups.push(await userRes.getAllObjects());
    } finally {
      userRes.close();
    }
    const sysRes = await helper.getAlbums(photoAccessHelper.AlbumType.SYSTEM,
      photoAccessHelper.AlbumSubtype.ANY);
    try {
      groups.push(await sysRes.getAllObjects());
    } finally {
      sysRes.close();
    }
    for (const group of groups) {
      for (const album of group) {
        const id = album.albumUri;
        if (id.length === 0 || seen.has(id)) {
          continue;
        }
        seen.add(id);
        const info = new PhotoAlbumInfo();
        info.id = id;
        info.name = album.albumName;
        info.count = album.count;
        info.coverUri = album.coverUri;
        out.push(info);
      }
    }
    return out;
  }

  /** 按 albumUri 查找相册（对齐 Flutter firstWhereOrNull((e) => e.id == task.sourceId)） */
  static async findAlbum(albumUri: string): Promise<photoAccessHelper.Album | undefined> {
    const helper = await PhotoAlbumService.getHelper();
    const res = await helper.getAlbums(photoAccessHelper.AlbumType.USER,
      photoAccessHelper.AlbumSubtype.USER_GENERIC);
    let found: photoAccessHelper.Album | undefined = undefined;
    try {
      for (const album of await res.getAllObjects()) {
        if (album.albumUri === albumUri) {
          found = album;
          break;
        }
      }
    } finally {
      res.close();
    }
    if (found === undefined) {
      const sysRes = await helper.getAlbums(photoAccessHelper.AlbumType.SYSTEM,
        photoAccessHelper.AlbumSubtype.ANY);
      try {
        for (const album of await sysRes.getAllObjects()) {
          if (album.albumUri === albumUri) {
            found = album;
            break;
          }
        }
      } finally {
        sysRes.close();
      }
    }
    return found;
  }

  // ============================================================
  // 分页拉取
  // ============================================================

  /**
   * 分页拉取相册资源（按 DATE_ADDED 降序）。
   * 本 SDK 的 DataSharePredicates 不支持范围查询/limitAndOffset，时间过滤由调用方
   * 基于 isPending 在内存中完成（排序保证时间有序，无需谓词过滤）。
   */
  private static async fetchPage(album: photoAccessHelper.Album, pageSize: number,
    offset: number): Promise<photoAccessHelper.PhotoAsset[]> {
    const pred = new dataSharePredicates.DataSharePredicates();
    pred.orderByDesc(photoAccessHelper.PhotoKeys.DATE_ADDED);
    pred.limit(pageSize, offset);
    const opts: photoAccessHelper.FetchOptions = {
      fetchColumns: PhotoAlbumService.FETCH_COLUMNS,
      predicates: pred
    };
    const res = await album.getAssets(opts);
    try {
      return await res.getAllObjects();
    } finally {
      res.close();
    }
  }

  // ============================================================
  // 条目构造
  // ============================================================

  private static num(asset: photoAccessHelper.PhotoAsset, key: string): number {
    try {
      const v = asset.get(key);
      if (typeof v === 'number') {
        return v;
      }
      if (typeof v === 'string' && v.length > 0) {
        return Number(v);
      }
      return 0;
    } catch (_e) {
      return 0;
    }
  }

  private static isSupportedType(asset: photoAccessHelper.PhotoAsset): boolean {
    return asset.photoType === photoAccessHelper.PhotoType.IMAGE
      || asset.photoType === photoAccessHelper.PhotoType.VIDEO;
  }

  private static baseName(uri: string): string {
    const idx = uri.lastIndexOf('/');
    return idx >= 0 ? uri.substring(idx + 1) : uri;
  }

  private static stripExt(name: string): string {
    const i = name.lastIndexOf('.');
    return i > 0 ? name.substring(0, i) : name;
  }

  private static compareEntries(a: PhotoSourceEntry, b: PhotoSourceEntry): number {
    if (a.orderMs !== b.orderMs) {
      return a.orderMs - b.orderMs;
    }
    return a.sourceUniqueId < b.sourceUniqueId ? -1 : (a.sourceUniqueId > b.sourceUniqueId ? 1 : 0);
  }

  /** cursor 过滤（对齐 Flutter：orderMs > cursor 或同级时 uniqueId 更大） */
  private static isPending(orderMs: number, uniqueId: string, cursor: PhotoBackupCursor): boolean {
    if (orderMs > cursor.lastCreatedAtMs) {
      return true;
    }
    if (orderMs < cursor.lastCreatedAtMs) {
      return false;
    }
    return uniqueId > cursor.lastUniqueId;
  }

  private static buildEntry(asset: photoAccessHelper.PhotoAsset, orderMs: number): PhotoSourceEntry | undefined {
    if (!PhotoAlbumService.isSupportedType(asset)) {
      return undefined;
    }
    const size = PhotoAlbumService.num(asset, photoAccessHelper.PhotoKeys.SIZE);
    if (size <= 0) {
      return undefined;
    }
    const name = asset.displayName.trim();
    const displayName = name.length > 0 ? name : PhotoAlbumService.baseName(asset.uri);
    const entry = new PhotoSourceEntry();
    entry.sourceUniqueId = asset.uri;
    entry.displayName = displayName;
    entry.localUri = asset.uri;
    entry.relativePath = displayName;
    entry.orderMs = orderMs;
    entry.size = size;
    entry.fileMtimeMs = PhotoAlbumService.num(asset, photoAccessHelper.PhotoKeys.DATE_MODIFIED) * 1000;
    return entry;
  }

  // ============================================================
  // 实况照片视频轨导出
  // ============================================================

  /**
   * 导出实况照片的视频轨到沙盒 cache 目录（对齐 Flutter originFileWithSubtype）。
   * 非实况照片或导出失败时抛错，由调用方跳过；文件用完由 maybeDeleteSandboxTempFile 清理。
   */
  static async exportLiveVideo(asset: photoAccessHelper.PhotoAsset): Promise<LiveVideoExport> {
    const ctx = WindowStore.appContext;
    if (!ctx) {
      throw new Error('photo_backup_context_missing');
    }
    const videoPath = `${ctx.cacheDir}/photo_backup_live_${Date.now()}_${Math.floor(Math.random() * 1000000)}.mov`;
    const file = fileIo.openSync(videoPath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    fileIo.closeSync(file);
    const videoFileUri = fileUri.getUriFromPath(videoPath);

    const handler = new MovingPhotoDataHandler();
    const reqPromise = photoAccessHelper.MediaAssetManager.requestMovingPhoto(ctx, asset,
      { deliveryMode: photoAccessHelper.DeliveryMode.FAST_MODE }, handler);
    const timeout = new Promise<photoAccessHelper.MovingPhoto>((_resolve, reject): void => {
      setTimeout((): void => {
        handler.fail(new Error('live_photo_export_timeout'));
      }, LIVE_EXPORT_TIMEOUT_MS);
    });
    try {
      await reqPromise;
      const moving = await Promise.race([handler.promise, timeout]);
      await moving.requestContent(photoAccessHelper.ResourceType.VIDEO_RESOURCE, videoFileUri);
    } catch (e) {
      try {
        fileIo.unlinkSync(videoPath);
      } catch (_ignored) {
      }
      throw e instanceof Error ? e : new Error(`${e}`);
    }
    const st = fileIo.statSync(videoPath);
    const out = new LiveVideoExport();
    out.path = videoPath;
    out.size = st.size;
    return out;
  }

  /**
   * 上传完成后清理沙盒临时文件（对齐 Flutter UploadTempFileCleaner.maybeDeleteSandboxTempFile）：
   * 仅删除应用 cache 目录下的文件；file://media 等媒体库 URI 直接跳过。
   */
  static async maybeDeleteSandboxTempFile(localUri: string): Promise<void> {
    try {
      const ctx = WindowStore.appContext;
      if (!ctx) {
        return;
      }
      const cachePrefix = `${ctx.cacheDir}/`;
      let path = localUri;
      if (path.startsWith('file://')) {
        // 应用沙盒 file:// uri 去掉 scheme 后即为路径；媒体库 uri（file://media/...）不匹配 cache 前缀自然跳过
        path = path.substring('file://'.length);
      }
      if (!path.startsWith(cachePrefix)) {
        return;
      }
      fileIo.unlinkSync(path);
    } catch (_e) {
      // 文件可能已被清理
    }
  }

  // ============================================================
  // 相册扫描（三种模式，对齐 Flutter _scanAlbum / _scanAlbumBatched / _scanAlbumPendingMeta）
  // ============================================================

  /** 相册不存在（对齐 Flutter Exception('photo_backup_album_not_found')） */
  private static albumNotFoundError(): Error {
    return new Error(L10n.t('photo_backup_album_not_found', '相册不存在或已被删除'));
  }

  /** 扫描前权限校验（对齐 Flutter 各 _scan 方法内的 _ensurePhotoPermission）：未授权时 toast 并抛出标记异常 */
  private static async ensureScanPermission(): Promise<void> {
    const hasPermission = await PhotoAlbumService.ensurePermission();
    if (!hasPermission) {
      throw new Error('photo_backup_permission_denied');
    }
  }

  /**
   * 全量扫描（对齐 Flutter _scanAlbum）：页 200，返回按 orderMs+uniqueId 升序的全部条目。
   * uploadLivePhotoVideo 时为实况照片追加视频轨条目。
   */
  static async scanAlbum(task: PhotoBackupTask): Promise<PhotoSourceEntry[]> {
    await PhotoAlbumService.ensureScanPermission();
    const album = await PhotoAlbumService.findAlbum(task.sourceId);
    if (album === undefined) {
      throw PhotoAlbumService.albumNotFoundError();
    }
    const out: PhotoSourceEntry[] = [];
    let offset = 0;
    while (true) {
      const list = await PhotoAlbumService.fetchPage(album, SCAN_PAGE_SIZE, offset);
      if (list.length === 0) {
        break;
      }
      for (const asset of list) {
        const orderMs = PhotoAlbumService.num(asset, photoAccessHelper.PhotoKeys.DATE_ADDED) * 1000;
        const entry = PhotoAlbumService.buildEntry(asset, orderMs);
        if (entry === undefined) {
          continue;
        }
        out.push(entry);
        if (!task.uploadLivePhotoVideo) {
          continue;
        }
        if (PhotoAlbumService.num(asset, photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE)
          !== photoAccessHelper.PhotoSubtype.MOVING_PHOTO) {
          continue;
        }
        try {
          const live = await PhotoAlbumService.exportLiveVideo(asset);
          if (live.size <= 0) {
            continue;
          }
          const lvName = `${PhotoAlbumService.stripExt(entry.displayName)}.MOV`;
          const lvEntry = new PhotoSourceEntry();
          lvEntry.sourceUniqueId = `${asset.uri}#live`;
          lvEntry.displayName = lvName;
          lvEntry.localUri = live.path;
          lvEntry.relativePath = lvName;
          lvEntry.orderMs = orderMs;
          lvEntry.size = live.size;
          lvEntry.fileMtimeMs = entry.fileMtimeMs;
          out.push(lvEntry);
        } catch (_e) {
          // 非实况或导出失败：跳过视频轨
        }
      }
      if (list.length < SCAN_PAGE_SIZE) {
        break;
      }
      offset += SCAN_PAGE_SIZE;
    }
    out.sort(PhotoAlbumService.compareEntries);
    return out;
  }

  /**
   * 流式扫描（对齐 Flutter _scanAlbumBatched）：页 80，逐批回调，立即开始上传；
   * onBatch 返回 false 或抛错均中断扫描（失败/取消即停）。cursor 非空时在扫描侧过滤。
   */
  static async scanAlbumBatched(task: PhotoBackupTask, cursor: PhotoBackupCursor | undefined,
    onBatch: (batch: PhotoSourceEntry[]) => Promise<boolean>): Promise<void> {
    await PhotoAlbumService.ensureScanPermission();
    const album = await PhotoAlbumService.findAlbum(task.sourceId);
    if (album === undefined) {
      throw PhotoAlbumService.albumNotFoundError();
    }
    let offset = 0;
    while (true) {
      const list = await PhotoAlbumService.fetchPage(album, STREAM_PAGE_SIZE, offset);
      if (list.length === 0) {
        break;
      }
      const batch: PhotoSourceEntry[] = [];
      for (const asset of list) {
        const orderMs = PhotoAlbumService.num(asset, photoAccessHelper.PhotoKeys.DATE_ADDED) * 1000;
        const entry = PhotoAlbumService.buildEntry(asset, orderMs);
        if (entry !== undefined && (cursor === undefined || PhotoAlbumService.isPending(orderMs,
          entry.sourceUniqueId, cursor))) {
          batch.push(entry);
        }
        if (!task.uploadLivePhotoVideo) {
          continue;
        }
        if (PhotoAlbumService.num(asset, photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE)
          !== photoAccessHelper.PhotoSubtype.MOVING_PHOTO) {
          continue;
        }
        try {
          const live = await PhotoAlbumService.exportLiveVideo(asset);
          if (live.size <= 0) {
            continue;
          }
          const baseName = entry !== undefined ? entry.displayName
            : PhotoAlbumService.stripExt(PhotoAlbumService.baseName(asset.uri));
          const lvName = `${PhotoAlbumService.stripExt(baseName)}.MOV`;
          const lvEntry = new PhotoSourceEntry();
          lvEntry.sourceUniqueId = `${asset.uri}#live`;
          lvEntry.displayName = lvName;
          lvEntry.localUri = live.path;
          lvEntry.relativePath = lvName;
          lvEntry.orderMs = orderMs;
          lvEntry.size = live.size;
          lvEntry.fileMtimeMs = entry !== undefined ? entry.fileMtimeMs
            : PhotoAlbumService.num(asset, photoAccessHelper.PhotoKeys.DATE_MODIFIED) * 1000;
          if (cursor === undefined || PhotoAlbumService.isPending(orderMs, lvEntry.sourceUniqueId, cursor)) {
            batch.push(lvEntry);
          }
        } catch (_e) {
          // 非实况或导出失败：跳过视频轨
        }
      }
      if (batch.length > 0) {
        batch.sort(PhotoAlbumService.compareEntries);
        const keepGoing = await onBatch(batch);
        if (!keepGoing) {
          return;
        }
      }
      if (list.length < STREAM_PAGE_SIZE) {
        break;
      }
      offset += STREAM_PAGE_SIZE;
    }
  }

  /**
   * 上传新增 Meta 扫描（对齐 Flutter _scanAlbumPendingMeta）：只拉「创建时间 ≥ cursor」的资源列表，
   * 不解析文件内容，上传时再按需 resolve；返回按 orderMs+uniqueId 升序的 Meta 列表。
   */
  static async scanAlbumPendingMeta(task: PhotoBackupTask,
    cursor: PhotoBackupCursor): Promise<PhotoAlbumAssetMeta[]> {
    await PhotoAlbumService.ensureScanPermission();
    const album = await PhotoAlbumService.findAlbum(task.sourceId);
    if (album === undefined) {
      throw PhotoAlbumService.albumNotFoundError();
    }
    const pendingMeta: PhotoAlbumAssetMeta[] = [];
    let offset = 0;
    while (true) {
      const list = await PhotoAlbumService.fetchPage(album, META_PAGE_SIZE, offset);
      if (list.length === 0) {
        break;
      }
      for (const asset of list) {
        if (!PhotoAlbumService.isSupportedType(asset)) {
          continue;
        }
        const orderMs = PhotoAlbumService.num(asset, photoAccessHelper.PhotoKeys.DATE_ADDED) * 1000;
        if (!PhotoAlbumService.isPending(orderMs, asset.uri, cursor)) {
          continue;
        }
        pendingMeta.push(new PhotoAlbumAssetMeta(asset, orderMs));
      }
      if (list.length < META_PAGE_SIZE) {
        break;
      }
      offset += META_PAGE_SIZE;
    }
    pendingMeta.sort((a: PhotoAlbumAssetMeta, b: PhotoAlbumAssetMeta): number => {
      if (a.orderMs !== b.orderMs) {
        return a.orderMs - b.orderMs;
      }
      return a.asset.uri < b.asset.uri ? -1 : (a.asset.uri > b.asset.uri ? 1 : 0);
    });
    return pendingMeta;
  }

  /**
   * 上传该条相册资源时再解析（对齐 Flutter _resolveAlbumMetaToEntries）：
   * 取主图条目 + 可选实况视频轨条目。主图不可用（size<=0）返回空。
   */
  static async resolveAlbumMetaToEntries(meta: PhotoAlbumAssetMeta,
    task: PhotoBackupTask): Promise<PhotoSourceEntry[]> {
    const asset = meta.asset;
    const entry = PhotoAlbumService.buildEntry(asset, meta.orderMs);
    if (entry === undefined) {
      return [];
    }
    const entries: PhotoSourceEntry[] = [entry];
    if (!task.uploadLivePhotoVideo) {
      return entries;
    }
    if (PhotoAlbumService.num(asset, photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE)
      !== photoAccessHelper.PhotoSubtype.MOVING_PHOTO) {
      return entries;
    }
    try {
      const live = await PhotoAlbumService.exportLiveVideo(asset);
      if (live.size <= 0) {
        return entries;
      }
      const lvName = `${PhotoAlbumService.stripExt(entry.displayName)}.MOV`;
      const lvEntry = new PhotoSourceEntry();
      lvEntry.sourceUniqueId = `${asset.uri}#live`;
      lvEntry.displayName = lvName;
      lvEntry.localUri = live.path;
      lvEntry.relativePath = lvName;
      lvEntry.orderMs = meta.orderMs;
      lvEntry.size = live.size;
      lvEntry.fileMtimeMs = entry.fileMtimeMs;
      entries.push(lvEntry);
    } catch (_e) {
      // 非实况或导出失败：仅上传主图
    }
    return entries;
  }

  // ============================================================
  // 文件夹扫描（对齐 Flutter _scanFolder；鸿蒙表单不提供文件夹来源，兜底支持历史任务）
  // ============================================================

  /** 递归扫描文件夹，返回按 mtime+path 升序的条目（过滤系统垃圾文件与空文件） */
  static async scanFolder(root: string): Promise<PhotoSourceEntry[]> {
    const trimmed = root.trim();
    const out: PhotoSourceEntry[] = [];
    if (trimmed.length === 0) {
      return out;
    }
    try {
      if (!fileIo.accessSync(trimmed)) {
        return out;
      }
    } catch (_e) {
      return out;
    }
    await PhotoAlbumService.walkFolder(trimmed, trimmed, out);
    out.sort(PhotoAlbumService.compareEntries);
    return out;
  }

  private static async walkFolder(root: string, dir: string, out: PhotoSourceEntry[]): Promise<void> {
    let names: string[] = [];
    try {
      names = fileIo.listFileSync(dir);
    } catch (_e) {
      return;
    }
    for (const name of names) {
      const full = dir.endsWith('/') ? `${dir}${name}` : `${dir}/${name}`;
      let st: fileIo.Stat;
      try {
        st = fileIo.statSync(full);
      } catch (_e) {
        continue;
      }
      if (st.isDirectory()) {
        await PhotoAlbumService.walkFolder(root, full, out);
        continue;
      }
      if (st.size <= 0) {
        continue;
      }
      if (UploadTransferHelper.shouldIgnore(name)) {
        continue;
      }
      const rel = full.startsWith(`${root}/`) ? full.slice(root.length + 1) : name;
      const orderMs = st.mtime * 1000;
      const entry = new PhotoSourceEntry();
      entry.sourceUniqueId = rel;
      entry.displayName = name;
      entry.localUri = full;
      entry.relativePath = rel;
      entry.orderMs = orderMs;
      entry.size = st.size;
      entry.fileMtimeMs = orderMs;
      out.push(entry);
    }
  }
}
