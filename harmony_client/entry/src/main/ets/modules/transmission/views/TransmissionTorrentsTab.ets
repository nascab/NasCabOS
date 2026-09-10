import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { ThemeManager } from '../../../core/theme/ThemeManager';
import { AppEventBus } from '../../../common/AppEventBus';
import { NavUtil } from '../../../common/NavUtil';
import { AppRouter } from '../../../router/AppRouter';
import { FileBrowserParam } from '../../../files/views/FileBrowserPage';
import { DialogUtil } from '../../../common/DialogUtil';
import { GlassCard } from '../../../common/components/GlassCard';
import { EmptyState } from '../../../common/components/EmptyState';
import { PickOption, showOptionPickSheet } from '../../../common/components/OptionPickSheet';
import { pickTargetFolderViaSheet } from '../../../files/views/FolderPickerSheet';
import { TransmissionController } from '../controllers/TransmissionController';
import { showTorrentFilesSheet } from '../components/TorrentFilesSheet';
import { TorrentRecord } from '../models/TransmissionModels';

/** 筛选 chip 数据（对齐 Flutter _FilterChip 5 项） */
const FILTER_KEYS: string[] = ['all', 'downloading', 'seeding', 'paused', 'error'];
const FILTER_LABEL_KEYS: Record<string, string> = {
  'all': 'transmission_filter_all',
  'downloading': 'transmission_filter_downloading',
  'seeding': 'transmission_filter_seeding',
  'paused': 'transmission_filter_paused',
  'error': 'transmission_filter_error'
};
const FILTER_LABEL_FALLBACK: Record<string, string> = {
  'all': '全部',
  'downloading': '下载中',
  'seeding': '做种',
  'paused': '已暂停',
  'error': '错误'
};

/**
 * 任务标签页（对齐 Flutter _TorrentsTab）：
 * 状态筛选 chips + 排序选择 + 任务卡片列表（进度/大小/速度/操作）。
 */
@ComponentV2
export struct TransmissionTorrentsTab {
  @Param ctrl: TransmissionController = new TransmissionController();
  /** 主题变化刷新计数（AppTheme.current() 非响应式） */
  @Local themeTick: number = 0;
  private themeListener: (data: string) => void = (_data: string): void => {
    this.themeTick++;
  };

  aboutToAppear(): void {
    AppEventBus.on(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
  }

  aboutToDisappear(): void {
    AppEventBus.off(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  /** 已完成任务强调色（对齐 Flutter：浅色 #2E7D32，深色 tertiary → secondary） */
  private completedAccent(): string {
    return AppTheme.isDark() ? this.palette().secondary : '#2E7D32';
  }

  /** 在文件管理中打开下载目录（对齐 _openDownloadDirInFileBrowser：文件路径取父目录） */
  private openDownloadDir(targetPath: string): void {
    const target = targetPath.trim();
    if (target.length === 0) {
      return;
    }
    const extIdx = target.lastIndexOf('.');
    const slashIdx = target.lastIndexOf('/');
    const hasExt = extIdx > slashIdx && extIdx >= 0 && extIdx < target.length - 1;
    const openTarget = hasExt ? (slashIdx > 0 ? target.substring(0, slashIdx) : '/') : target;
    const p = new FileBrowserParam();
    p.initialPath = openTarget;
    p.isRootPage = false;
    NavUtil.push(AppRouter.FILES, p);
  }

  /** 排序选择弹层（对齐 PopupMenuButton + torrentSortKeys） */
  private showSortSheet(): void {
    const options: PickOption[] = this.ctrl.torrentSortKeys.map((key: string): PickOption =>
      new PickOption(key, this.ctrl.torrentSortLabel(key)));
    showOptionPickSheet(L10n.t('sort', '排序'), options, this.ctrl.torrentSortKey,
      (key: string): void => {
        this.ctrl.torrentSortKey = key;
      });
  }

  /** 更改保存目录（对齐 _changeDownloadDir） */
  private changeDownloadDir(id: number, currentDir: string): void {
    pickTargetFolderViaSheet(currentDir, (paths: string[]): void => {
      if (paths.length === 0) {
        return;
      }
      const next = paths[0].trim();
      if (next.length === 0 || next === currentDir) {
        return;
      }
      void this.ctrl.setTorrentDownloadDir(id, next);
    });
  }

  /** 删除任务（对齐 TextButton 删除 + showConfirmDialog） */
  private confirmRemoveTorrent(id: number): void {
    DialogUtil.showConfirmDialog(L10n.t('confirm', '确认'),
      L10n.t('transmission_remove_confirm', '确定删除该任务吗？'), (): void => {
        void this.ctrl.removeTorrent(id);
      });
  }

  build() {
    Column() {
      if (!this.ctrl.isRunning()) {
        // 服务未运行（对齐 Center(Text)）
        Column() {
          Text(L10n.t('transmission_service_not_running', 'Transmission 服务未运行'))
            .fontSize(14)
            .fontColor(this.palette().subText)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        // 筛选 chips 行
        Scroll() {
          Row({ space: 8 }) {
            ForEach(FILTER_KEYS, (key: string) => {
              this.FilterChip(key)
            }, (key: string): string => key)
          }
          .padding({ left: 12, right: 12 })
        }
        .width('100%')
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .margin({ top: 12 })
        .opacity(this.themeTick >= 0 ? 1 : 1)

        // 排序行（对齐 sort 标签 + 右对齐下拉）
        Row() {
          Text(L10n.t('sort', '排序'))
            .fontSize(13)
            .fontColor(AppTheme.withAlpha(this.palette().onSurface, 0.75))
          Blank()
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.text_arrow_up_and_down'))
              .fontSize(15)
              .fontColor([this.palette().primary])
            Text(this.ctrl.torrentSortLabel(this.ctrl.torrentSortKey))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().primary)
              .maxLines(1)
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(14)
              .fontColor([this.palette().primary])
          }
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onClick((): void => {
            this.showSortSheet();
          })
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 8 })

        // 任务列表
        if (this.ctrl.displayTorrents.length === 0) {
          Column() {
            EmptyState({
              message: L10n.t('transmission_no_torrents', '暂无下载任务'),
              imagePath: $rawfile('icons/no_data.png')
            })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 10 }) {
            ForEach(this.ctrl.displayTorrents, (t: TorrentRecord) => {
              ListItem() {
                this.TorrentCard(t)
              }
            }, (t: TorrentRecord): string =>
              `${t.id}_${t.status}_${t.percentDone}_${t.rateDownload}_${t.rateUpload}_${t.downloadDir}`)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 12, right: 12, bottom: 12 })
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 状态筛选 chip（对齐 FilterChip 选中主色浅底） */
  @Builder
  FilterChip(key: string) {
    Text(L10n.t(FILTER_LABEL_KEYS[key], FILTER_LABEL_FALLBACK[key]))
      .fontSize(13)
      .fontColor(this.ctrl.torrentFilter === key
        ? this.palette().primary : this.palette().onSurface)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .borderRadius(18)
      .border({
        width: 1,
        color: this.ctrl.torrentFilter === key ? this.palette().primary : this.palette().divider
      })
      .backgroundColor(this.ctrl.torrentFilter === key
        ? AppTheme.withAlpha(this.palette().primary, 0.12)
        : AppTheme.withAlpha(this.palette().onSurface, 0.05))
      .maxLines(1)
      .onClick((): void => {
        this.ctrl.torrentFilter = key;
      })
  }

  /** 任务卡片（对齐 _TorrentCard） */
  @Builder
  TorrentCard(t: TorrentRecord) {
    GlassCard({ padValue: 12 }) {
      this.TorrentCardContent(t)
    }
  }

  @Builder
  TorrentCardContent(t: TorrentRecord) {
    Column({ space: 8 }) {
      // 行 1：完成图标 + 名称 + 已完成徽标
      Row() {
        if (this.ctrl.isTorrentFinished(t)) {
          SymbolGlyph($r('sys.symbol.checkmark_circle'))
            .fontSize(18)
            .fontColor([this.completedAccent()])
            .margin({ right: 8 })
        }
        Text(t.name.length > 0 ? t.name : '-')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.finishedNameColor(t))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.ctrl.isTorrentFinished(t)) {
          Text(L10n.t('completed', '已完成'))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.completedAccent())
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(999)
            .backgroundColor(this.finishedBadgeBg())
            .margin({ left: 8 })
        }
      }
      .alignItems(VerticalAlign.Top)
      .width('100%')

      // 行 2：保存目录（查看 + 路径）
      if (t.downloadDir.length > 0) {
        Row({ space: 8 }) {
          Text(`[${L10n.t('perm_view', '查看')}]`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().primary)
            .onClick((): void => {
              this.openDownloadDir(t.downloadDir);
            })
          Text(t.downloadDir)
            .fontSize(12)
            .fontColor(this.palette().subText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
      }

      // 行 3：进度条（完成态用强调色）
      Progress({
        value: this.progressPercent(t),
        total: 100,
        type: ProgressType.Linear
      })
        .color(this.ctrl.isTorrentFinished(t) ? this.completedAccent() : this.palette().primary)
        .width('100%')

      // 行 4：大小 / 分享率 / 已上传
      Row({ space: 16 }) {
        Text(`${this.ctrl.formatBytes(this.ctrl.torrentDisplayDownloadedBytes(t))} / `
          + `${this.ctrl.formatBytes(this.ctrl.torrentDisplayTotalSize(t))}`)
          .fontSize(12)
          .fontColor(this.mutedText(t))
        Text(`${L10n.t('transmission_share_ratio', '分享率')}: ${this.ctrl.formatRatio(t.uploadRatio)}`)
          .fontSize(12)
          .fontColor(this.palette().subText)
        Text(`${L10n.t('transmission_torrent_uploaded', '已上传')}: ${this.ctrl.formatBytes(t.uploadedEver)}`)
          .fontSize(12)
          .fontColor(this.palette().subText)
      }
      .width('100%')

      // 行 5：状态 + 百分比 + 速度
      Row({ space: 12 }) {
        Text(this.ctrl.statusLabelForTorrent(t))
          .fontSize(12)
          .fontWeight(this.ctrl.isTorrentFinished(t) ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.ctrl.isTorrentFinished(t) ? this.completedAccent() : this.palette().subText)
        Text(`${(t.percentDone * 100).toFixed(1)}%`)
          .fontSize(12)
          .fontColor(this.mutedText(t))
        Text(`↓ ${this.ctrl.formatSpeed(t.rateDownload)}`)
          .fontSize(12)
          .fontColor(this.palette().subText)
        Text(`↑ ${this.ctrl.formatSpeed(t.rateUpload)}`)
          .fontSize(12)
          .fontColor(this.palette().subText)
      }
      .width('100%')

      // 行 6：操作按钮（右对齐，对齐 TextButton 行）
      Row({ space: 4 }) {
        if (this.ctrl.isOpLoading(t.id)) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(this.palette().primary)
        } else {
          if (!this.ctrl.isTorrentFinished(t)) {
            this.CardTextButton(L10n.t('transmission_select_files', '选择文件'), (): void => {
              showTorrentFilesSheet(this.ctrl, t.id, t.name);
            })
            this.CardTextButton(L10n.t('transmission_change_download_dir', '更改目录'), (): void => {
              this.changeDownloadDir(t.id, t.downloadDir);
            })
            if (this.ctrl.canShowTorrentStart(t)) {
              this.CardTextButton(L10n.t('transmission_torrent_start', '开始'), (): void => {
                void this.ctrl.startTorrent(t.id);
              })
            }
            if (this.ctrl.canShowTorrentPause(t)) {
              this.CardTextButton(L10n.t('transmission_torrent_pause', '暂停'), (): void => {
                void this.ctrl.stopTorrent(t.id);
              })
            }
          }
          this.CardTextButton(L10n.t('delete', '删除'), (): void => {
            this.confirmRemoveTorrent(t.id);
          }, true)
        }
      }
      .justifyContent(FlexAlign.End)
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  /** 卡片文字按钮（对齐 Flutter TextButton：主色文字） */
  @Builder
  CardTextButton(label: string, onTap: () => void, danger: boolean = false) {
    Text(label)
      .fontSize(13)
      .fontColor(danger ? this.palette().error : this.palette().primary)
      .padding({ left: 8, right: 8, top: 6, bottom: 6 })
      .onClick((): void => {
        onTap();
      })
  }

  /** 已完成名称颜色（对齐 Flutter 深色完成后 78% 透明） */
  private finishedNameColor(t: TorrentRecord): string {
    if (this.ctrl.isTorrentFinished(t) && AppTheme.isDark()) {
      return AppTheme.withAlpha(this.palette().onSurface, 0.78);
    }
    return this.palette().onSurface;
  }

  private mutedText(t: TorrentRecord): string {
    if (this.ctrl.isTorrentFinished(t) && AppTheme.isDark()) {
      return AppTheme.withAlpha(this.palette().onSurface, 0.72);
    }
    return this.palette().subText;
  }

  private finishedBadgeBg(): string {
    if (AppTheme.isDark()) {
      return AppTheme.withAlpha(this.completedAccent(), 0.18);
    }
    return '#E8F5E9';
  }

  /** 进度百分比 0-100（完成态固定 100，对齐 Flutter value: 1.0） */
  private progressPercent(t: TorrentRecord): number {
    if (this.ctrl.isTorrentFinished(t)) {
      return 100;
    }
    return Math.min(Math.max(t.percentDone * 100, 0), 100);
  }
}
