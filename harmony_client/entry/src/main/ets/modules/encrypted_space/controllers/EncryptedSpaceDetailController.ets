import { L10n } from '../../../core/localization/L10n';
import { DialogUtil } from '../../../common/DialogUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { PreferencesStore } from '../../../core/storage/PreferencesStore';
import { UploadCancellationToken } from '../../../transfer/controllers/UploadCore';
import {
  EncryptedSpaceActiveSpace, EncryptedFileItem, encryptedFileItemFrom,
  ENCRYPTED_SPACE_SORT_FIELDS
} from '../models/EncryptedSpaceModels';
import { EncryptedSpaceApiService } from '../services/EncryptedSpaceApiService';
import { EncryptedSpaceFileUtils } from '../services/EncryptedSpaceFileUtils';

/** 文件列表排序偏好 key（对齐 _prefsSortFieldKey/_prefsSortOrderKey） */
const PREFS_SORT_FIELD_KEY = 'encrypted_space_file_list_sort_field';
const PREFS_SORT_ORDER_KEY = 'encrypted_space_file_list_sort_order';
/** 文件列表分页大小（对齐 _fileListPageSize） */
const FILE_LIST_PAGE_SIZE = 200;

/**
 * 加密空间详情控制器（对齐 Flutter EncryptedSpaceDetailController）：
 * 分页文件列表、排序/类型筛选/搜索（防抖）、分块上传（含取消）、删除、下载、打开（图片查看器/视频播放器）。
 */
@ObservedV2
export class EncryptedSpaceDetailController {
  readonly active: EncryptedSpaceActiveSpace;
  @Trace files: EncryptedFileItem[] = [];
  @Trace isLoading: boolean = false;
  @Trace errorText: string = '';
  @Trace loadingMore: boolean = false;
  @Trace hasMore: boolean = true;
  /** 排序字段：id, create_time, check_time, original_time, size, duration, show_name */
  @Trace sortField: string = 'original_time';
  @Trace sortOrder: string = 'desc';
  /** 与后端 private_space_index.file_type 一致：all / image / video / other */
  @Trace fileTypeFilter: string = 'all';
  @Trace searchKeyword: string = '';
  @Trace isUploading: boolean = false;
  @Trace uploadingFileName: string = '';
  @Trace uploadingIndex: number = 0;
  @Trace uploadingTotal: number = 0;
  @Trace uploadingProgress: number = 0;
  /** 图片查看器打开序号（自增触发；对齐 Flutter Get.to CustomGallery） */
  @Trace viewerVersion: number = 0;
  /** 图片查看器当前点击的文件（viewerVersion 变化时打开） */
  @Trace viewerItem: EncryptedFileItem | undefined = undefined;

  private searchDebounceTimer: number = -1;
  private uploadCancelToken: UploadCancellationToken = new UploadCancellationToken();

  constructor(active: EncryptedSpaceActiveSpace) {
    this.active = active;
  }

  /** 页面销毁时清理（对齐 onClose） */
  release(): void {
    if (this.searchDebounceTimer >= 0) {
      clearTimeout(this.searchDebounceTimer);
      this.searchDebounceTimer = -1;
    }
  }

  /** 退出详情页时静默删除空间 token（对齐 Flutter closeActiveSpace） */
  deleteTokenSilently(): void {
    const spaceId = this.active.spaceId;
    if (spaceId <= 0) {
      return;
    }
    EncryptedSpaceApiService.deleteToken(spaceId).catch((_e: Object): void => {
      // 静默失败
    });
  }

  // ===== 排序 / 筛选 / 搜索 =====

  async loadSortFromPrefs(): Promise<void> {
    try {
      const store = PreferencesStore.getInstance();
      const f = (store.getString(PREFS_SORT_FIELD_KEY) ?? '').trim();
      const o = (store.getString(PREFS_SORT_ORDER_KEY) ?? '').trim().toLowerCase();
      if (f.length > 0 && ENCRYPTED_SPACE_SORT_FIELDS.includes(f)) {
        this.sortField = f;
      }
      if (o === 'asc') {
        this.sortOrder = 'asc';
      } else if (o === 'desc') {
        this.sortOrder = 'desc';
      }
    } catch (_e) {
      // 偏好读取失败不阻塞
    }
  }

  private async saveSortToPrefs(): Promise<void> {
    try {
      const store = PreferencesStore.getInstance();
      await store.setString(PREFS_SORT_FIELD_KEY, this.sortField);
      await store.setString(PREFS_SORT_ORDER_KEY, this.sortOrder);
    } catch (_e) {
      // 偏好写入失败不阻塞
    }
  }

  setSort(field: string, order: string): void {
    this.sortField = field;
    this.sortOrder = order;
    void this.saveSortToPrefs();
    void this.refreshList(false);
  }

  setFileTypeFilter(raw: string): void {
    const v = raw.trim().toLowerCase();
    if (v !== 'all' && v !== 'image' && v !== 'video' && v !== 'other') {
      return;
    }
    if (this.fileTypeFilter === v) {
      return;
    }
    this.fileTypeFilter = v;
    void this.refreshList(false);
  }

  /** 搜索输入（500ms 防抖后刷新，对齐 onSearchChanged） */
  onSearchChanged(value: string): void {
    this.searchKeyword = value;
    if (this.searchDebounceTimer >= 0) {
      clearTimeout(this.searchDebounceTimer);
    }
    this.searchDebounceTimer = setTimeout((): void => {
      this.searchDebounceTimer = -1;
      void this.refreshList(false);
    }, 500);
  }

  clearSearch(): void {
    this.searchKeyword = '';
    void this.refreshList(false);
  }

  // ===== 列表 =====

  async refreshList(showLoading: boolean = true): Promise<void> {
    this.isLoading = true;
    this.errorText = '';
    this.hasMore = true;
    try {
      if (showLoading) {
        await DialogUtil.showLoading(L10n.loading);
      }
      const res = await EncryptedSpaceApiService.getFileList(
        this.active.spaceId, this.active.token, FILE_LIST_PAGE_SIZE, 0,
        this.sortField, this.sortOrder, this.fileTypeFilter, this.searchKeyword);
      if (!res.success) {
        this.errorText = res.message.length > 0 ? res.message : L10n.operationFailed;
        this.files = [];
        return;
      }
      const list: EncryptedFileItem[] = [];
      for (const raw of res.data ?? []) {
        list.push(encryptedFileItemFrom(raw as Record<string, Object>));
      }
      this.files = list;
      this.hasMore = list.length >= FILE_LIST_PAGE_SIZE;
    } catch (_e) {
      this.errorText = L10n.operationFailed;
      this.files = [];
    } finally {
      if (showLoading) {
        await DialogUtil.dismissLoading(true);
      }
      this.isLoading = false;
    }
  }

  /** 滚动到底部时加载下一页（对齐 loadMore） */
  async loadMore(): Promise<void> {
    if (this.loadingMore || !this.hasMore || this.isLoading) {
      return;
    }
    this.loadingMore = true;
    try {
      const res = await EncryptedSpaceApiService.getFileList(
        this.active.spaceId, this.active.token, FILE_LIST_PAGE_SIZE, this.files.length,
        this.sortField, this.sortOrder, this.fileTypeFilter, this.searchKeyword);
      if (!res.success) {
        return;
      }
      const added = res.data?.length ?? 0;
      if (added > 0) {
        const next: EncryptedFileItem[] = this.files.slice();
        for (const raw of res.data ?? []) {
          next.push(encryptedFileItemFrom(raw as Record<string, Object>));
        }
        this.files = next;
      }
      this.hasMore = added >= FILE_LIST_PAGE_SIZE;
    } catch (_e) {
      this.hasMore = false;
    } finally {
      this.loadingMore = false;
    }
  }

  // ===== 删除 / 下载 / 打开 =====

  async deleteItemsFlow(items: EncryptedFileItem[]): Promise<void> {
    const ids: number[] = [];
    for (const it of items) {
      if (it.indexId > 0) {
        ids.push(it.indexId);
      }
    }
    if (ids.length === 0) {
      return;
    }
    const ok = await DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      `${L10n.t('confirm_delete', '确认删除')} (${ids.length})`,
      undefined, L10n.t('delete', '删除'), L10n.cancel);
    if (ok !== true) {
      return;
    }
    await DialogUtil.showLoading(L10n.loading);
    try {
      const res = await EncryptedSpaceApiService.deleteSpaceFiles(this.active.spaceId, ids);
      if (!res.success) {
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('delete_failed', '删除失败'));
        return;
      }
      ToastUtil.show(L10n.t('delete_success', '删除成功'));
      await this.refreshList(false);
    } finally {
      await DialogUtil.dismissLoading(true);
    }
  }

  /** 查看器内删除单张（对齐 deleteItemFromGalleryFlow；成功返回 true 供查看器移除） */
  async deleteFromGalleryFlow(indexId: number): Promise<boolean> {
    if (indexId <= 0) {
      return false;
    }
    const ok = await DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      `${L10n.t('confirm_delete', '确认删除')} (1)`,
      undefined, L10n.t('delete', '删除'), L10n.cancel);
    if (ok !== true) {
      return false;
    }
    await DialogUtil.showLoading(L10n.loading);
    try {
      const res = await EncryptedSpaceApiService.deleteSpaceFiles(this.active.spaceId, [indexId]);
      if (!res.success) {
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('delete_failed', '删除失败'));
        return false;
      }
      ToastUtil.show(L10n.t('delete_success', '删除成功'));
      await this.refreshList(false);
      return true;
    } finally {
      await DialogUtil.dismissLoading(true);
    }
  }

  /** 下载单个文件（对齐 _downloadItems 单条路径；其他类型文件点开即下载） */
  async downloadItem(item: EncryptedFileItem): Promise<void> {
    if (item.indexId <= 0) {
      return;
    }
    const url = EncryptedSpaceApiService.buildDecodeUrl(
      this.active.spaceId, this.active.token, item.indexId, '', true, item.showName);
    await EncryptedSpaceFileUtils.downloadAndSave(url, item.showName);
  }

  /** 打开条目：图片进查看器、视频进播放器、其他下载（对齐 openItem） */
  openItem(item: EncryptedFileItem): void {
    if (item.fileType === 'image') {
      this.viewerItem = item;
      this.viewerVersion++;
      return;
    }
    if (item.fileType === 'video') {
      this.openVideo(item);
      return;
    }
    void this.downloadItem(item);
  }

  private openVideo(item: EncryptedFileItem): void {
    const videos: EncryptedFileItem[] = [];
    let index = -1;
    for (const f of this.files) {
      if (f.fileType !== 'video') {
        continue;
      }
      videos.push(f);
      if (f.indexId === item.indexId) {
        index = videos.length - 1;
      }
    }
    if (videos.length === 0 || index < 0) {
      return;
    }
    EncryptedSpaceFileUtils.openVideoPlayer(this.active, videos, index);
  }

  // ===== 上传 =====

  /** 选择来源并上传（对齐 uploadFilesFlow：相册/文件两个入口） */
  async uploadFilesFlow(source: string): Promise<void> {
    if (this.isUploading) {
      return;
    }
    let uris: string[] = [];
    if (source === 'media') {
      uris = await EncryptedSpaceFileUtils.pickMediaUris();
    } else {
      uris = await EncryptedSpaceFileUtils.pickFileUris();
    }
    if (uris.length === 0) {
      return;
    }
    await this.uploadUris(uris);
  }

  private async uploadUris(uris: string[]): Promise<void> {
    if (uris.length === 0 || this.isUploading) {
      return;
    }
    this.isUploading = true;
    this.uploadingTotal = uris.length;
    this.uploadingIndex = 0;
    this.uploadingProgress = 0;
    this.uploadingFileName = '';
    this.uploadCancelToken = new UploadCancellationToken();
    try {
      for (let i = 0; i < uris.length; i++) {
        if (this.uploadCancelToken.isCancelled()) {
          throw new Error('upload_cancelled');
        }
        const uri = uris[i];
        const fileName = EncryptedSpaceFileUtils.fileNameFromUri(uri);
        if (fileName.length === 0) {
          continue;
        }
        this.uploadingIndex = i + 1;
        this.uploadingFileName = fileName;
        this.uploadingProgress = 0;
        await EncryptedSpaceApiService.uploadFile(
          this.active.spaceId, this.active.token, uri, fileName,
          (sent: number, total: number): void => {
            if (total <= 0) {
              return;
            }
            this.uploadingProgress = Math.min(Math.max(sent / total, 0), 1);
          }, this.uploadCancelToken);
      }
      await this.refreshList(false);
    } catch (e) {
      const msg = e instanceof Error ? e.message : `${e}`;
      if (msg === 'upload_cancelled') {
        ToastUtil.show(L10n.t('cancel', '取消'));
      } else {
        ToastUtil.show(msg.length > 0 ? msg : L10n.operationFailed);
      }
    } finally {
      this.isUploading = false;
      this.uploadingFileName = '';
      this.uploadingIndex = 0;
      this.uploadingTotal = 0;
      this.uploadingProgress = 0;
    }
  }

  /** 取消上传（确认后置取消标记，分块循环检测后中断，对齐 cancelUploadFlow） */
  async cancelUploadFlow(): Promise<void> {
    if (!this.isUploading) {
      return;
    }
    const ok = await DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('encrypted_space_cancel_upload_confirm', '确认取消上传？'),
      undefined, L10n.confirm, L10n.cancel);
    if (ok !== true) {
      return;
    }
    this.uploadCancelToken.cancel();
  }
}
