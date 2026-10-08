import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { AppRouter } from '../../../router/AppRouter';
import { NavUtil } from '../../../common/NavUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { DialogUtil } from '../../../common/DialogUtil';
import { L10n } from '../../../core/localization/L10n';
import { FileItem, FileModelAccess, FileSuffixes } from '../models/FileModels';
import { GalleryItem, GalleryPageParam } from '../../gallery/models/GalleryModels';
import { PlayerPlaylistItem } from '../../video_player/models/PlayerModels';
import { openVideoPlayer } from '../../video_player/views/PlayerNavigator';
import { BookLocalCacheService } from '../../book/services/BookLocalCacheService';
import { BookScopedTokenApiService } from '../../book/services/BookApiServices';
import { BookTxtReaderParam, BookWebReaderParam } from '../../book/router/BookRoutes';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'FileOpener';
/** Web 阅读器支持的电子书后缀（pdf 走 foliate 内置 pdf.js） */
const WEB_READER_EXTS: string[] = ['.pdf', '.epub', '.mobi', '.azw3'];

/**
 * 文件打开分发器（对齐 Flutter file_controller parts/open.dart handleItemTap）：
 * 图片/raw → gallery 图片浏览器；视频 → video_player 播放页；
 * txt → book TXT 阅读器（先本地缓存）；pdf/epub/mobi/azw3 → book Web 阅读器（scoped token）；
 * 其余类型（文本编辑器/Office/压缩包预览等鸿蒙端未迁移）提示敬请期待。
 */
export class FileOpener {
  /** 点击文件条目时按类型分发；allItems 为当前展示列表（图片/视频用于构建同屏滑动/连播列表） */
  static openFileItem(item: FileItem, allItems: FileItem[]): void {
    const type = FileModelAccess.type(item);
    const ext = FileOpener.extOf(item);
    if (type === 'image' || type === 'raw' || FileSuffixes.isImage(item)) {
      FileOpener.openGallery(item, allItems);
      return;
    }
    if (type === 'video' || FileSuffixes.isVideo(item)) {
      FileOpener.openVideoPlaylist(item, allItems);
      return;
    }
    if (ext === '.txt') {
      void FileOpener.openTxtReader(item);
      return;
    }
    if (WEB_READER_EXTS.includes(ext)) {
      void FileOpener.openWebReader(item);
      return;
    }
    // md/代码文本（文本编辑器）、docx/xlsx（Office 预览）、zip/rar（压缩包预览）等暂未迁移
    ToastUtil.show(L10n.featureComingSoon);
  }

  // ==================== 图片 → gallery ====================

  /** 图片列表 → GalleryPageParam（同目录图片可左右滑动，对齐 Flutter images.indexOf） */
  private static openGallery(item: FileItem, allItems: FileItem[]): void {
    const images = allItems.filter((e: FileItem): boolean => {
      const t = FileModelAccess.type(e);
      return t === 'image' || t === 'raw' || FileSuffixes.isImage(e);
    });
    const list = images.length > 0 ? images : [item];
    const targetPath = FileModelAccess.path(item);
    let initialIndex = list.findIndex((e: FileItem): boolean => FileModelAccess.path(e) === targetPath);
    if (initialIndex < 0) {
      initialIndex = 0;
    }
    const galleryItems: GalleryItem[] = list.map((e: FileItem): GalleryItem => {
      const gi = new GalleryItem();
      gi.type = FileModelAccess.type(e) === 'raw' ? 'raw' : 'image';
      gi.path = FileModelAccess.path(e);
      gi.name = FileModelAccess.fileName(e);
      // photoId 保持 0：GalleryController 按文件路径走 rawFile URL / 文件删除分支
      return gi;
    });
    const param = new GalleryPageParam();
    param.items = galleryItems;
    param.initialIndex = initialIndex;
    param.showInfo = true;
    NavUtil.push(AppRouter.PHOTO_GALLERY, param);
  }

  // ==================== 视频 → video_player ====================

  /** 视频列表 → 播放器播放列表（连播，ignoreFindSub=1 与 Flutter 文件浏览默认一致） */
  private static openVideoPlaylist(item: FileItem, allItems: FileItem[]): void {
    const videos = allItems.filter((e: FileItem): boolean => {
      const t = FileModelAccess.type(e);
      return t === 'video' || FileSuffixes.isVideo(e);
    });
    const list = videos.length > 0 ? videos : [item];
    const targetPath = FileModelAccess.path(item);
    let initialIndex = list.findIndex((e: FileItem): boolean => FileModelAccess.path(e) === targetPath);
    if (initialIndex < 0) {
      initialIndex = 0;
    }
    const playlist: PlayerPlaylistItem[] = list.map((e: FileItem): PlayerPlaylistItem => {
      const pi = new PlayerPlaylistItem();
      pi.path = FileModelAccess.path(e);
      pi.name = FileModelAccess.fileName(e);
      return pi;
    }).filter((pi: PlayerPlaylistItem): boolean => pi.path.trim().length > 0);
    if (playlist.length === 0) {
      ToastUtil.show(L10n.operationFailed);
      return;
    }
    if (initialIndex >= playlist.length) {
      initialIndex = 0;
    }
    openVideoPlayer(playlist, initialIndex, 1);
  }

  // ==================== TXT → book TXT 阅读器 ====================

  /**
   * TXT：先经 BookLocalCacheService 下载到本地缓存再打开分页阅读器
   * （对齐 Flutter _openTxtReaderFromItem；无 fileHash 时用路径 MD5 作为缓存键）。
   */
  private static async openTxtReader(item: FileItem): Promise<void> {
    const filePath = FileModelAccess.path(item).trim();
    if (filePath.length === 0) {
      ToastUtil.show(L10n.operationFailed);
      return;
    }
    const title = FileOpener.titleOf(item, filePath);
    const filename = FileOpener.basename(filePath);
    try {
      const fileHash = await FileOpener.resolveCacheHash(item, filePath);
      DialogUtil.showLoading(L10n.t('loading'));
      const ok = await BookLocalCacheService.getInstance()
        .ensureCached(fileHash, filename.length > 0 ? filename : title, filePath);
      DialogUtil.dismissLoading(true);
      if (!ok) {
        ToastUtil.show(L10n.networkFailure);
        return;
      }
      const localPath = BookLocalCacheService.getInstance().cachedFilePathOf(fileHash);
      if (localPath === undefined) {
        ToastUtil.show(L10n.networkFailure);
        return;
      }
      const param = new BookTxtReaderParam();
      param.title = title;
      param.fileHash = fileHash;
      param.localFilePath = localPath;
      NavUtil.push(AppRouter.BOOK_TXT_READER, param);
    } catch (e) {
      hilog.error(0x0000, TAG, 'openTxtReader failed: %{public}s', JSON.stringify(e));
      DialogUtil.dismissLoading(true);
      ToastUtil.show(L10n.networkFailure);
    }
  }

  // ==================== pdf/epub/mobi/azw3 → book Web 阅读器 ====================

  /**
   * pdf/epub/mobi/azw3：创建 scoped token（阅读器上报进度用），有 fileHash 时先本地缓存，
   * 再打开 foliate Web 阅读器（pdf 经内置 pdf.js 渲染）。
   */
  private static async openWebReader(item: FileItem): Promise<void> {
    const filePath = FileModelAccess.path(item).trim();
    if (filePath.length === 0) {
      ToastUtil.show(L10n.operationFailed);
      return;
    }
    const title = FileOpener.titleOf(item, filePath);
    const filename = FileOpener.basename(filePath);
    const fileHash = (item.fileHash ?? '').trim();
    try {
      DialogUtil.showLoading(L10n.t('loading'));
      let localPath = '';
      if (fileHash.length > 0) {
        const cached = await BookLocalCacheService.getInstance()
          .ensureCached(fileHash, filename, filePath);
        if (!cached) {
          DialogUtil.dismissLoading(true);
          ToastUtil.show(L10n.networkFailure);
          return;
        }
        const local = BookLocalCacheService.getInstance().cachedFilePathOf(fileHash);
        localPath = local !== undefined ? local : '';
      }
      const scopedToken = await BookScopedTokenApiService.createScopedToken(filePath);
      DialogUtil.dismissLoading(true);
      if (scopedToken.length === 0) {
        ToastUtil.show(L10n.networkFailure);
        return;
      }
      const param = new BookWebReaderParam();
      param.title = title;
      param.fileHash = fileHash;
      param.filePath = filePath;
      param.filename = filename;
      param.localPath = localPath;
      param.url = scopedToken;
      NavUtil.push(AppRouter.BOOK_WEB_READER, param);
    } catch (e) {
      hilog.error(0x0000, TAG, 'openWebReader failed: %{public}s', JSON.stringify(e));
      DialogUtil.dismissLoading(true);
      ToastUtil.show(L10n.networkFailure);
    }
  }

  // ==================== helpers ====================

  /** 缓存键：优先条目自带 fileHash，否则取路径 MD5（与 Flutter md5(path) 兜底一致，仅作本地缓存键） */
  private static async resolveCacheHash(item: FileItem, filePath: string): Promise<string> {
    const h = (item.fileHash ?? '').trim();
    if (h.length > 0) {
      return h;
    }
    return FileOpener.md5Hex(filePath);
  }

  /** 后缀（带点、小写）；ext 字段缺省时从文件名推导 */
  private static extOf(item: FileItem): string {
    let ext = FileModelAccess.ext(item).trim().toLowerCase();
    if (ext.length > 0) {
      return ext.startsWith('.') ? ext : `.${ext}`;
    }
    const name = FileModelAccess.fileName(item);
    const dot = name.lastIndexOf('.');
    if (dot >= 0 && dot < name.length - 1) {
      return name.substring(dot).toLowerCase();
    }
    return '';
  }

  private static basename(path: string): string {
    const p = path.trim();
    if (p.length === 0) {
      return '';
    }
    const idx = p.lastIndexOf('/');
    return idx >= 0 ? p.substring(idx + 1) : p;
  }

  private static titleOf(item: FileItem, filePath: string): string {
    const name = FileModelAccess.fileName(item).trim();
    return name.length > 0 ? name : FileOpener.basename(filePath);
  }

  /** 字符串 MD5 十六进制（cryptoFramework，与 Flutter md5.convert 一致）；失败返回空串 */
  private static async md5Hex(input: string): Promise<string> {
    try {
      const md = cryptoFramework.createMd('MD5');
      const bytes = new util.TextEncoder().encodeInto(input);
      await md.update({ data: bytes });
      const digest = await md.digest();
      let hex = '';
      const data = digest.data;
      for (let i = 0; i < data.length; i++) {
        const b = data[i];
        hex += (b < 16 ? '0' : '') + b.toString(16);
      }
      return hex;
    } catch (e) {
      hilog.error(0x0000, TAG, 'md5Hex failed: %{public}s', JSON.stringify(e));
      return '';
    }
  }
}
