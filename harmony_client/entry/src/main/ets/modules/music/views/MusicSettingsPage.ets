import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { PageScaffold } from '../../../common/PageScaffold';
import { ToastUtil } from '../../../common/ToastUtil';
import { DialogUtil } from '../../../common/DialogUtil';
import { EmptyState } from '../../../common/components/EmptyState';
import { CurrentUserStore } from '../../../core/user/CurrentUserStore';
import { PickOption, showOptionPickSheet } from '../../../common/components/OptionPickSheet';
import { MusicSourceController, MusicCacheSettingsController } from '../controllers/MusicSettingControllers';
import { MusicSource } from '../models/MusicModels';
import { pickTargetFolderViaSheet } from '../../../files/views/FolderPickerSheet';
import { FileFormat } from '../../../files/models/FileModels';

/**
 * 音乐设置页（对齐 Flutter _AppMusicSettingsTab）：
 * 管理员显示 来源/缓存 两个标签；非管理员仅缓存标签。
 */
@ComponentV2
export struct MusicSettingsPage {
  @Param popPage: () => void = (): void => {
  };
  /** 0 来源（管理员） 1 缓存 */
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
        // 标签切换（对齐 Flutter TabBar：settings_source / music_menu_settings_cache）
        Row({ space: 24 }) {
          this.TopTabChip(L10n.t('settings_source', '来源设置'), 0)
          this.TopTabChip(L10n.t('music_menu_settings_cache', '缓存设置'), 1)
        }
        .width('100%')
        .height(44)
        .padding({ left: 16, right: 16 })

        if (this.settingsTab === 0) {
          MusicSourceSettingsView()
        } else {
          MusicCacheSettingsView()
        }
      } else {
        MusicCacheSettingsView()
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
 * 音乐来源设置视图（对齐 Flutter MusicSourceSettingsView 移动端形态）：
 * 标题行（全部扫描/刷新）+ 来源卡片列表 + 添加来源卡片。
 */
@ComponentV2
export struct MusicSourceSettingsView {
  ctrl: MusicSourceController = new MusicSourceController();

  aboutToAppear(): void {
    this.ctrl = new MusicSourceController();
    this.ctrl.onInit();
  }

  /** 添加来源：文件夹多选（对齐 Flutter _pickAndAdd multiSelect: true） */
  private pickAndAdd(): void {
    pickTargetFolderViaSheet('', (paths: string[]): void => {
      if (paths.length === 0) {
        return;
      }
      void this.ctrl.addSources(paths);
    }, true);
  }

  /** 重新定位（确认 + 单选文件夹，对齐 Flutter relocate） */
  private confirmRelocate(source: MusicSource): void {
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

  /** 删除来源（对齐 Flutter delete 确认） */
  private confirmDelete(source: MusicSource): void {
    DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('music_source_delete_confirm', '确定删除来源目录：@path？', L10n.paramsOf('path', source.path)),
      (): void => {
        void this.ctrl.deleteSourceOptimistic(source);
      },
      L10n.t('delete', '删除'),
      L10n.cancel);
  }

  /** 帮助信息弹窗（对齐 Flutter help IconButton） */
  private showHelp(message: string): void {
    void DialogUtil.showInfoDialog(L10n.t('tip', '提示'), message);
  }

  /** 定时扫描小时选择（对齐 Flutter DropdownButton 1-24） */
  private openHoursPicker(source: MusicSource): void {
    const options: PickOption[] = [];
    for (let h = 1; h <= 24; h++) {
      options.push(new PickOption(`${h}`, `${h}`));
    }
    showOptionPickSheet(L10n.t('music_source_scan_interval_hours', '扫描间隔（小时）'), options,
      `${this.ctrl.getIntervalHours(source)}`, (key: string): void => {
        void this.ctrl.updateSourceOptimistic(source, undefined, undefined, 1,
          parseInt(key, 10) * 3600 * 1000);
      });
  }

  /** 展示类型选择（music=file / series=dir，切换需确认） */
  private openShowTypePicker(source: MusicSource): void {
    const current = source.showType.length > 0 ? source.showType : 'music';
    const options: PickOption[] = [
      new PickOption('music', L10n.t('file', '文件')),
      new PickOption('series', L10n.t('dir', '目录'))
    ];
    showOptionPickSheet(L10n.t('music_source_show_type', '展示类型'), options, current, (key: string): void => {
      if (key === current) {
        return;
      }
      DialogUtil.showConfirmDialog(
        L10n.t('need_confirm', '需要确认'),
        L10n.t('music_source_show_type_switch_confirm', '切换展示类型将重建该来源的索引，确定继续？'),
        (): void => {
          void this.ctrl.updateSourceOptimistic(source, undefined, undefined, undefined, undefined, key);
        },
        L10n.ok,
        L10n.cancel);
    });
  }

  /** 定时扫描开关切换 */
  private toggleInterval(source: MusicSource, value: boolean): void {
    if (value) {
      const ms = Math.min(Math.max(this.ctrl.getIntervalHours(source), 1), 24) * 3600 * 1000;
      void this.ctrl.updateSourceOptimistic(source, undefined, undefined, 1, ms);
    } else {
      void this.ctrl.updateSourceOptimistic(source, undefined, undefined, 0, 0);
    }
  }

  build() {
    Column() {
      // 标题行：来源 + 全部扫描 + 刷新
      Row({ space: 10 }) {
        Text(L10n.t('settings_source', '来源设置'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
        Text(L10n.t('music_source_scan_all', '全部扫描'))
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
            void this.ctrl.fetchSources(true);
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })

      if (this.ctrl.sources.length === 0) {
        Column() {
          EmptyState({ message: L10n.t('music_source_add_card', '添加音乐来源目录') })
        }
        .layoutWeight(1)
      } else {
        List() {
          ForEach(this.ctrl.sources, (s: MusicSource) => {
            ListItem() {
              this.SourceCard(s)
            }
            .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          }, (s: MusicSource) => `${s.id}_${s.path}`)
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
        Text(L10n.t('music_source_add_card', '添加音乐来源目录'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
        SymbolGlyph($r('sys.symbol.questionmark_circle'))
          .fontSize(16)
          .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.45)])
          .onClick(() => {
            this.showHelp(L10n.t('music_source_help_add_source', '添加一个目录作为音乐来源'));
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
  SourceCard(s: MusicSource) {
    Column() {
      // 路径 + 状态
      Text(s.path)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.current().onSurface)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Row({ space: 8 }) {
        Text(`[${s.exists ? L10n.t('music_source_available', '可用') : L10n.t('music_source_unavailable', '不可用')}]`)
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
          Text(L10n.t('music_source_scan_now', '立即扫描'))
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

      this.SwitchRow(L10n.t('music_source_scan_when_start', '启动时扫描'),
        L10n.t('music_source_help_scan_when_start', '服务器启动时扫描该目录'),
        s.scanWhenStart, (v: boolean): void => {
          void this.ctrl.updateSourceOptimistic(s, v ? 1 : 0);
        })
      this.SwitchRow(L10n.t('music_source_scan_when_change', '变更时扫描'),
        L10n.t('music_source_help_scan_when_change', '目录内容变化时自动扫描'),
        s.scanWhenChange, (v: boolean): void => {
          void this.ctrl.updateSourceOptimistic(s, undefined, v ? 1 : 0);
        })

      // 定时扫描
      Row() {
        Row({ space: 4 }) {
          Text(L10n.t('music_source_scan_interval', '定时扫描'))
            .fontSize(14)
            .fontColor(AppTheme.current().onSurface)
          SymbolGlyph($r('sys.symbol.questionmark_circle'))
            .fontSize(16)
            .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.45)])
            .onClick(() => {
              this.showHelp(L10n.t('music_source_help_scan_interval', '按设定间隔定时扫描该目录'));
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
          Text(L10n.t('music_source_scan_interval_hours', '扫描间隔（小时）'))
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
          Text(L10n.t('music_source_show_type', '展示类型'))
            .fontSize(14)
            .fontColor(AppTheme.current().onSurface)
          SymbolGlyph($r('sys.symbol.questionmark_circle'))
            .fontSize(16)
            .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.45)])
            .onClick(() => {
              this.showHelp(L10n.t('music_source_show_type_switch_confirm', '切换展示类型将重建该来源的索引，确定继续？'));
            })
        }
        Blank()
        Text(s.showType.length > 0 && s.showType === 'series' ? L10n.t('dir', '目录') : L10n.t('file', '文件'))
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
    .padding(12)
    .borderRadius(14)
    .border({ width: 0.8, color: AppTheme.withAlpha(AppTheme.current().divider, 0.8) })
    .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.9))
  }

  @Builder
  SwitchRow(title: string, help: string, value: boolean, onChanged: (v: boolean) => void) {
    Row() {
      Row({ space: 4 }) {
        Text(title)
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
        SymbolGlyph($r('sys.symbol.questionmark_circle'))
          .fontSize(16)
          .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.45)])
          .onClick(() => {
            this.showHelp(help);
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
    .margin({ top: 4, bottom: 4 })
  }
}

/**
 * 音乐缓存设置视图（对齐 Flutter MusicCacheSettingsView）：
 * 选项卡片（启用开关 + 最大条目）+ 统计卡片（条目数/占用空间/清空按钮）。
 */
@ComponentV2
export struct MusicCacheSettingsView {
  ctrl: MusicCacheSettingsController = new MusicCacheSettingsController();
  @Local private maxItemsText: string = '';

  aboutToAppear(): void {
    this.ctrl = new MusicCacheSettingsController();
    this.maxItemsText = `${this.ctrl.playCtrl.audioCacheMaxItems}`;
    void this.ctrl.refreshStats(false);
  }

  private parseMaxItems(): number {
    const raw = this.maxItemsText.trim();
    if (raw.length === 0) {
      return -1;
    }
    const v = parseInt(raw, 10);
    return Number.isNaN(v) ? -1 : v;
  }

  private async applyMaxItems(): Promise<void> {
    const v = this.parseMaxItems();
    if (v < 0) {
      ToastUtil.show(L10n.t('music_cache_settings_invalid_max_items', '请输入有效的最大缓存条目数'));
      return;
    }
    await this.ctrl.setMaxItems(v);
    this.maxItemsText = `${this.ctrl.playCtrl.audioCacheMaxItems}`;
  }

  private async clearCache(): Promise<void> {
    await this.ctrl.clearCache();
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }

  build() {
    Column() {
      // 标题行
      Row({ space: 10 }) {
        Text(L10n.t('music_cache_settings_title', '音频缓存'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
        Blank()
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(20)
          .fontColor([AppTheme.current().onSurface])
          .padding(6)
          .onClick(() => {
            void this.ctrl.refreshStats(false);
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })

      List() {
        // 选项卡片
        ListItem() {
          Column() {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.slider_horizontal_2'))
                .fontSize(18)
                .fontColor([AppTheme.current().onSurface])
              Text(L10n.t('music_cache_settings_section_options', '选项'))
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppTheme.current().onSurface)
            }
            .width('100%')

            Row() {
              Column({ space: 4 }) {
                Text(L10n.t('music_cache_settings_enabled', '启用音频缓存'))
                  .fontSize(14)
                  .fontColor(AppTheme.current().onSurface)
                Text(L10n.t('music_cache_settings_enabled_tip', '播放过的音频将缓存到本地，断网或重播时更快加载'))
                  .fontSize(12)
                  .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.55))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.ctrl.enabled })
                .selectedColor(AppTheme.current().primary)
                .onChange((v: boolean): void => {
                  void this.ctrl.toggleEnabled(v);
                })
            }
            .width('100%')
            .margin({ top: 12 })

            Row({ space: 10 }) {
              TextInput({ text: this.maxItemsText })
                .type(InputType.Number)
                .enabled(this.ctrl.enabled)
                .fontSize(14)
                .height(42)
                .layoutWeight(1)
                .borderRadius(10)
                .backgroundColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.06))
                .placeholderColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.35))
                .onChange((v: string): void => {
                  this.maxItemsText = v;
                })
              Button(L10n.t('music_cache_settings_apply', '应用'))
                .fontSize(14)
                .height(42)
                .borderRadius(10)
                .backgroundColor(AppTheme.current().primary)
                .opacity(this.ctrl.enabled ? 1 : 0.5)
                .enabled(this.ctrl.enabled)
                .onClick(() => {
                  void this.applyMaxItems();
                })
            }
            .width('100%')
            .margin({ top: 10 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(12)
          .borderRadius(14)
          .border({ width: 0.8, color: AppTheme.withAlpha(AppTheme.current().divider, 0.8) })
          .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.9))
        }
        .padding({ left: 16, right: 16, top: 6, bottom: 6 })

        // 统计卡片
        ListItem() {
          Column() {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.externaldrive'))
                .fontSize(18)
                .fontColor([AppTheme.current().onSurface])
              Text(L10n.t('music_cache_settings_section_stats', '统计'))
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppTheme.current().onSurface)
            }
            .width('100%')

            Row({ space: 12 }) {
              this.StatTile(L10n.t('music_cache_settings_cached_count', '缓存条目'), `${this.ctrl.cachedCount}`)
              this.StatTile(L10n.t('music_cache_settings_cached_size', '占用空间'),
                FileFormat.formatSize(this.ctrl.cachedBytes))
            }
            .width('100%')
            .margin({ top: 12 })

            Button(this.ctrl.clearing ? L10n.t('music_cache_settings_clearing', '清空中...')
              : L10n.t('music_cache_settings_clear', '清空缓存'))
              .fontSize(14)
              .height(42)
              .width('100%')
              .borderRadius(10)
              .backgroundColor(AppTheme.withAlpha(AppTheme.current().primary, 0.85))
              .margin({ top: 12 })
              .enabled(!this.ctrl.clearing)
              .onClick(() => {
                void this.clearCache();
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(12)
          .borderRadius(14)
          .border({ width: 0.8, color: AppTheme.withAlpha(AppTheme.current().divider, 0.8) })
          .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.9))
        }
        .padding({ left: 16, right: 16, top: 6, bottom: 6 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  StatTile(label: string, value: string) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(12)
        .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
      Text(value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding(12)
    .borderRadius(12)
    .border({ width: 0.8, color: AppTheme.withAlpha(AppTheme.current().divider, 0.8) })
    .backgroundColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.04))
  }
}
