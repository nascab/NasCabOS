import { MediaPickerUtil } from '../../../transfer/utils/MediaPickerUtil';
import { PreferencesStore } from '../../../core/storage/PreferencesStore';
import { ToastUtil } from '../../../common/ToastUtil';
import { DialogUtil } from '../../../common/DialogUtil';
import { PickOption, showOptionPickSheet } from '../../../common/components/OptionPickSheet';
import { L10n } from '../../../core/localization/L10n';
import { NotesFileUtils } from '../../notes/services/NotesFileUtils';
import {
  MediaToolApiResult, MediaToolImageCompressApiService, MediaToolImageCompressResult,
  MediaToolTaskApiService
} from '../services/MediaToolApiServices';
import {
  MediaToolKind, MediaToolTaskItem, audioCodecForFormat, mtAsRecord, mtClampInt,
  mtParsePositiveNum
} from '../models/MediaToolModels';

// ===== 图片压缩转换控制器（对齐 Flutter ImageCompressController） =====

/** 设置持久化 key（Flutter CacheKeys.imageCompressXxx 的模块内等价实现） */
const KEY_IMG_QUALITY = 'media_tool_image_compress_quality';
const KEY_IMG_FORMAT = 'media_tool_image_compress_format';
const KEY_IMG_SIZE = 'media_tool_image_compress_size';
const KEY_IMG_CUSTOM_OUT_SIZE = 'media_tool_image_compress_custom_out_size';
const KEY_IMG_WITH_META = 'media_tool_image_compress_with_meta';

/** 支持的图片扩展名（对齐 Flutter _supportedImageExtsWithDot） */
const SUPPORTED_IMAGE_EXTS: string[] = [
  '.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.tif', '.tiff', '.heic', '.heif'
];

function isSupportedImagePath(nameOrPath: string): boolean {
  const lower = nameOrPath.trim().toLowerCase();
  for (const ext of SUPPORTED_IMAGE_EXTS) {
    if (lower.endsWith(ext)) {
      return true;
    }
  }
  return false;
}

@ObservedV2
export class ImageCompressController {
  @Trace quality: string = 'auto';
  @Trace format: string = 'auto';
  @Trace size: string = 'auto';
  /** 0 表示未设置（Flutter 的 nullable int） */
  @Trace customOutSize: number = 0;
  @Trace withMeta: boolean = true;
  @Trace busy: boolean = false;
  @Trace results: MediaToolImageCompressResult[] = [];
  private lastUploadStartTime: number = 0;

  constructor() {
    const store = PreferencesStore.getInstance();
    const q = store.getString(KEY_IMG_QUALITY, '');
    if (q !== undefined && q.length > 0) {
      this.quality = q;
    }
    const f = store.getString(KEY_IMG_FORMAT, '');
    if (f !== undefined && f.length > 0) {
      this.format = f;
    }
    const s = store.getString(KEY_IMG_SIZE, '');
    if (s !== undefined && s.length > 0) {
      this.size = s;
    }
    const custom = store.getInt(KEY_IMG_CUSTOM_OUT_SIZE, 0);
    if (custom > 0) {
      this.customOutSize = custom;
    }
    this.withMeta = store.getBool(KEY_IMG_WITH_META, true);
  }

  // ===== 设置持久化（对齐 Flutter ever 监听写入缓存） =====

  setQuality(v: string): void {
    this.quality = v;
    void PreferencesStore.getInstance().setString(KEY_IMG_QUALITY, v);
  }

  setFormat(v: string): void {
    this.format = v;
    void PreferencesStore.getInstance().setString(KEY_IMG_FORMAT, v);
  }

  setSize(v: string): void {
    this.size = v;
    void PreferencesStore.getInstance().setString(KEY_IMG_SIZE, v);
  }

  setCustomOutSize(v: number): void {
    this.customOutSize = v;
    const store = PreferencesStore.getInstance();
    if (v > 0) {
      void store.setInt(KEY_IMG_CUSTOM_OUT_SIZE, v);
    } else {
      void store.remove(KEY_IMG_CUSTOM_OUT_SIZE);
    }
  }

  setWithMeta(v: boolean): void {
    this.withMeta = v;
    void PreferencesStore.getInstance().setBool(KEY_IMG_WITH_META, v);
  }

  // ===== 统计（对齐 Flutter optimizedCount / optimizedSavedBytesText） =====

  optimizedCount(): number {
    let n = 0;
    this.results.forEach((e: MediaToolImageCompressResult): void => {
      if (e.inputSize - e.outputSize > 0) {
        n++;
      }
    });
    return n;
  }

  optimizedSavedBytesText(): string {
    let total = 0;
    this.results.forEach((e: MediaToolImageCompressResult): void => {
      total += Math.max(0, e.inputSize - e.outputSize);
    });
    return mtFormatSize(total);
  }

  /** 打包下载起始时间戳（结果中最小的 uploadStartTime，对齐 zipMinTimeStamp） */
  zipMinTimeStamp(): number {
    let minTs = 0;
    this.results.forEach((it: MediaToolImageCompressResult): void => {
      const ts = it.uploadStartTime;
      if (ts > 0 && (minTs === 0 || ts < minTs)) {
        minTs = ts;
      }
    });
    return minTs > 0 ? minTs : this.lastUploadStartTime;
  }

  // ===== 上传（对齐 Flutter pickAndUploadByMobileSource） =====

  /** 弹出来源选择（相册/文件），返回 'media' | 'files' | ''（取消） */
  pickSource(): Promise<string> {
    return new Promise<string>((resolve: (v: string) => void) => {
      const options: PickOption[] = [
        new PickOption('media', L10n.t('upload_center_pick_media', '选择媒体文件')),
        new PickOption('files', L10n.t('folder_upload_file', '选择文件'))
      ];
      showOptionPickSheet(
        L10n.t('media_tool_pick_images', '选择图片'), options, '', (key: string): void => {
          resolve(key);
        });
    });
  }

  /** 选择图片并逐个上传（相册/文件来源统一入口） */
  async pickAndUpload(): Promise<void> {
    if (this.busy) {
      return;
    }
    const source = await this.pickSource();
    if (source.length === 0) {
      return;
    }
    const uris = source === 'media'
      ? await MediaPickerUtil.pickMedia()
      : await MediaPickerUtil.pickFiles();
    if (uris.length === 0) {
      return;
    }
    const supported: string[] = [];
    let hasUnsupported = false;
    uris.forEach((uri: string): void => {
      if (isSupportedImagePath(uri)) {
        supported.push(uri);
      } else {
        hasUnsupported = true;
      }
    });
    if (supported.length === 0) {
      if (hasUnsupported) {
        ToastUtil.show(L10n.t('file_format_not_supported', '文件格式不支持'));
      }
      return;
    }
    if (hasUnsupported) {
      ToastUtil.show(L10n.t('file_format_not_supported', '文件格式不支持'));
    }
    const now = Date.now();
    this.lastUploadStartTime = now;
    this.busy = true;
    try {
      for (const uri of supported) {
        await this.uploadOne(uri, now);
      }
    } catch (e) {
      ToastUtil.show(e instanceof Error ? e.message : L10n.operationFailed);
    } finally {
      this.busy = false;
    }
  }

  /** 上传单张图片并插入结果列表头部（对齐 Flutter _uploadOnePath） */
  private async uploadOne(localUri: string, uploadStartTime: number): Promise<void> {
    const clean = localUri.split('?')[0];
    const slash = clean.lastIndexOf('/');
    const name = slash >= 0 && slash < clean.length - 1
      ? decodeURIComponent(clean.substring(slash + 1)) : 'image';
    const query = this.buildQuery(name, uploadStartTime);
    const res = await MediaToolImageCompressApiService.uploadAndCompress(localUri, name, query);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('server_error', '服务器错误'));
      return;
    }
    const data = mtAsRecord(res.data);
    const outputPath = data['outputFullPath'] !== undefined && data['outputFullPath'] !== null
      ? `${data['outputFullPath']}` : '';
    if (outputPath.length === 0) {
      return;
    }
    const item = new MediaToolImageCompressResult();
    item.fileName = name;
    item.inputSize = mtAsNumberOr(data['inputSize'], 0);
    item.outputSize = mtAsNumberOr(data['outputSize'], 0);
    item.outputFormat = data['outputFormat'] !== undefined && data['outputFormat'] !== null
      ? `${data['outputFormat']}` : '';
    item.outputFullPath = outputPath;
    item.uploadStartTime = mtAsNumberOr(data['uploadStartTime'], uploadStartTime);
    const next: MediaToolImageCompressResult[] = [item];
    this.results.forEach((r: MediaToolImageCompressResult): void => {
      next.push(r);
    });
    this.results = next;
  }

  /** 上传 query（对齐 Flutter _buildQuery） */
  private buildQuery(fileName: string, uploadStartTime: number): Map<string, string> {
    let outSize: number | undefined = undefined;
    if (this.size === 'custom') {
      outSize = this.customOutSize > 0 ? this.customOutSize : undefined;
    } else if (this.size !== 'auto') {
      outSize = mtParsePositiveNum(this.size, 1, 20000);
    }
    const query = new Map<string, string>();
    query.set('fileName', fileName);
    query.set('uploadStartTime', `${uploadStartTime}`);
    query.set('withMeta', this.withMeta ? '1' : '0');
    if (this.quality !== 'auto') {
      const q = mtParsePositiveNum(this.quality, 1, 100);
      if (q !== undefined) {
        query.set('zipQuality', `${Math.round(q)}`);
      }
    }
    if (outSize !== undefined) {
      query.set('outSize', `${Math.round(outSize)}`);
    }
    if (this.format !== 'auto') {
      query.set('zipFormat', this.format);
    }
    return query;
  }

  // ===== 结果操作（对齐 Flutter clearResults / saveFile / downloadZip） =====

  clearResults(): void {
    this.results = [];
    this.lastUploadStartTime = 0;
  }

  /** 保存单个结果（走系统"另存为"，对齐 Flutter _downloadViaCenter 语义） */
  async saveFile(item: MediaToolImageCompressResult): Promise<void> {
    const dot = item.fileName.lastIndexOf('.');
    const base = dot > 0 ? item.fileName.substring(0, dot) : item.fileName;
    const suggested = `${base}.${item.outputFormat}`;
    const url = MediaToolImageCompressApiService.buildFileDownloadUrl(item.outputFullPath, suggested);
    try {
      await NotesFileUtils.saveUrlAs(url, suggested);
    } catch (e) {
      ToastUtil.show(e instanceof Error ? e.message : L10n.operationFailed);
    }
  }

  async downloadZip(): Promise<void> {
    const ts = this.zipMinTimeStamp();
    if (ts <= 0) {
      return;
    }
    const url = MediaToolImageCompressApiService.buildZipDownloadUrl(ts, 'all-image.zip');
    try {
      await NotesFileUtils.saveUrlAs(url, 'all-image.zip');
    } catch (e) {
      ToastUtil.show(e instanceof Error ? e.message : L10n.operationFailed);
    }
  }
}

// ===== 批量任务列表控制器（对齐 Flutter 各批量任务 controller，按 kind 参数化） =====

@ObservedV2
export class MediaToolTaskController {
  readonly kind: MediaToolKind;
  private readonly api: MediaToolTaskApiService;
  @Trace tasks: MediaToolTaskItem[] = [];
  @Trace isLoading: boolean = false;
  @Trace errorText: string = '';
  /** 正在执行 start/stop 的任务 id 集合（对齐 Flutter opLoadingById） */
  @Trace opLoadingIds: number[] = [];
  private pollTimer: number = -1;
  private refreshInFlight: boolean = false;

  constructor(kind: MediaToolKind) {
    this.kind = kind;
    this.api = new MediaToolTaskApiService(`/api/mediaTool/${MediaToolTaskController.apiBase(kind)}`);
  }

  private static apiBase(kind: MediaToolKind): string {
    switch (kind) {
      case 'img_batch':
        return 'imgBatchCompress';
      case 'video_trans':
        return 'videoTrans';
      case 'audio_trans':
        return 'audioTrans';
      case 'media_arrange':
        return 'mediaArrange';
      default:
        return 'imgBatchCompress';
    }
  }

  // ===== 轮询（对齐 Flutter Timer.periodic 3s） =====

  startPolling(): void {
    this.stopPolling();
    void this.refreshList(false, true, false);
    this.pollTimer = setInterval((): void => {
      void this.refreshList(false, false, false);
    }, 3000);
  }

  stopPolling(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  isOpLoading(id: number): boolean {
    return this.opLoadingIds.indexOf(id) >= 0;
  }

  private setOpLoading(id: number, loading: boolean): void {
    const idx = this.opLoadingIds.indexOf(id);
    if (loading && idx < 0) {
      this.opLoadingIds.push(id);
    } else if (!loading && idx >= 0) {
      this.opLoadingIds.splice(idx, 1);
    }
  }

  // ===== 列表刷新（对齐 Flutter refreshList） =====

  async refreshList(showLoading: boolean = true, clearOnFail: boolean = true,
    waitIfBusy: boolean = true): Promise<void> {
    if (this.refreshInFlight) {
      if (!waitIfBusy) {
        return;
      }
      while (this.refreshInFlight) {
        await mtSleep(50);
      }
    }
    this.refreshInFlight = true;
    this.isLoading = true;
    this.errorText = '';
    try {
      if (showLoading) {
        await DialogUtil.showLoading(L10n.loading);
      }
      const res = await this.api.list(1);
      if (!res.success) {
        this.errorText = res.message.length > 0 ? res.message : L10n.operationFailed;
        if (clearOnFail) {
          this.tasks = [];
        }
        return;
      }
      const data = mtAsRecord(res.data);
      const items = data['items'];
      const out: MediaToolTaskItem[] = [];
      if (Array.isArray(items)) {
        (items as Object[]).forEach((o: Object): void => {
          out.push(MediaToolTaskItem.fromJson(mtAsRecord(o)));
        });
      }
      this.tasks = out;
    } catch (_e) {
      this.errorText = L10n.operationFailed;
      if (clearOnFail) {
        this.tasks = [];
      }
    } finally {
      if (showLoading) {
        await DialogUtil.dismissLoading(true);
      }
      this.isLoading = false;
      this.refreshInFlight = false;
    }
  }

  // ===== 任务操作（对齐 Flutter upsert / remove / start / stop） =====

  /** 新建/更新任务（body 由各编辑弹窗构建，与 Flutter 请求体一致） */
  async upsert(body: Record<string, Object>): Promise<boolean> {
    const res = await this.api.upsert(body);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      return false;
    }
    await this.refreshList(false, true, true);
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
    return true;
  }

  async removeTask(id: number): Promise<void> {
    const confirmed = await DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'), L10n.t(this.deleteConfirmKey(), '确定删除该任务吗？'));
    if (confirmed !== true) {
      return;
    }
    const res = await this.api.remove(id);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('delete_failed', '删除失败'));
      return;
    }
    await this.refreshList(false, true, true);
    ToastUtil.show(L10n.t('delete_success', '删除成功'));
  }

  async startTask(id: number): Promise<void> {
    await this.opStartStop(id, true);
  }

  async stopTask(id: number): Promise<void> {
    await this.opStartStop(id, false);
  }

  private async opStartStop(id: number, isStart: boolean): Promise<void> {
    this.setOpLoading(id, true);
    let res: MediaToolApiResult<Record<string, Object>>;
    try {
      res = isStart ? await this.api.start(id) : await this.api.stop(id);
    } finally {
      this.setOpLoading(id, false);
    }
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      await this.refreshList(false, false, true);
      return;
    }
    await this.refreshList(false, false, true);
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }

  /** 删除确认文案 key（对齐 Flutter 各 controller 的 showConfirmDialog 内容 key） */
  deleteConfirmKey(): string {
    switch (this.kind) {
      case 'video_trans':
        return 'media_tool_video_trans_delete_confirm';
      case 'audio_trans':
        return 'media_tool_audio_trans_delete_confirm';
      case 'media_arrange':
        return 'media_tool_arrange_delete_confirm';
      default:
        return 'file_share_server_delete_confirm';
    }
  }

  /** 启停按钮文案 key（媒体整理使用独立 key，对齐 Flutter） */
  startLabelKey(): string {
    return this.kind === 'media_arrange' ? 'media_tool_arrange_start' : 'file_backup_start';
  }

  stopLabelKey(): string {
    return this.kind === 'media_arrange' ? 'media_tool_arrange_stop' : 'file_backup_stop';
  }
}

// ===== 编辑弹窗共用工具 =====

/** 图片批量压缩任务请求体（对齐 Flutter ImgBatchCompressController.upsert 参数校验与组装） */
export function buildImgBatchUpsertBody(id: number | undefined, sourcePath: string,
  targetPath: string, outFormat: string, quality: number, outSize: number | undefined,
  nonImagePolicy: string): Record<string, Object> {
  const body: Record<string, Object> = {
    'source_path': sourcePath,
    'target_path': targetPath,
    'out_format': outFormat,
    'quality': quality,
    'non_image_policy': nonImagePolicy
  };
  if (id !== undefined) {
    body['id'] = id;
  }
  if (outSize !== undefined) {
    body['out_size'] = outSize;
  }
  return body;
}

/** 视频转换 trans_config（对齐 Flutter _VideoTransDialogState._buildConfig） */
export function buildVideoTransConfig(format: string, vcodec: string, acodec: string,
  resolution: string, videoBitrate: number | undefined, audioBitrate: number | undefined,
  fps: number | undefined, threadCount: number, enableHwAccel: boolean): Record<string, Object> {
  const cfg: Record<string, Object> = {
    'out_format': format,
    'vcodec': vcodec,
    'acodec': acodec,
    'resolution': resolution,
    'thread_count': threadCount,
    'enable_hw_accel': enableHwAccel
  };
  if (videoBitrate !== undefined) {
    cfg['video_bitrate_mbps'] = videoBitrate;
  }
  if (audioBitrate !== undefined) {
    cfg['audio_bitrate_kbps'] = audioBitrate;
  }
  if (fps !== undefined) {
    cfg['fps'] = fps;
  }
  return cfg;
}

/** 音频转换 trans_config（对齐 Flutter _AudioTransDialogState._buildConfig） */
export function buildAudioTransConfig(format: string, sampleRate: string, channels: string,
  audioBitrate: number | undefined, threadCount: number): Record<string, Object> {
  const cfg: Record<string, Object> = {
    'out_format': format,
    'acodec': audioCodecForFormat(format),
    'sample_rate': sampleRate,
    'channels': channels,
    'thread_count': threadCount
  };
  if (audioBitrate !== undefined) {
    cfg['audio_bitrate_kbps'] = audioBitrate;
  }
  return cfg;
}

/** 质量输入解析（对齐 Flutter _parseQuality：digits-only + clamp 30..100，空回退 80） */
export function parseImgBatchQuality(text: string): number {
  return mtClampInt(text, 30, 100, 80);
}

/** 自定义尺寸解析（对齐 Flutter _parseOutSize：clamp 10..20000，空/非法为 undefined） */
export function parseImgBatchOutSize(text: string): number | undefined {
  const trimmed = text.trim();
  if (trimmed.length === 0) {
    return undefined;
  }
  const n = Number(trimmed);
  if (Number.isNaN(n) || n <= 0) {
    return undefined;
  }
  return Math.min(20000, Math.max(10, Math.round(n)));
}

// ===== 模块内小工具 =====

export function mtAsNumberOr(v: Object | undefined | null, fallback: number): number {
  if (v === undefined || v === null) {
    return fallback;
  }
  if (typeof v === 'number') {
    return Number.isNaN(v) ? fallback : v;
  }
  const n = Number(`${v}`);
  return Number.isNaN(n) ? fallback : n;
}

function mtFormatSize(bytes: number): string {
  if (bytes <= 0) {
    return '0 B';
  }
  const suffixes: string[] = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  const v = bytes / Math.pow(1024, i);
  return `${v.toFixed(1)} ${suffixes[i]}`;
}

function mtSleep(ms: number): Promise<void> {
  return new Promise((resolve: () => void) => setTimeout(resolve, ms));
}
