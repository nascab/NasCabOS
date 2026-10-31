import { ApiUrls } from '../../../core/network/ApiUrls';
import { APIClient } from '../../../core/network/APIClient';
import { L10n } from '../../../core/localization/L10n';
import { AppImageLoader } from '../../../common/components/AppImage';
import { DialogUtil } from '../../../common/DialogUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { FileApiService } from '../../files/service/FileApiService';
import { PhotoTimelineApiService } from '../../photo/service/PhotoTimelineApiService';
import { TimelineDetectedFaceItem } from '../../photo/models/PhotoModels';
import { DownloadService } from '../../transfer/services/DownloadService';
import { DownloadTarget } from '../../transfer/models/DownloadModels';
import { GalleryItem, GalleryPageParam } from '../models/GalleryModels';

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

/** 是否 GIF 条目（对齐 Flutter _hasGifExtension：name/path/url 任一为 .gif） */
function hasGifExtension(value: string): boolean {
  const raw = value.trim();
  if (raw.length === 0) {
    return false;
  }
  const clean = raw.split('?')[0].trim().toLowerCase();
  return clean.endsWith('.gif');
}

/**
 * GIF 的 rawFile URL 补 raw=1 以保留原文件（动画）；
 * 非 GIF 不加 raw=1，交由服务端解码/按 EXIF 旋转后返回 JPEG（对齐 Flutter _normalizeGifUrl）。
 */
function normalizeGifUrl(url: string, isGif: boolean): string {
  const trimmed = url.trim();
  if (!isGif || trimmed.length === 0) {
    return trimmed;
  }
  const q = trimmed.indexOf('?');
  const base = q >= 0 ? trimmed.substring(0, q) : trimmed;
  if (!base.endsWith('/api/file/rawFile')) {
    return trimmed;
  }
  if (/(\?|&)raw=1(&|$)/.test(trimmed)) {
    return trimmed;
  }
  return `${trimmed}${q >= 0 ? '&' : '?'}raw=1`;
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
  /** items 集合变化（configure 完成/删除）通知页面的懒加载数据源 */
  onItemsSet: () => void = (): void => {
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
      // URL 构建对齐 Flutter galleryItems setter：GIF 才带 raw=1，其余交给服务端转码输出 JPEG
      const isGif = hasGifExtension(src.name) || hasGifExtension(src.path) || hasGifExtension(src.url);
      const path = src.path.trim();
      const existingUrl = src.url.trim();
      if (path.length > 0 && !isUrl(path)) {
        it.url = await ApiUrls.getRawFileUrl(path, true, 'file', undefined, isGif);
      } else if (existingUrl.length > 0) {
        it.url = normalizeGifUrl(existingUrl, isGif);
      } else {
        it.url = normalizeGifUrl(path, isGif);
      }
      it.liveVideoUrl = await this.buildLiveVideoUrl(it);
      items.push(it);
    }
    this.items = items;
    this.currentIndex = Math.min(Math.max(param.initialIndex, 0), Math.max(items.length - 1, 0));
    this.isControlsVisible = true;
    this.livePlayingIndex = -1;
    this.onItemsSet();
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
    // 相邻页图片无需主动预取：Swiper cachedCount(1) 会构建相邻页的 ZoomableImage，
    // 由组件自身懒加载并随页面销毁自动取消；主动 load 会留下无法随销毁取消的等待者。
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
        // 全景探测不是展示者：拿到结果后释放等待者名额（下载本身继续完成并入缓存）
        AppImageLoader.detach(item.url);
        const info = await pm.getImageInfo();
        candidate = matchesPanoramaRatio(info.size.width, info.size.height);
      }
      this.panoramaCandidates.set(index, candidate);
    } catch (_e) {
      AppImageLoader.detach(this.items[index]?.url ?? '');
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
    this.onItemsSet();
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

  /** 下载当前图片：与照片时间轴一致走下载中心（Live Photo/RAW 附件一并入队后跳转下载中心） */
  async downloadCurrentImage(): Promise<void> {
    const item = this.currentItem();
    if (item === undefined) {
      return;
    }
    const path = normalizeServerPath(item.path);
    if (path.length === 0 || isUrl(path)) {
      ToastUtil.show(L10n.t('download_failed', '下载失败'));
      return;
    }
    const targets: DownloadTarget[] = [{ path: path, isDirHint: false }];
    if (item.photoId > 0) {
      const dir = serverDirname(path);
      if (item.liveFilename.trim().length > 0) {
        targets.push({ path: serverJoin(dir, item.liveFilename.trim()), isDirHint: false });
      }
      if (item.rawFilename.trim().length > 0) {
        targets.push({ path: serverJoin(dir, item.rawFilename.trim()), isDirHint: false });
      }
    }
    // 图片浏览器内直接入队，不跳转下载中心
    const added: number = await DownloadService.getInstance().enqueue(targets);
    if (added > 0) {
      ToastUtil.show(L10n.t('task_added', '任务已添加'));
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
