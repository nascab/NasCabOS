import { http } from '@kit.NetworkKit';
import { picker } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ApiUrls } from '../../core/network/ApiUrls';
import { APIClient } from '../../core/network/APIClient';
import { L10n } from '../../core/localization/L10n';
import { AppImageLoader } from '../../common/components/AppImage';
import { DialogUtil } from '../../common/DialogUtil';
import { ToastUtil } from '../../common/ToastUtil';
import { FileApiService } from '../../files/service/FileApiService';
import { PhotoTimelineApiService } from '../../photo/service/PhotoTimelineApiService';
import { TimelineDetectedFaceItem } from '../../photo/models/PhotoModels';
import { GalleryItem, GalleryPageParam } from '../models/GalleryModels';

const TAG = 'GalleryController';
/** 全景图宽高比判定范围（对齐 Flutter _panoramaMin/MaxAspectRatio） */
const PANORAMA_MIN_RATIO = 1.8;
const PANORAMA_MAX_RATIO = 2.2;
/** 自动播放切换间隔（对齐 Flutter autoPlayInterval） */
const AUTO_PLAY_INTERVAL_MS = 3000;

/** 规范化服务器路径：反斜杠→斜杠、合并多斜杠、去尾斜杠（对齐 Flutter _normalizeServerPath） */
function normalizeServerPath(v: string): string {
  let x = v.trim();
  if (x.length === 0) {
    return x;
  }
  x = x.replace(/\\/g, '/').replace(/\/+/g, '/');
  while (x.length > 1 && x.endsWith('/')) {
    x = x.substring(0, x.length - 1);
  }
  return x;
}

function isUrl(v: string): boolean {
  return v.startsWith('http://') || v.startsWith('https://');
}

function serverDirname(v: string): string {
  const x = normalizeServerPath(v);
  const i = x.lastIndexOf('/');
  if (i <= 0) {
    return '';
  }
  return x.substring(0, i);
}

function serverJoin(dir: string, name: string): string {
  const d = normalizeServerPath(dir);
  const n = name.trim().replace(/\\/g, '/');
  if (d.length === 0) {
    return normalizeServerPath(n);
  }
  if (n.length === 0) {
    return d;
  }
  return normalizeServerPath(`${d}/${n}`);
}

function baseName(v: string): string {
  const clean = v.split('?')[0];
  const i = clean.lastIndexOf('/');
  return i >= 0 && i < clean.length - 1 ? clean.substring(i + 1) : clean;
}

function asNum(v: Object | undefined | null): number {
  if (v === undefined || v === null) {
    return 0;
  }
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

function asStr(v: Object | undefined | null): string {
  if (v === undefined || v === null) {
    return '';
  }
  return `${v}`;
}

/**
 * 图片浏览器控制器（对齐 Flutter CustomGalleryController）。
 * 页面通过 attachPage/gotoPage 回调驱动 Swiper 翻页，onPageChanged 回报当前页。
 */
@ObservedV2
export class GalleryController {
  @Trace items: GalleryItem[] = [];
  @Trace currentIndex: number = 0;
  @Trace isControlsVisible: boolean = true;
  @Trace isAutoPlaying: boolean = false;
  @Trace isInfoPanelVisible: boolean = false;
  @Trace infoLoading: boolean = false;
  @Trace infoErrorText: string = '';
  @Trace infoData: Record<string, Object> | undefined = undefined;
  /** 当前页内播放 Live Photo 的索引（-1 表示未播放；切页自动停止） */
  @Trace livePlayingIndex: number = -1;
  @Trace showInfoButton: boolean = true;
  /** 每页旋转次数（quarter turns）与缩放比例 */
  @Trace rotations: Map<number, number> = new Map();
  @Trace scales: Map<number, number> = new Map();
  @Trace panoramaCandidates: Map<number, boolean> = new Map();

  private page: GalleryPageParam = new GalleryPageParam();
  private autoPlayTimer: number = -1;
  private propertiesSeq: number = 0;
  private lastInfoPath: string = '';
  private panoramaInFlight: Set<number> = new Set();
  /** 页面注入：翻页执行器（SwiperController.changeIndex）与关闭回调 */
  gotoPage: (index: number) => void = (_i: number): void => {
  };
  closePage: () => void = (): void => {
  };

  get isLivePhotoPlaying(): boolean {
    return this.livePlayingIndex >= 0;
  }

  get currentIsLivePhoto(): boolean {
    const it = this.currentItem();
    return it !== undefined && it.liveVideoUrl.length > 0;
  }

  currentItem(): GalleryItem | undefined {
    return this.currentIndex >= 0 && this.currentIndex < this.items.length
      ? this.items[this.currentIndex] : undefined;
  }

  // ================= 配置与 URL 构建 =================

  /** 配置并构建图片 URL（对齐 Flutter galleryItems setter + configure） */
  async configure(param: GalleryPageParam): Promise<void> {
    this.page = param;
    this.showInfoButton = param.showInfo;
    if (!param.showInfo) {
      this.isInfoPanelVisible = false;
    }
    this.panoramaCandidates = new Map();
    this.panoramaInFlight.clear();
    const items: GalleryItem[] = [];
    for (const src of param.items) {
      const it = new GalleryItem();
      it.type = src.type;
      it.path = src.path;
      it.name = src.name;
      it.photoId = src.photoId;
      it.width = src.width;
      it.height = src.height;
      it.isLvp = src.isLvp;
      it.isMergeLvp = src.isMergeLvp;
      it.liveFilename = src.liveFilename;
      it.rawFilename = src.rawFilename;
      it.fileHash = src.fileHash;
      it.url = src.url.length > 0 ? src.url : (isUrl(src.path) ? src.path : await ApiUrls.getRawFileUrl(src.path));
      it.liveVideoUrl = await this.buildLiveVideoUrl(it);
      items.push(it);
    }
    this.items = items;
    this.currentIndex = Math.min(Math.max(param.initialIndex, 0), Math.max(items.length - 1, 0));
    this.isControlsVisible = true;
    this.livePlayingIndex = -1;
    this.preloadAdjacent(this.currentIndex);
  }

  /** Live Photo 视频地址：合并式走提取接口，分离式拼同目录 liveFilename（对齐 Flutter getLiveVideoUrlForItem） */
  private async buildLiveVideoUrl(item: GalleryItem): Promise<string> {
    if (item.isLvp !== 1) {
      return '';
    }
    if (item.isMergeLvp === 1) {
      return item.path.trim().length > 0 ? ApiUrls.getMergeLvpVideoUrl(item.path.trim()) : '';
    }
    const liveFilename = item.liveFilename.trim();
    const photoPath = item.path.trim();
    if (liveFilename.length === 0 || photoPath.length === 0) {
      return '';
    }
    const livePath = serverJoin(serverDirname(photoPath), liveFilename);
    if (livePath.length === 0) {
      return '';
    }
    return ApiUrls.getRawFileUrl(livePath);
  }

  // ================= 页内 Live Photo 播放 =================

  startLivePlayback(index: number): void {
    if (index < 0 || index >= this.items.length) {
      return;
    }
    if (this.livePlayingIndex === index) {
      return;
    }
    this.livePlayingIndex = index;
  }

  stopLivePlayback(): void {
    this.livePlayingIndex = -1;
  }

  // ================= 页面事件 =================

  /** Swiper 翻页回调（对齐 Flutter _onPageControllerTick） */
  onPageChanged(idx: number): void {
    if (idx === this.currentIndex) {
      return;
    }
    this.currentIndex = idx;
    if (this.isLivePhotoPlaying && this.livePlayingIndex !== idx) {
      this.stopLivePlayback();
    }
    this.preloadAdjacent(idx);
    if (this.isInfoPanelVisible) {
      void this.fetchCurrentImageInfo(false);
    }
  }

  private preloadAdjacent(idx: number): void {
    void this.ensurePanoramaCandidate(idx);
    const next = this.items[idx + 1];
    if (next !== undefined && next.url.length > 0) {
      AppImageLoader.load(next.url).catch((_e: Object): void => {
      });
    }
    const prev = this.items[idx - 1];
    if (prev !== undefined && prev.url.length > 0) {
      AppImageLoader.load(prev.url).catch((_e: Object): void => {
      });
    }
  }

  // ================= 旋转/缩放 =================

  rotateLeft(index: number): void {
    this.rotations.set(index, (this.rotations.get(index) ?? 0) - 1);
  }

  rotateRight(index: number): void {
    this.rotations.set(index, (this.rotations.get(index) ?? 0) + 1);
  }

  getRotation(index: number): number {
    return this.rotations.get(index) ?? 0;
  }

  getScale(index: number): number {
    return this.scales.get(index) ?? 1.0;
  }

  setScale(index: number, scale: number): void {
    this.scales.set(index, scale);
  }

  toggleControls(): void {
    this.isControlsVisible = !this.isControlsVisible;
  }

  // ================= 信息面板 =================

  toggleInfoPanel(): void {
    this.isInfoPanelVisible = !this.isInfoPanelVisible;
    if (this.isInfoPanelVisible) {
      void this.fetchCurrentImageInfo(true);
    }
  }

  private isServerVersionAtLeast(min: number): boolean {
    const version = APIClient.getInstance().state.serverVersion ?? '';
    const m = /(\d+)/.exec(version);
    if (m === null) {
      return true;
    }
    return Number(m[1]) >= min;
  }

  /** 获取当前图属性 + 人脸（seq 防竞态，对齐 Flutter fetchCurrentImageInfo） */
  async fetchCurrentImageInfo(force: boolean): Promise<void> {
    const item = this.currentItem();
    if (item === undefined) {
      return;
    }
    const normalized = normalizeServerPath(item.path);
    if (normalized.length === 0 || isUrl(normalized)) {
      this.infoData = undefined;
      this.infoErrorText = '';
      this.infoLoading = false;
      this.lastInfoPath = '';
      return;
    }
    if (!force && this.lastInfoPath === normalized && this.infoData !== undefined) {
      return;
    }
    this.lastInfoPath = normalized;
    const seq = ++this.propertiesSeq;
    this.infoLoading = true;
    this.infoErrorText = '';
    if (force) {
      this.infoData = undefined;
    }
    try {
      const res = await new PhotoTimelineApiService().getPhotoProperties(normalized);
      if (seq !== this.propertiesSeq) {
        return;
      }
      if (!res.success) {
        this.infoData = undefined;
        this.infoErrorText = res.message ?? L10n.t('operation_failed', '操作失败');
        return;
      }
      const data: Record<string, Object> = res.data ?? {};
      const itemFileHash = item.fileHash.trim();
      const photoIndex = data['photoIndex'] as Record<string, Object> | undefined;
      const infoFileHash = asStr(photoIndex?.['fileHash']).trim() || itemFileHash;
      if (infoFileHash.length > 0 && this.isServerVersionAtLeast(4)) {
        try {
          const facesRes = await new PhotoTimelineApiService().listPhotoFaces(infoFileHash);
          if (seq !== this.propertiesSeq) {
            return;
          }
          if (facesRes.success && facesRes.data !== undefined) {
            data['photoFaces'] = facesRes.data;
          }
        } catch (_e) {
          // 人脸获取失败不阻塞基础信息展示
        }
      }
      this.infoData = data;
      this.infoErrorText = '';
    } catch (_e) {
      if (seq !== this.propertiesSeq) {
        return;
      }
      this.infoData = undefined;
      this.infoErrorText = L10n.t('operation_failed', '操作失败');
    } finally {
      if (seq === this.propertiesSeq) {
        this.infoLoading = false;
      }
    }
  }

  infoFaces(): TimelineDetectedFaceItem[] {
    const arr = this.infoData?.['photoFaces'];
    return Array.isArray(arr) ? arr as TimelineDetectedFaceItem[] : [];
  }

  // ================= 全景检测 =================

  isPanoramaCandidate(index: number): boolean {
    return this.panoramaCandidates.get(index) ?? false;
  }

  async ensurePanoramaCandidate(index: number): Promise<void> {
    if (index < 0 || index >= this.items.length) {
      return;
    }
    if (this.panoramaCandidates.has(index) || this.panoramaInFlight.has(index)) {
      return;
    }
    this.panoramaInFlight.add(index);
    try {
      const item = this.items[index];
      let candidate = matchesPanoramaRatio(item.width, item.height);
      if (!candidate) {
        const pm = await AppImageLoader.load(item.url);
        const info = await pm.getImageInfo();
        candidate = matchesPanoramaRatio(info.size.width, info.size.height);
      }
      this.panoramaCandidates.set(index, candidate);
    } catch (_e) {
      this.panoramaCandidates.set(index, false);
    } finally {
      this.panoramaInFlight.delete(index);
    }
  }

  // ================= 删除 =================

  private removeItemAndFixPage(removedIndex: number): void {
    if (removedIndex < 0 || removedIndex >= this.items.length) {
      return;
    }
    const next: GalleryItem[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (i !== removedIndex) {
        next.push(this.items[i]);
      }
    }
    this.items = next;
    if (next.length === 0) {
      this.closePage();
      return;
    }
    const safeIndex = removedIndex >= next.length ? next.length - 1 : removedIndex;
    this.currentIndex = safeIndex;
    this.gotoPage(safeIndex);
  }

  async deleteCurrentImage(): Promise<void> {
    const item = this.currentItem();
    if (item === undefined) {
      return;
    }
    const idx = this.currentIndex;

    // 照片库条目：放入照片回收站
    if (item.photoId > 0) {
      try {
        const res = await new PhotoTimelineApiService().batchTrash([item.photoId]);
        if (!res.success) {
          ToastUtil.show(res.code === 403
            ? L10n.t('permission_denied', '权限被拒绝')
            : L10n.t('operation_failed', '操作失败'));
          return;
        }
        if (this.page.onDeleted !== undefined) {
          this.page.onDeleted(item.photoId);
        }
        this.removeItemAndFixPage(idx);
        ToastUtil.show(L10n.t('photo_trashed_success', '已放入照片回收站'));
      } catch (_e) {
        ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      }
      return;
    }

    // 文件条目：文件管理删除（shell 支持时三按钮，否则确认后直接删）
    const path = normalizeServerPath(item.path);
    if (path.length === 0 || isUrl(path)) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      return;
    }
    const shellSupported = APIClient.getInstance().state.shellSupported;
    const title = L10n.t('need_confirm', '需要确认');
    const content = L10n.t('folder_delete_confirm', '确定删除@fileCount个项目吗？',
      L10n.paramsOf('fileCount', '1'));
    if (shellSupported) {
      await DialogUtil.showConfirmThreeButtonsDialog(title, content,
        async (): Promise<void> => {
          await this.deleteFileByPath(path, idx, false);
        },
        async (): Promise<void> => {
          await this.deleteFileByPath(path, idx, true);
        },
        L10n.t('cancel', '取消'), L10n.t('delete', '删除'),
        L10n.t('put_in_recycle_bin', '放入回收站'));
    } else {
      const confirmed = await DialogUtil.showConfirmDialog(title, content,
        undefined, L10n.t('ok', '确定'), L10n.t('cancel', '取消'));
      if (confirmed !== true) {
        return;
      }
      await this.deleteFileByPath(path, idx, false);
    }
  }

  private async deleteFileByPath(path: string, idx: number, recycle: boolean): Promise<void> {
    const res = await new FileApiService().deleteEntries([path], recycle);
    if (!res.success) {
      await DialogUtil.showErrorDialog(res.message ?? L10n.t('operation_failed', '操作失败'));
      return;
    }
    this.removeItemAndFixPage(idx);
    ToastUtil.show(L10n.t('delete_success', '删除成功'));
  }

  // ================= 下载 =================

  /** 下载当前图片（对齐 Flutter downloadCurrentImage：live/raw 附件一并保存） */
  async downloadCurrentImage(): Promise<void> {
    const item = this.currentItem();
    if (item === undefined) {
      return;
    }
    const path = item.path.trim();
    if (path.length === 0 || item.url.length === 0) {
      return;
    }
    const wanted: string[] = [path];
    if (item.photoId > 0 && path.length > 0 && !isUrl(path)) {
      const dir = serverDirname(path);
      if (item.liveFilename.trim().length > 0) {
        wanted.push(serverJoin(dir, item.liveFilename.trim()));
      }
      if (item.rawFilename.trim().length > 0) {
        wanted.push(serverJoin(dir, item.rawFilename.trim()));
      }
    }

    try {
      const docPicker = new picker.DocumentViewPicker();
      const opts = new picker.DocumentSaveOptions();
      opts.newFileNames = wanted.map((w: string): string => baseName(w));
      const uris = await docPicker.save(opts);
      if (uris === undefined || uris.length === 0) {
        return;
      }
      DialogUtil.showLoading(L10n.t('downloading', '下载中...'));
      try {
        for (let i = 0; i < uris.length && i < wanted.length; i++) {
          const url = await ApiUrls.getRawFileUrl(wanted[i]);
          const buf = await GalleryController.downloadBuffer(url);
          const file = fs.openSync(uris[i], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
          try {
            fs.writeSync(file.fd, buf);
          } finally {
            fs.closeSync(file);
          }
        }
        ToastUtil.show(L10n.t('download_success', '下载成功'));
      } finally {
        await DialogUtil.dismissLoading();
      }
    } catch (e) {
      hilog.error(0x0000, TAG, 'download failed: %{public}s', JSON.stringify(e));
      await DialogUtil.dismissLoading();
      ToastUtil.show(L10n.t('download_failed', '下载失败'));
    }
  }

  private static async downloadBuffer(url: string): Promise<ArrayBuffer> {
    const token = (APIClient.getInstance().state.accessToken ?? '').trim();
    const headers: Record<string, string> = {};
    if (token.length > 0) {
      headers['Authorization'] = `Bearer ${token}`;
    }
    const req = http.createHttp();
    try {
      const resp = await req.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 300000,
        usingProtocol: http.HttpProtocol.HTTP1_1,
        remoteValidation: 'skip',
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error(`download_http_${resp.responseCode}`);
      }
      return resp.result as ArrayBuffer;
    } finally {
      req.destroy();
    }
  }

  // ================= 自动播放 =================

  toggleAutoPlay(): void {
    this.isAutoPlaying = !this.isAutoPlaying;
    if (this.isAutoPlaying) {
      this.startAutoPlay();
    } else {
      this.stopAutoPlay();
    }
  }

  private startAutoPlay(): void {
    this.stopAutoPlay();
    this.autoPlayTimer = setInterval((): void => {
      this.nextImage();
    }, AUTO_PLAY_INTERVAL_MS);
  }

  private stopAutoPlay(): void {
    if (this.autoPlayTimer >= 0) {
      clearInterval(this.autoPlayTimer);
      this.autoPlayTimer = -1;
    }
  }

  // ================= 翻页 =================

  previousImage(): void {
    if (this.currentIndex > 0) {
      this.gotoPage(this.currentIndex - 1);
    }
  }

  nextImage(): void {
    if (this.currentIndex < this.items.length - 1) {
      this.gotoPage(this.currentIndex + 1);
    }
  }

  destroy(): void {
    this.stopAutoPlay();
    this.livePlayingIndex = -1;
  }
}

function matchesPanoramaRatio(width: number, height: number): boolean {
  if (width <= 0 || height <= 0 || width <= height) {
    return false;
  }
  const ratio = width / height;
  return ratio >= PANORAMA_MIN_RATIO && ratio <= PANORAMA_MAX_RATIO;
}

export { normalizeServerPath, isUrl, asStr };
