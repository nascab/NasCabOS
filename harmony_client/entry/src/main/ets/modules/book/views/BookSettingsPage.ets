import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { PageScaffold } from '../../../common/PageScaffold';
import { ToastUtil } from '../../../common/ToastUtil';
import { DialogUtil, DialogResult } from '../../../common/DialogUtil';
import { EmptyState } from '../../../common/components/EmptyState';
import { GlassCard } from '../../../common/components/GlassCard';
import { PickOption, showOptionPickSheet } from '../../../common/components/OptionPickSheet';
import { CurrentUserStore } from '../../../core/user/CurrentUserStore';
import { BookSourceSettingsController } from '../controllers/BookControllers';
import { BookSource } from '../models/BookModels';
import { BookLocalCacheService, BookCacheEntry } from '../services/BookLocalCacheService';
import { pickTargetFolderViaSheet } from '../../../files/views/FolderPickerSheet';
import { FileFormat } from '../../../files/models/FileModels';

/**
 * 图书设置页（对齐 Flutter _AppBookSettingsTab）：
 * 管理员显示 来源设置/缓存下载 两个标签；非管理员仅缓存下载。
 */
@ComponentV2
export struct BookSettingsPage {
  @Param popPage: () => void = (): void => {
  };
  /** 0 来源（管理员） 1 缓存下载 */
  @Local settingsTab: number = 0;
  private isAdmin: boolean = CurrentUserStore.getInstance().isAdmin;

  aboutToAppear(): void {
    this.settingsTab = this.isAdmin ? 0 : 1;
  }

  build() {
    PageScaffold({
      title: L10n.t('setting', '设置'),
      showBack: true,
      onBack: (): void => {
        this.popPage();
      },
      content: (): void => {
        this.PageBody()
      }
    })
  }

  @Builder
  PageBody() {
    Column() {
      if (this.isAdmin) {
        Row({ space: 24 }) {
          this.TopTabChip(L10n.t('settings_source', '来源设置'), 0)
          this.TopTabChip(L10n.t('book_menu_settings_cache_download', '缓存下载'), 1)
        }
        .width('100%')
        .height(44)
        .padding({ left: 16, right: 16 })

        if (this.settingsTab === 0) {
          BookSourceSettingsView()
        } else {
          BookCacheDownloadView()
        }
      } else {
        BookCacheDownloadView()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.current().pageBg)
  }

  @Builder
  TopTabChip(label: string, index: number) {
    Column() {
      Text(label)
        .fontSize(14)
        .fontWeight(this.settingsTab === index ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.settingsTab === index ? AppTheme.current().primary
          : AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
      Rect()
        .width(24)
        .height(2.5)
        .radius(1.25)
        .fill(this.settingsTab === index ? AppTheme.current().primary : Color.Transparent)
        .margin({ top: 3 })
    }
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.settingsTab = index;
    })
  }
}

/**
 * 图书来源设置视图（对齐 Flutter BookSourceSettingsView 移动端形态）：
 * 标题行（全部扫描/刷新）+ 来源卡片列表 + 添加来源卡片。
 */
@ComponentV2
export struct BookSourceSettingsView {
  ctrl: BookSourceSettingsController = new BookSourceSettingsController();

  aboutToAppear(): void {
    this.ctrl = new BookSourceSettingsController();
    this.ctrl.onInit();
  }

  private pickAndAdd(): void {
    pickTargetFolderViaSheet('', (paths: string[]): void => {
      if (paths.length === 0) {
        return;
      }
      void this.ctrl.addSources(paths);
    }, true);
  }

  private confirmRelocate(source: BookSource): void {
    DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('photo_source_relocate_confirm', '确定要重新定位该来源目录吗？'),
      (): void => {
        pickTargetFolderViaSheet('', (paths: string[]): void => {
          if (paths.length === 0) {
            return;
          }
          void this.ctrl.relocateSource(source, paths[0]);
        });
      },
      L10n.confirm,
      L10n.cancel);
  }

  private confirmDelete(source: BookSource): void {
    DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('book_source_delete_confirm', '确定删除来源目录：@path？', L10n.paramsOf('path', source.path)),
      (): void => {
        void this.ctrl.deleteSourceOptimistic(source);
      },
      L10n.t('delete', '删除'),
      L10n.cancel);
  }

  private showHelp(message: string): void {
    void DialogUtil.showInfoDialog(L10n.t('tip', '提示'), message);
  }

  private openHoursPicker(source: BookSource): void {
    const options: PickOption[] = [];
    for (let h = 1; h <= 24; h++) {
      options.push(new PickOption(`${h}`, `${h}`));
    }
    showOptionPickSheet(L10n.t('book_source_scan_interval_hours', '扫描间隔（小时）'), options,
      `${this.ctrl.getIntervalHours(source)}`, (key: string): void => {
        void this.ctrl.updateSourceOptimistic(source, undefined, undefined, 1,
          parseInt(key, 10) * 3600 * 1000);
      });
  }

  private openShowTypePicker(source: BookSource): void {
    const current = source.showType.length > 0 ? source.showType : 'book';
    const options: PickOption[] = [
      new PickOption('book', L10n.t('file', '文件')),
      new PickOption('series', L10n.t('dir', '目录'))
    ];
    showOptionPickSheet(L10n.t('book_source_show_type', '展示类型'), options, current,
      (key: string): void => {
        if (key === current) {
          return;
        }
        DialogUtil.showConfirmDialog(
          L10n.t('need_confirm', '需要确认'),
          L10n.t('book_source_show_type_switch_confirm', '切换展示类型将重建该来源的索引，确定继续？'),
          (): void => {
            void this.ctrl.updateSourceOptimistic(source, undefined, undefined, undefined, undefined, key);
          },
          L10n.ok,
          L10n.cancel);
      });
  }

  private toggleInterval(source: BookSource, value: boolean): void {
    if (value) {
      const ms = this.ctrl.getIntervalHours(source) * 3600 * 1000;
      void this.ctrl.updateSourceOptimistic(source, undefined, undefined, 1, ms);
    } else {
      void this.ctrl.updateSourceOptimistic(source, undefined, undefined, 0, 0);
    }
  }

  build() {
    Column() {
      // 标题行：来源设置 + 全部扫描 + 刷新
      Row({ space: 10 }) {
        Text(L10n.t('settings_source', '来源设置'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
        Text(L10n.t('book_source_scan_all', '全部扫描'))
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .padding({ left: 4, right: 4, top: 6, bottom: 6 })
          .onClick(() => {
            void this.ctrl.scanSource('all');
          })
        Blank()
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(20)
          .fontColor([AppTheme.current().onSurface])
          .padding(6)
          .onClick(() => {
            void this.ctrl.fetchSources();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })

      if (this.ctrl.loadingSources && this.ctrl.sources.length === 0) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(AppTheme.current().primary)
        }
        .layoutWeight(1)
        .width('100%')
      } else if (this.ctrl.sources.length === 0) {
        Column() {
          EmptyState({ message: L10n.t('book_source_add_card', '添加图书来源目录') })
        }
        .layoutWeight(1)
      } else {
        List() {
          ForEach(this.ctrl.sources, (s: BookSource) => {
            ListItem() {
              this.SourceCard(s)
            }
            .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          }, (s: BookSource) => `${s.id}_${s.path}_${s.showType}_${s.scanWhenStart}_${s.scanWhenChange}_${s.scanIntervalMs}`)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }

      // 添加来源卡片（对齐 _MobileAddSourceCard）
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.plus_circle'))
          .fontSize(20)
          .fontColor([AppTheme.current().primary])
        Text(L10n.t('book_source_add_card', '添加图书来源目录'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
        SymbolGlyph($r('sys.symbol.questionmark_circle'))
          .fontSize(16)
          .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.45)])
          .onClick(() => {
            this.showHelp(L10n.t('book_source_help_add_source', '添加一个目录作为图书来源'));
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 14, bottom: 14 })
      .margin({ left: 16, right: 16, bottom: 16 })
      .borderRadius(14)
      .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.9))
      .onClick(() => {
        this.pickAndAdd();
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  SwitchRow(title: string, helpMessage: string, value: boolean, onChanged: (v: boolean) => void) {
    Row() {
      Row({ space: 4 }) {
        Text(title)
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
        SymbolGlyph($r('sys.symbol.questionmark_circle'))
          .fontSize(16)
          .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.45)])
          .onClick(() => {
            this.showHelp(helpMessage);
          })
      }
      Blank()
      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(AppTheme.current().primary)
        .onChange((v: boolean): void => {
          onChanged(v);
        })
    }
    .width('100%')
    .margin({ top: 8, bottom: 4 })
  }

  @Builder
  SourceCard(s: BookSource) {
    GlassCard({
      padValue: 12,
      bgOpacity: 0.9
    }) {
      Column() {
        Text(s.path)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row({ space: 8 }) {
          Text(`[${s.exists ? L10n.t('book_source_available', '可用') : L10n.t('book_source_unavailable', '不可用')}]`)
            .fontSize(12)
            .fontColor(s.exists ? '#4CAF50' : '#F44336')
          Blank()
          if (!s.exists) {
            Text(L10n.t('photo_source_relocate', '重定位'))
              .fontSize(13)
              .fontColor(AppTheme.current().primary)
              .padding({ left: 6, top: 4, bottom: 4 })
              .onClick(() => {
                this.confirmRelocate(s);
              })
          }
          if (s.exists) {
            Text(L10n.t('book_source_scan_now', '立即扫描'))
              .fontSize(13)
              .fontColor(AppTheme.current().primary)
              .padding({ left: 6, top: 4, bottom: 4 })
              .onClick(() => {
                void this.ctrl.scanSource(s.path);
              })
          }
          Text(L10n.t('delete', '删除'))
            .fontSize(13)
            .fontColor(AppTheme.current().error)
            .padding({ left: 6, right: 4, top: 4, bottom: 4 })
            .onClick(() => {
              this.confirmDelete(s);
            })
        }
        .width('100%')
        .margin({ top: 8 })

        this.SwitchRow(L10n.t('book_source_scan_when_start', '启动时扫描'),
          L10n.t('book_source_help_scan_when_start', '服务器启动时扫描该目录'),
          s.scanWhenStart === 1, (v: boolean): void => {
            void this.ctrl.updateSourceOptimistic(s, v ? 1 : 0);
          })
        this.SwitchRow(L10n.t('book_source_scan_when_change', '变更时扫描'),
          L10n.t('book_source_help_scan_when_change', '目录内容变化时自动扫描'),
          s.scanWhenChange === 1, (v: boolean): void => {
            void this.ctrl.updateSourceOptimistic(s, undefined, v ? 1 : 0);
          })

        // 定时扫描
        Row() {
          Row({ space: 4 }) {
            Text(L10n.t('book_source_scan_interval', '定时扫描'))
              .fontSize(14)
              .fontColor(AppTheme.current().onSurface)
            SymbolGlyph($r('sys.symbol.questionmark_circle'))
              .fontSize(16)
              .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.45)])
              .onClick(() => {
                this.showHelp(L10n.t('book_source_help_scan_interval', '按设定间隔定时扫描该目录'));
              })
          }
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.ctrl.getIntervalEnabled(s) })
            .selectedColor(AppTheme.current().primary)
            .onChange((v: boolean): void => {
              this.toggleInterval(s, v);
            })
        }
        .width('100%')
        .margin({ top: 8, bottom: 4 })

        if (this.ctrl.getIntervalEnabled(s)) {
          Row() {
            Text(L10n.t('book_source_scan_interval_hours', '扫描间隔（小时）'))
              .fontSize(14)
              .fontColor(AppTheme.current().onSurface)
            Blank()
            Text(`${this.ctrl.getIntervalHours(s)}`)
              .fontSize(14)
              .fontColor(AppTheme.current().primary)
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(14)
              .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.5)])
              .margin({ left: 6 })
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
          .onClick(() => {
            this.openHoursPicker(s);
          })
        }

        // 展示类型
        Row() {
          Row({ space: 4 }) {
            Text(L10n.t('book_source_show_type', '展示类型'))
              .fontSize(14)
              .fontColor(AppTheme.current().onSurface)
            SymbolGlyph($r('sys.symbol.questionmark_circle'))
              .fontSize(16)
              .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.45)])
              .onClick(() => {
                this.showHelp(L10n.t('book_source_show_type_switch_confirm',
                  '切换展示类型将重建该来源的索引，确定继续？'));
              })
          }
          Blank()
          Text(s.showType === 'series' ? L10n.t('dir', '目录') : L10n.t('file', '文件'))
            .fontSize(14)
            .fontColor(AppTheme.current().primary)
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(14)
            .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.5)])
            .margin({ left: 6 })
        }
        .width('100%')
        .padding({ top: 4, bottom: 4 })
        .onClick(() => {
          this.openShowTypePicker(s);
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }
}

/**
 * 图书缓存下载视图（对齐 Flutter BookCacheDownloadView）：
 * 标题行（总大小/清空）+ 缓存条目列表（文件名/hash/路径/大小/删除）。
 */
@ComponentV2
export struct BookCacheDownloadView {
  @Local entries: BookCacheEntry[] = [];
  @Local loaded: boolean = false;

  aboutToAppear(): void {
    this.reload();
  }

  private reload(): void {
    this.entries = BookLocalCacheService.getInstance().listCacheEntries();
    this.loaded = true;
  }

  private totalSize(): number {
    let sum = 0;
    for (const e of this.entries) {
      sum += e.sizeBytes;
    }
    return sum;
  }

  private baseName(path: string): string {
    const p = path.replace(/\\/g, '/');
    const idx = p.lastIndexOf('/');
    return idx >= 0 ? p.substring(idx + 1) : p;
  }

  private deleteOne(entry: BookCacheEntry): void {
    DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('book_cache_delete_one_confirm', '确定删除缓存：@fileHash？',
        L10n.paramsOf('fileHash', entry.fileHash)),
      undefined,
      L10n.ok,
      L10n.cancel,
      false)
      .then((ok: DialogResult | undefined): void => {
        if (ok !== true) {
          return;
        }
        BookLocalCacheService.getInstance().deleteCache(entry.fileHash);
        ToastUtil.show(L10n.t('delete_success', '删除成功'));
        this.reload();
      });
  }

  private deleteAll(): void {
    DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('book_cache_delete_all_confirm', '确定清空全部图书缓存？'),
      undefined,
      L10n.ok,
      L10n.cancel,
      false)
      .then((ok: DialogResult | undefined): void => {
        if (ok !== true) {
          return;
        }
        BookLocalCacheService.getInstance().clearAllCaches();
        ToastUtil.show(L10n.t('operation_success', '操作成功'));
        this.reload();
      });
  }

  build() {
    Column() {
      // 标题行：缓存下载 + 总大小 + 清空
      Row({ space: 8 }) {
        Text(L10n.t('book_cache_download_title', '缓存下载'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
        if (this.totalSize() > 0) {
          Text(`(${FileFormat.formatSize(this.totalSize())})`)
            .fontSize(13)
            .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
        }
        Blank()
        SymbolGlyph($r('sys.symbol.trash_fill'))
          .fontSize(20)
          .fontColor([AppTheme.current().error])
          .padding(6)
          .onClick(() => {
            this.deleteAll();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })

      Column() {
        if (!this.loaded) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(AppTheme.current().primary)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.entries.length === 0) {
          Column() {
            Text(L10n.t('book_cache_empty', '暂无缓存'))
              .fontSize(14)
              .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 0 }) {
            ForEach(this.entries, (e: BookCacheEntry) => {
              ListItem() {
                Column({ space: 2 }) {
                  Row({ space: 8 }) {
                    Column({ space: 2 }) {
                      Text(this.baseName(e.filePath))
                        .fontSize(14)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(AppTheme.current().onSurface)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                      Text(e.fileHash)
                        .fontSize(12)
                        .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.7))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                      Text(e.filePath)
                        .fontSize(11)
                        .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.55))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    Text(FileFormat.formatSize(e.sizeBytes))
                      .fontSize(12)
                      .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.8))
                    SymbolGlyph($r('sys.symbol.trash'))
                      .fontSize(18)
                      .fontColor([AppTheme.current().error])
                      .padding(6)
                      .onClick(() => {
                        this.deleteOne(e);
                      })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                  .padding({ top: 10, bottom: 10 })
                  Divider()
                    .color(AppTheme.current().divider)
                    .strokeWidth(0.8)
                }
                .width('100%')
              }
            }, (e: BookCacheEntry): string => `${e.fileHash}_${e.sizeBytes}`)
          }
          .width('100%')
          .height('100%')
          .padding({ left: 12, right: 12 })
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
        }
      }
      .layoutWeight(1)
      .width('100%')
      .margin({ left: 16, right: 16, bottom: 16 })
      .borderRadius(16)
      .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.55))
      .border({ width: 1, color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.06) })
      .clip(true)
    }
    .width('100%')
    .height('100%')
  }
}
