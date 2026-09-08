import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import fs from '@ohos.file.fs';
import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { APIClient } from '../../core/network/APIClient';
import { DialogUtil } from '../../common/DialogUtil';
import { ToastUtil } from '../../common/ToastUtil';
import { SheetHandle, SheetParamsBase, SheetUtil } from '../../common/SheetUtil';
import { FileFormat } from '../../files/models/FileModels';
import { pickServerFileViaSheet } from '../../files/views/FolderPickerSheet';
import { UriReader } from '../../transfer/utils/UriReader';
import { asNum, asStr } from '../../video/models/VideoModels';
import { VideoPlayerController } from '../VideoPlayerController';
import { PlayerTrackInfo, PLAYER_QUALITY_OPTIONS } from '../models/PlayerModels';
import { VideoPlayerApiService } from '../service/VideoPlayerApiService';

const TAG = 'PlayerMenus';
/** 支持的外挂字幕扩展名（对齐 Flutter exts 集合） */
const SUBTITLE_EXTS: string[] = ['.srt', '.ass', '.vtt', '.ssa', '.sub', '.mks'];
/** 播放器菜单面板色（对齐 Flutter #1E1E2C 深色面板语义，跟随主题） */
function panelBg(): string {
  return AppTheme.current().surfaceBg;
}
function onSurface(): string {
  return AppTheme.current().onSurface;
}
function subText(): string {
  return AppTheme.current().subText;
}
function accent(): string {
  return AppTheme.current().primary;
}

function baseName(p: string): string {
  const normalized = p.replace(/\\/g, '/');
  const slash = normalized.lastIndexOf('/');
  return slash >= 0 ? normalized.substring(slash + 1) : normalized;
}

function fileExt(p: string): string {
  const dot = p.lastIndexOf('.');
  return dot >= 0 ? p.substring(dot).toLowerCase() : '';
}

function baseNameWithoutExt(p: string): string {
  const name = baseName(p);
  const dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

/** 字幕搜索需要服务器 6.x+（对齐 Flutter isServerVersionAtLeast(6)） */
function serverSupportsSubtitleSearch(): boolean {
  try {
    const ver = APIClient.getInstance().state.serverVersion;
    if (ver === undefined || ver.trim().length === 0) {
      return true;
    }
    const major = parseInt(ver.trim(), 10);
    return Number.isNaN(major) ? true : major >= 6;
  } catch (_e) {
    return true;
  }
}

function findSubtitleTrack(ctrl: VideoPlayerController, label: string): PlayerTrackInfo | undefined {
  for (const t of ctrl.subtitleTracks) {
    if (t.label === label) {
      return t;
    }
  }
  return undefined;
}

// ================================ 倍速 ================================

class SpeedSheetParams extends SheetParamsBase {
  ctrl: VideoPlayerController = new VideoPlayerController();
}

const SPEED_OPTIONS: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

@Builder
function SpeedSheetContent(p: SpeedSheetParams) {
  SpeedSheetInner({ p: p })
}

@ComponentV2
struct SpeedSheetInner {
  @Param p: SpeedSheetParams = new SpeedSheetParams();

  build() {
    Column() {
      SheetHandle()
      Text(L10n.t('player_play_speed', '播放速度'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(onSurface())
        .width('100%')
        .padding({ left: 20, right: 20, top: 6, bottom: 14 })
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(SPEED_OPTIONS, (speed: number) => {
          Text(`${speed}x`)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .padding({ left: 18, right: 18, top: 9, bottom: 9 })
            .borderRadius(999)
            .backgroundColor(this.p.ctrl.playbackSpeed === speed ? accent() : AppTheme.current().cardBg)
            .margin({ right: 14, bottom: 8 })
            .onClick(() => {
              this.p.ctrl.setSpeed(speed);
              this.p.close();
            })
        }, (speed: number): string => `${speed}`)
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 28 })
    }
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(panelBg())
  }
}

/** 打开倍速弹层（对齐 Flutter showSpeedMenu） */
export function showSpeedSheet(ctrl: VideoPlayerController): void {
  const p = new SpeedSheetParams();
  p.ctrl = ctrl;
  SheetUtil.present(p, wrapBuilder(SpeedSheetContent));
}

// ================================ 画质 ================================

class QualitySheetParams extends SheetParamsBase {
  ctrl: VideoPlayerController = new VideoPlayerController();
}

@Builder
function QualitySheetContent(p: QualitySheetParams) {
  QualitySheetInner({ p: p })
}

@ComponentV2
struct QualitySheetInner {
  @Param p: QualitySheetParams = new QualitySheetParams();

  build() {
    Column() {
      SheetHandle()
      Text(L10n.t('player_choose_quality', '选择画质'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(onSurface())
        .width('100%')
        .padding({ left: 20, right: 20, top: 6, bottom: 8 })
      List({ space: 0 }) {
        ForEach(PLAYER_QUALITY_OPTIONS, (q: string): void => {
          ListItem() {
            Row({ space: 12 }) {
              Text(this.p.ctrl.qualityLabel(q))
                .fontSize(15)
                .fontColor(onSurface())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              if (this.p.ctrl.currentQuality === q) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(18)
                  .fontColor([accent()])
              }
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 13, bottom: 13 })
            .onClick(() => {
              this.p.ctrl.changeQuality(q);
              this.p.close();
            })
          }
        }, (q: string): string => q)
      }
      .width('100%')
      .constraintSize({ maxHeight: 420 })
      .scrollBar(BarState.Auto)
      .padding({ bottom: 20 })
    }
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(panelBg())
  }
}

/** 打开画质弹层（对齐 Flutter showQualityMenu） */
export function showQualitySheet(ctrl: VideoPlayerController): void {
  const p = new QualitySheetParams();
  p.ctrl = ctrl;
  SheetUtil.present(p, wrapBuilder(QualitySheetContent));
}

// ================================ 循环模式 ================================

class LoopSheetParams extends SheetParamsBase {
  ctrl: VideoPlayerController = new VideoPlayerController();
}

class LoopOption {
  key: string = '';
  label: string = '';

  constructor(key: string, label: string) {
    this.key = key;
    this.label = label;
  }
}

function loopOptions(): LoopOption[] {
  return [
    new LoopOption('sequence', L10n.t('player_loop_sequence', '顺序播放')),
    new LoopOption('single', L10n.t('player_loop_single', '单视频循环')),
    new LoopOption('all', L10n.t('player_loop_all', '全部循环')),
    new LoopOption('shuffle', L10n.t('player_loop_shuffle', '随机播放'))
  ];
}

@Builder
function LoopSheetContent(p: LoopSheetParams) {
  LoopSheetInner({ p: p })
}

@ComponentV2
struct LoopSheetInner {
  @Param p: LoopSheetParams = new LoopSheetParams();

  build() {
    Column() {
      SheetHandle()
      Text(L10n.t('player_loop', '循环播放'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(onSurface())
        .width('100%')
        .padding({ left: 20, right: 20, top: 6, bottom: 8 })
      List({ space: 0 }) {
        ForEach(loopOptions(), (opt: LoopOption): void => {
          ListItem() {
            Row({ space: 12 }) {
              Text(opt.label)
                .fontSize(15)
                .fontColor(onSurface())
                .layoutWeight(1)
              if (this.p.ctrl.loopMode === opt.key) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(18)
                  .fontColor([accent()])
              }
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 13, bottom: 13 })
            .onClick(() => {
              void this.p.ctrl.setLoopMode(opt.key);
              this.p.close();
            })
          }
        }, (opt: LoopOption): string => opt.key)
      }
      .width('100%')
      .padding({ bottom: 20 })
    }
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(panelBg())
  }
}

/** 打开循环模式弹层（对齐 Flutter showLoopModeMenu） */
export function showLoopSheet(ctrl: VideoPlayerController): void {
  const p = new LoopSheetParams();
  p.ctrl = ctrl;
  SheetUtil.present(p, wrapBuilder(LoopSheetContent));
}

// ================================ 音轨 ================================

class AudioSheetParams extends SheetParamsBase {
  ctrl: VideoPlayerController = new VideoPlayerController();
}

@Builder
function AudioSheetContent(p: AudioSheetParams) {
  AudioSheetInner({ p: p })
}

@ComponentV2
struct AudioSheetInner {
  @Param p: AudioSheetParams = new AudioSheetParams();

  private labels(): string[] {
    if (this.p.ctrl.audioTrackLabels.length === 0) {
      return [L10n.t('default', '默认')];
    }
    return this.p.ctrl.audioTrackLabels;
  }

  build() {
    Column() {
      SheetHandle()
      Text(L10n.t('player_choose_audio', '选择音轨'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(onSurface())
        .width('100%')
        .padding({ left: 20, right: 20, top: 6, bottom: 8 })
      List({ space: 0 }) {
        ForEach(this.labels(), (t: string): void => {
          ListItem() {
            Row({ space: 12 }) {
              Text(t)
                .fontSize(15)
                .fontColor(onSurface())
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              if (this.p.ctrl.currentAudioTrack === t) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(18)
                  .fontColor([accent()])
              }
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 13, bottom: 13 })
            .onClick(() => {
              this.p.close();
              void this.p.ctrl.setAudioTrack(t);
            })
          }
        }, (t: string, idx: number): string => `${idx}_${t}`)
      }
      .width('100%')
      .constraintSize({ maxHeight: 420 })
      .scrollBar(BarState.Auto)
      .padding({ bottom: 20 })
    }
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(panelBg())
  }
}

/** 打开音轨弹层（对齐 Flutter showAudioMenu） */
export function showAudioSheet(ctrl: VideoPlayerController): void {
  const p = new AudioSheetParams();
  p.ctrl = ctrl;
  SheetUtil.present(p, wrapBuilder(AudioSheetContent));
}

// ================================ 字幕 ================================

class SubtitleSheetParams extends SheetParamsBase {
  ctrl: VideoPlayerController = new VideoPlayerController();
}

@Builder
function SubtitleSheetContent(p: SubtitleSheetParams) {
  SubtitleSheetInner({ p: p })
}

@ComponentV2
struct SubtitleSheetInner {
  @Param p: SubtitleSheetParams = new SubtitleSheetParams();

  /** 外挂字幕是否可删除（source 非空且有 path） */
  private canDelete(label: string): boolean {
    const t = findSubtitleTrack(this.p.ctrl, label);
    return t !== undefined && t.isExternal && t.source.trim().length > 0 && t.path.trim().length > 0;
  }

  private pickServerSubtitle(): void {
    this.p.close();
    const videoPath = this.p.ctrl.currentSourcePathForInfo();
    pickServerFileViaSheet('', (paths: string[]): void => {
      if (paths.length === 0) {
        return;
      }
      const subPath = paths[0].trim();
      if (subPath.length === 0) {
        return;
      }
      if (SUBTITLE_EXTS.indexOf(fileExt(subPath)) < 0) {
        ToastUtil.show(L10n.t('player_subtitle_format_unsupported', '不支持的字幕格式: @ext',
          this.extParams(fileExt(subPath))));
        return;
      }
      if (videoPath.length === 0) {
        ToastUtil.show(L10n.t('player_cannot_get_video_path', '无法获取当前视频路径'));
        return;
      }
      void this.p.ctrl.addAndSelectExternalSubtitle(subPath, baseName(subPath), '');
    });
  }

  private extParams(ext: string): Map<string, string> {
    const m = new Map<string, string>();
    m.set('ext', ext);
    return m;
  }

  private async pickAndUploadLocalSubtitle(): Promise<void> {
    this.p.close();
    const videoPath = this.p.ctrl.currentSourcePathForInfo();
    if (videoPath.length === 0) {
      ToastUtil.show(L10n.t('player_cannot_get_video_path', '无法获取当前视频路径'));
      return;
    }
    let uris: string[] = [];
    try {
      const docPicker = new picker.DocumentViewPicker();
      const opts = new picker.DocumentSelectOptions();
      opts.maxSelectNumber = 1;
      opts.fileSuffixFilters = SUBTITLE_EXTS;
      uris = await docPicker.select(opts);
    } catch (_e) {
      return; // 用户取消
    }
    if (uris === undefined || uris.length === 0) {
      return;
    }
    const uri = uris[0];
    const filename = uriDisplayName(uri);
    if (filename.length === 0) {
      ToastUtil.show(L10n.t('player_pick_local_subtitle_hint', '请选择本地字幕文件'));
      return;
    }
    const ctx = getContext(this) as common.Context;
    const tempPath = `${ctx.cacheDir}/upload_sub_${Date.now()}_${filename}`;
    try {
      const size = UriReader.statSize(uri);
      const bytes = UriReader.readRange(uri, 0, size);
      const buf = new ArrayBuffer(bytes.length);
      new Uint8Array(buf).set(bytes);
      const file = fs.openSync(tempPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, buf);
      fs.closeSync(file);
      DialogUtil.showLoading(L10n.t('loading', '加载中...'));
      const res = await new VideoPlayerApiService().uploadSubtitle(videoPath, tempPath, filename);
      await DialogUtil.dismissLoading();
      try {
        fs.unlinkSync(tempPath);
      } catch (_e2) {
        // 忽略临时文件清理失败
      }
      if (!res.success || res.data === undefined) {
        ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
        return;
      }
      const savedPath = asStr(res.data['path']).trim();
      const savedName = asStr(res.data['filename']).trim();
      if (savedPath.length === 0 || savedName.length === 0) {
        ToastUtil.show(L10n.t('operation_failed', '操作失败'));
        return;
      }
      await this.p.ctrl.addAndSelectExternalSubtitle(savedPath, savedName, 'uploaded');
      ToastUtil.show(L10n.t('player_subtitle_upload_success', '上传成功'));
    } catch (e) {
      await DialogUtil.dismissLoading();
      hilog.error(0x0000, TAG, 'uploadSubtitle failed: %{public}s', JSON.stringify(e));
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
    }
  }

  build() {
    Column() {
      SheetHandle()
      Text(L10n.t('player_subtitle', '字幕'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(onSurface())
        .width('100%')
        .padding({ left: 20, right: 20, top: 6, bottom: 4 })
      // 操作项
      Column() {
        this.ActionRow($r('sys.symbol.magnifyingglass'),
          L10n.t('player_subtitle_search', '字幕搜索'), (): void => {
            this.p.close();
            showSubtitleSearchSheet(this.p.ctrl);
          })
        this.ActionRow($r('sys.symbol.cloud'),
          L10n.t('player_choose_server_subtitle', '选择服务器字幕'), (): void => {
            this.pickServerSubtitle();
          })
        this.ActionRow($r('sys.symbol.upload'),
          L10n.t('player_upload_subtitle', '上传字幕'), (): void => {
            void this.pickAndUploadLocalSubtitle();
          })
      }
      .width('100%')
      Divider()
        .color(AppTheme.current().divider)
        .margin({ top: 4, bottom: 4 })
      // 轨道列表
      List({ space: 0 }) {
        ForEach(this.p.ctrl.subtitleTrackLabels, (label: string, index: number): void => {
          ListItem() {
            Row({ space: 10 }) {
              Text(index === 0 ? '' : `${index}.`)
                .fontSize(13)
                .fontColor(subText())
                .width(26)
              Text(label)
                .fontSize(15)
                .fontColor(onSurface())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              if (this.canDelete(label)) {
                Column() {
                  SymbolGlyph($r('sys.symbol.trash'))
                    .fontSize(17)
                    .fontColor([subText()])
                }
                .width(36)
                .height(36)
                .onClick(() => {
                  const t = findSubtitleTrack(this.p.ctrl, label);
                  if (t !== undefined) {
                    void this.p.ctrl.deleteExternalSubtitle(t.path);
                  }
                })
              }
              if (this.p.ctrl.currentSubtitleTrack === label) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(18)
                  .fontColor([accent()])
              }
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 11, bottom: 11 })
            .onClick(() => {
              this.p.close();
              void this.p.ctrl.setSubtitleTrack(label);
            })
          }
        }, (label: string, index: number): string => `${index}_${label}`)
      }
      .width('100%')
      .constraintSize({ maxHeight: 380 })
      .scrollBar(BarState.Auto)
      .padding({ bottom: 20 })
    }
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(panelBg())
  }

  @Builder
  ActionRow(icon: Resource, label: string, onTap: () => void) {
    Row({ space: 14 }) {
      SymbolGlyph(icon)
        .fontSize(21)
        .fontColor([subText()])
      Text(label)
        .fontSize(15)
        .fontColor(onSurface())
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 11, bottom: 11 })
    .onClick(() => {
      onTap();
    })
  }
}

/** 从 URI 提取显示名（对齐 MediaPickerUtil.uriDisplayName） */
function uriDisplayName(uri: string): string {
  const clean = uri.split('?')[0];
  const idx = clean.lastIndexOf('/');
  if (idx < 0 || idx >= clean.length - 1) {
    return '';
  }
  return decodeURIComponent(clean.substring(idx + 1));
}

/** 打开字幕弹层（对齐 Flutter showSubtitleMenu） */
export function showSubtitleSheet(ctrl: VideoPlayerController): void {
  const p = new SubtitleSheetParams();
  p.ctrl = ctrl;
  SheetUtil.present(p, wrapBuilder(SubtitleSheetContent));
}

// ================================ 字幕搜索 ================================

class SubtitleSearchSheetParams extends SheetParamsBase {
  ctrl: VideoPlayerController = new VideoPlayerController();
  videoPath: string = '';
  defaultKeyword: string = '';
}

/** 搜索结果条目（服务器返回 fields: sname/displayName/language/ext/surl） */
class SubtitleSearchItem {
  sname: string = '';
  displayName: string = '';
  language: string = '';
  ext: string = '';
  surl: string = '';

  static fromRecord(obj: Record<string, Object>): SubtitleSearchItem {
    const it = new SubtitleSearchItem();
    it.sname = asStr(obj['sname']).trim();
    it.displayName = asStr(obj['displayName']).trim();
    it.language = asStr(obj['language']).trim();
    it.ext = asStr(obj['ext']).trim();
    it.surl = asStr(obj['surl']).trim();
    return it;
  }

  title(): string {
    if (this.displayName.length > 0) {
      return this.displayName;
    }
    return this.sname.length > 0 ? this.sname : 'subtitle';
  }
}

@Builder
function SubtitleSearchSheetContent(p: SubtitleSearchSheetParams) {
  SubtitleSearchSheetInner({ p: p })
}

@ComponentV2
struct SubtitleSearchSheetInner {
  @Param p: SubtitleSearchSheetParams = new SubtitleSearchSheetParams();
  @Local loading: boolean = false;
  @Local searchTab: number = 0;
  @Local keyword: string = '';
  @Local items: SubtitleSearchItem[] = [];
  private apiService: VideoPlayerApiService = new VideoPlayerApiService();

  aboutToAppear(): void {
    this.keyword = this.p.defaultKeyword;
    void this.runFeatureThenMaybeFallback();
  }

  private async search(searchType: string): Promise<SubtitleSearchItem[]> {
    const res = await this.apiService.searchSubtitles(this.p.videoPath, searchType,
      searchType === 'keyword' ? this.keyword.trim() : '');
    if (!res.success || res.data === undefined) {
      throw new Error(res.message ?? L10n.t('player_subtitle_search_failed', '字幕搜索失败'));
    }
    const raw = res.data['items'];
    const out: SubtitleSearchItem[] = [];
    if (Array.isArray(raw)) {
      for (const e of raw as Object[]) {
        if (e instanceof Object && !Array.isArray(e)) {
          out.push(SubtitleSearchItem.fromRecord(e as Record<string, Object>));
        }
      }
    }
    return out;
  }

  private async runFeatureThenMaybeFallback(): Promise<void> {
    this.loading = true;
    this.searchTab = 0;
    this.items = [];
    try {
      const feature = await this.search('feature');
      if (feature.length > 0) {
        this.items = feature;
        this.searchTab = 0;
        this.loading = false;
        return;
      }
      const keywordItems = await this.search('keyword');
      this.items = keywordItems;
      this.searchTab = 1;
      this.loading = false;
      if (keywordItems.length === 0) {
        ToastUtil.show(L10n.t('player_subtitle_search_no_results', '没有找到字幕'));
      }
    } catch (e) {
      this.loading = false;
      ToastUtil.show(`${e instanceof Error ? e.message : L10n.t('player_subtitle_search_failed', '字幕搜索失败')}`);
    }
  }

  private async runSearch(tab: number): Promise<void> {
    this.loading = true;
    this.searchTab = tab;
    this.items = [];
    try {
      const found = await this.search(tab === 0 ? 'feature' : 'keyword');
      this.items = found;
      this.loading = false;
      if (found.length === 0) {
        ToastUtil.show(L10n.t('player_subtitle_search_no_results', '没有找到字幕'));
      }
    } catch (e) {
      this.loading = false;
      ToastUtil.show(`${e instanceof Error ? e.message : L10n.t('player_subtitle_search_failed', '字幕搜索失败')}`);
    }
  }

  private async downloadItem(it: SubtitleSearchItem): Promise<void> {
    if (it.surl.length === 0) {
      return;
    }
    await DialogUtil.showLoading(L10n.t('player_subtitle_downloading', '正在下载字幕…'));
    try {
      const res = await this.apiService.downloadSearchedSubtitle(this.p.videoPath, it.surl,
        it.sname, it.language);
      if (!res.success || res.data === undefined) {
        throw new Error(res.message ?? L10n.t('player_subtitle_download_failed', '字幕下载失败'));
      }
      const savedPath = asStr(res.data['path']).trim();
      const savedName = asStr(res.data['filename']).trim();
      if (savedPath.length === 0 || savedName.length === 0) {
        throw new Error(L10n.t('operation_failed', '操作失败'));
      }
      await DialogUtil.dismissLoading();
      await this.p.ctrl.addAndSelectExternalSubtitle(savedPath, savedName, 'searched');
      ToastUtil.show(L10n.t('player_subtitle_download_success', '字幕下载完成'));
    } catch (e) {
      await DialogUtil.dismissLoading();
      ToastUtil.show(`${e instanceof Error ? e.message : L10n.t('player_subtitle_download_failed', '字幕下载失败')}`);
    }
  }

  build() {
    Column() {
      SheetHandle()
      Text(L10n.t('player_subtitle_search_results', '字幕搜索结果'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(onSurface())
        .width('100%')
        .padding({ left: 20, right: 20, top: 6, bottom: 8 })
      // tab 切换
      Row({ space: 8 }) {
        this.TabChip(L10n.t('player_subtitle_search_feature', '特征搜索'), 0)
        this.TabChip(L10n.t('player_subtitle_search_keyword', '关键字搜索'), 1)
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 10 })
      // 关键字输入行
      if (this.searchTab === 1) {
        Row({ space: 10 }) {
          TextInput({ text: this.keyword, placeholder: L10n.t('player_subtitle_keyword_hint', '请输入关键字') })
            .fontSize(14)
            .fontColor(onSurface())
            .placeholderColor(subText())
            .backgroundColor(AppTheme.current().inputFill)
            .borderRadius(10)
            .height(40)
            .layoutWeight(1)
            .onChange((v: string): void => {
              this.keyword = v;
            })
            .onSubmit((): void => {
              if (!this.loading) {
                void this.runSearch(1);
              }
            })
          Button(L10n.t('player_subtitle_search_action', '搜索'))
            .fontSize(14)
            .fontColor(AppTheme.current().buttonText)
            .backgroundColor(AppTheme.current().buttonBg)
            .height(40)
            .enabled(!this.loading)
            .onClick(() => {
              void this.runSearch(1);
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 10 })
      }
      // 搜索中
      if (this.loading) {
        Row({ space: 12 }) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(accent())
          Text(L10n.t('player_subtitle_searching', '正在搜索字幕…'))
            .fontSize(14)
            .fontColor(subText())
        }
        .width('100%')
        .padding({ top: 14, bottom: 14 })
      }
      // 结果列表
      if (!this.loading && this.items.length === 0) {
        Text(L10n.t('player_subtitle_search_no_results', '没有找到字幕'))
          .fontSize(14)
          .fontColor(subText())
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 30, bottom: 40 })
      }
      if (!this.loading && this.items.length > 0) {
        List({ space: 0 }) {
          ForEach(this.items, (it: SubtitleSearchItem, index: number): void => {
            ListItem() {
              Row({ space: 10 }) {
                Text(`${index + 1}.`)
                  .fontSize(12)
                  .fontColor(subText())
                  .width(26)
                Column({ space: 6 }) {
                  Text(it.title())
                    .fontSize(15)
                    .fontColor(onSurface())
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Row({ space: 10 }) {
                    this.Chip(`${L10n.t('player_subtitle_language', '语言')}: ` +
                      (it.language.length > 0 ? it.language
                        : L10n.t('player_subtitle_language_unknown', '未知')))
                    this.Chip(`${L10n.t('player_subtitle_type', '类型')}: ` +
                      (it.ext.length > 0 ? it.ext : '-'))
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
                  .fontSize(20)
                  .fontColor([subText()])
              }
              .alignItems(VerticalAlign.Center)
              .width('100%')
              .padding({ left: 20, right: 20, top: 10, bottom: 10 })
              .onClick(() => {
                void this.downloadItem(it);
              })
            }
          }, (it: SubtitleSearchItem, index: number): string => `${index}_${it.surl}`)
        }
        .width('100%')
        .constraintSize({ maxHeight: 380 })
        .scrollBar(BarState.Auto)
        .padding({ bottom: 24 })
      }
    }
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(panelBg())
  }

  @Builder
  TabChip(label: string, index: number) {
    Text(label)
      .fontSize(14)
      .fontWeight(this.searchTab === index ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.searchTab === index ? '#FFFFFF' : subText())
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .borderRadius(999)
      .backgroundColor(this.searchTab === index ? accent() : AppTheme.current().cardBg)
      .onClick(() => {
        if (!this.loading && this.searchTab !== index) {
          void this.runSearch(index);
        }
      })
  }

  @Builder
  Chip(text: string) {
    Text(text)
      .fontSize(12)
      .fontColor('#B3FFFFFF')
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .borderRadius(999)
      .border({ width: 1, color: '#1FFFFFFF' })
      .backgroundColor('#1AFFFFFF')
      .maxLines(1)
  }
}

/** 打开字幕搜索弹层（对齐 Flutter showSubtitleSearchDialog） */
export function showSubtitleSearchSheet(ctrl: VideoPlayerController): void {
  if (!serverSupportsSubtitleSearch()) {
    DialogUtil.showInfoDialog(L10n.tip, L10n.t('server_version_too_low',
      '您的服务端版本过低，请升级到最新版本并重新登录后再使用此功能'));
    return;
  }
  const videoPath = ctrl.currentSourcePathForInfo();
  if (videoPath.length === 0) {
    ToastUtil.show(L10n.t('player_cannot_get_video_path', '无法获取当前视频路径'));
    return;
  }
  const p = new SubtitleSearchSheetParams();
  p.ctrl = ctrl;
  p.videoPath = videoPath;
  p.defaultKeyword = baseNameWithoutExt(videoPath);
  SheetUtil.present(p, wrapBuilder(SubtitleSearchSheetContent));
}

// ================================ 更多操作 ================================

class MoreSheetParams extends SheetParamsBase {
  ctrl: VideoPlayerController = new VideoPlayerController();
}

class MoreMenuItem {
  icon: Resource = $r('sys.symbol.more');
  label: string = '';
  onTap: () => void = (): void => {
  };

  constructor(icon: Resource, label: string, onTap: () => void) {
    this.icon = icon;
    this.label = label;
    this.onTap = onTap;
  }
}

@Builder
function MoreSheetContent(p: MoreSheetParams) {
  MoreSheetInner({ p: p })
}

@ComponentV2
struct MoreSheetInner {
  @Param p: MoreSheetParams = new MoreSheetParams();

  private items(): MoreMenuItem[] {
    const ctrl = this.p.ctrl;
    const out: MoreMenuItem[] = [];
    if (!ctrl.isUrlSource) {
      out.push(new MoreMenuItem($r('sys.symbol.AI_subtitles'),
        L10n.t('player_subtitle', '字幕'), (): void => {
          this.p.close();
          showSubtitleSheet(ctrl);
        }));
      out.push(new MoreMenuItem($r('sys.symbol.music_note_list'),
        L10n.t('player_choose_audio', '选择音轨'), (): void => {
          this.p.close();
          showAudioSheet(ctrl);
        }));
    }
    out.push(new MoreMenuItem($r('sys.symbol.repeat'),
      L10n.t('player_loop', '循环播放'), (): void => {
        this.p.close();
        showLoopSheet(ctrl);
      }));
    return out;
  }

  build() {
    Column() {
      SheetHandle()
      Text(L10n.t('player_operation', '播放操作'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(onSurface())
        .width('100%')
        .padding({ left: 20, right: 20, top: 6, bottom: 14 })
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.items(), (item: MoreMenuItem): void => {
          Column({ space: 8 }) {
            SymbolGlyph(item.icon)
              .fontSize(26)
              .fontColor([onSurface()])
            Text(item.label)
              .fontSize(12)
              .fontColor(subText())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center)
          }
          .width('25%')
          .padding({ bottom: 16 })
          .onClick(() => {
            item.onTap();
          })
        }, (item: MoreMenuItem, idx: number): string => `${idx}_${item.label}`)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 28 })
    }
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(panelBg())
  }
}

/** 打开更多操作弹层（对齐 Flutter showMoreMenu，不迁移播放内核项） */
export function showMoreSheet(ctrl: VideoPlayerController): void {
  const p = new MoreSheetParams();
  p.ctrl = ctrl;
  SheetUtil.present(p, wrapBuilder(MoreSheetContent));
}

// ================================ 视频信息抽屉 ================================

class InfoDrawerParams extends SheetParamsBase {
  ctrl: VideoPlayerController = new VideoPlayerController();
  filePath: string = '';
}

@Builder
function InfoDrawerContent(p: InfoDrawerParams) {
  InfoDrawerInner({ p: p })
}

@ComponentV2
struct InfoDrawerInner {
  @Param p: InfoDrawerParams = new InfoDrawerParams();
  @Local loading: boolean = true;
  @Local errorText: string = '';
  @Local basicName: string = '';
  @Local basicPath: string = '';
  @Local basicSize: string = '';
  @Local viewWidth: number = 0;
  private apiService: VideoPlayerApiService = new VideoPlayerApiService();

  aboutToAppear(): void {
    void this.fetchBasicInfo();
  }

  private async fetchBasicInfo(): Promise<void> {
    try {
      const res = await this.apiService.getFileAttributes(this.p.filePath);
      if (!res.success || res.data === undefined) {
        this.errorText = res.message ?? L10n.t('operation_failed', '操作失败');
        this.loading = false;
        return;
      }
      const d = res.data;
      this.basicName = asStr(d['name']);
      this.basicPath = asStr(d['path']);
      this.basicSize = FileFormat.formatSize(Math.round(asNum(d['size'])));
      this.loading = false;
    } catch (e) {
      this.errorText = `${e instanceof Error ? e.message : e}`;
      this.loading = false;
    }
  }

  private cardWidth(): number {
    const w = this.viewWidth > 0 ? this.viewWidth : 320;
    return (w - 12) / 2;
  }

  private formatDuration(ms: number): string {
    const totalSec = Math.max(0, Math.floor(ms / 1000));
    const h = Math.floor(totalSec / 3600);
    const m = Math.floor((totalSec % 3600) / 60);
    const s = totalSec % 60;
    if (h > 0) {
      return `${h}:${`${m}`.padStart(2, '0')}:${`${s}`.padStart(2, '0')}`;
    }
    return `${m}:${`${s}`.padStart(2, '0')}`;
  }

  build() {
    Column() {
      SheetHandle()
      Text(L10n.t('video_info', '视频信息'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(onSurface())
        .width('100%')
        .padding({ left: 20, right: 20, top: 6, bottom: 10 })
      if (this.loading) {
        Column() {
          LoadingProgress()
            .width(30)
            .height(30)
            .color(accent())
        }
        .width('100%')
        .height(180)
        .justifyContent(FlexAlign.Center)
      } else if (this.errorText.length > 0) {
        Text(this.errorText)
          .fontSize(14)
          .fontColor(AppTheme.current().error)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 40, bottom: 50 })
      } else {
        Scroll() {
          Column() {
            Text(L10n.t('basic_info', '基础信息'))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(onSurface())
              .width('100%')
              .margin({ bottom: 10 })
            this.InfoRow(L10n.t('filename', '文件名'), this.basicName)
            this.InfoRow(L10n.t('path', '路径'), this.basicPath)
            this.InfoRow(L10n.t('size', '大小'), this.basicSize)
            this.InfoRow(L10n.t('duration', '时长'), this.formatDuration(this.p.ctrl.durationMs))
            Text(L10n.t('media_streams', '媒体流信息'))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(onSurface())
              .width('100%')
              .margin({ top: 20, bottom: 10 })
            if (this.p.ctrl.videoTracks.length > 0) {
              this.StreamCategory(L10n.t('video_stream', '视频流'),
                $r('sys.symbol.video'), this.p.ctrl.videoTracks)
              Row().height(14)
            }
            if (this.p.ctrl.audioTracks.length > 0) {
              this.StreamCategory(L10n.t('audio_stream', '音频流'),
                $r('sys.symbol.music_note_list'), this.p.ctrl.audioTracks)
              Row().height(14)
            }
            if (this.p.ctrl.subtitleTracks.length > 0) {
              this.StreamCategory(L10n.t('subtitle_stream', '字幕流'),
                $r('sys.symbol.AI_subtitles'), this.p.ctrl.subtitleTracks)
            }
          }
          .width('100%')
        }
        .scrollBar(BarState.Auto)
        .width('100%')
        .constraintSize({ maxHeight: 460 })
        .padding({ left: 20, right: 20, bottom: 30 })
        .onAreaChange((_o: Area, n: Area): void => {
          this.viewWidth = Number(n.width);
        })
      }
    }
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(panelBg())
  }

  @Builder
  InfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor(subText())
        .width(76)
      Text(value.length > 0 ? value : '-')
        .fontSize(13)
        .fontColor(onSurface())
        .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .margin({ bottom: 8 })
  }

  @Builder
  StreamCategory(title: string, icon: Resource, tracks: PlayerTrackInfo[]) {
    Column() {
      Row({ space: 8 }) {
        SymbolGlyph(icon)
          .fontSize(14)
          .fontColor([subText()])
        Text(title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(subText())
      }
      .width('100%')
      .margin({ bottom: 8 })
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(tracks, (t: PlayerTrackInfo, idx: number): void => {
          Column()
            .width(this.cardWidth() + 12)
            .height(0)
          this.StreamCard(t, idx === tracks.length - 1)
        }, (t: PlayerTrackInfo, idx: number): string => `${idx}_${t.index}_${t.label}`)
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  StreamCard(t: PlayerTrackInfo, isLast: boolean) {
    Column() {
      Row() {
        Text(t.index === -1 ? L10n.t('subtitle_external', '外置') : `${t.index}`)
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(accent())
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(4)
          .backgroundColor(AppTheme.withAlpha(accent(), 0.2))
        Blank()
        Text(this.streamLang(t).toUpperCase())
          .fontSize(10)
          .fontColor(subText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 6 })
      }
      .width('100%')
      Text(this.streamCodec(t).toUpperCase())
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(onSurface())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 8 })
      if (t.title.trim().length > 0) {
        Text(t.title)
          .fontSize(11)
          .fontColor(subText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 2 })
      }
      if (this.streamResolution(t).length > 0) {
        Text(this.streamResolution(t))
          .fontSize(10)
          .fontColor(subText())
          .width('100%')
          .margin({ top: 4 })
      }
      if (this.streamAudioInfo(t).length > 0) {
        Text(this.streamAudioInfo(t))
          .fontSize(10)
          .fontColor(subText())
          .width('100%')
          .margin({ top: 4 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width(this.cardWidth())
    .padding(12)
    .borderRadius(12)
    .border({ width: 1, color: AppTheme.withAlpha(subText(), 0.15) })
    .backgroundColor(AppTheme.withAlpha(onSurface(), 0.06))
    .margin({ right: isLast ? 0 : 12, bottom: 12 })
  }

  /** raw 流记录中字符串字段 */
  private rawStr(t: PlayerTrackInfo, key: string): string {
    if (t.raw === undefined) {
      return '';
    }
    return asStr(t.raw[key]).trim();
  }

  private rawNum(t: PlayerTrackInfo, key: string): number {
    if (t.raw === undefined) {
      return 0;
    }
    return Math.round(asNum(t.raw[key]));
  }

  /** raw.tags 子记录 */
  private rawTags(t: PlayerTrackInfo): Record<string, Object> {
    if (t.raw === undefined) {
      return {} as Record<string, Object>;
    }
    const tags = t.raw['tags'];
    if (tags !== undefined && tags !== null && tags instanceof Object && !Array.isArray(tags)) {
      return tags as Record<string, Object>;
    }
    return {} as Record<string, Object>;
  }

  private streamLang(t: PlayerTrackInfo): string {
    const lang = asStr(this.rawTags(t)['language']).trim();
    if (lang.length > 0) {
      return lang;
    }
    return t.language.length > 0 ? t.language : 'und';
  }

  private streamCodec(t: PlayerTrackInfo): string {
    const codec = this.rawStr(t, 'codec_name');
    if (codec.length > 0) {
      return codec;
    }
    return t.codecName.length > 0 ? t.codecName : 'unknown';
  }

  private streamResolution(t: PlayerTrackInfo): string {
    const w = this.rawNum(t, 'width');
    const h = this.rawNum(t, 'height');
    if (w > 0 && h > 0) {
      return `${w}x${h}`;
    }
    return '';
  }

  private streamAudioInfo(t: PlayerTrackInfo): string {
    const channels = this.rawNum(t, 'channels');
    if (channels <= 0) {
      return '';
    }
    const rate = this.rawNum(t, 'sample_rate');
    return `${channels} ch, ${rate > 0 ? rate : ''}Hz`;
  }
}

/** 打开视频信息抽屉（对齐 Flutter VideoInfoDrawer 底部弹层） */
export function showInfoDrawer(ctrl: VideoPlayerController): void {
  const item = ctrl.currentPlaylistItem();
  if (item === undefined || item.path.trim().length === 0) {
    return;
  }
  const p = new InfoDrawerParams();
  p.ctrl = ctrl;
  p.filePath = item.path;
  SheetUtil.present(p, wrapBuilder(InfoDrawerContent));
}
