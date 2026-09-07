import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { APIClient } from '../../../core/network/APIClient';
import { DialogUtil } from '../../../common/DialogUtil';
import { PageScaffold } from '../../../common/PageScaffold';
import { PickOption, showOptionPickSheet } from '../../../common/components/OptionPickSheet';
import { CurrentUserStore } from '../../../core/user/CurrentUserStore';
import { PhotoAiSettingsController } from '../../controllers/PhotoAiSettingsController';
import { PhotoPreviewSettingsController } from '../../controllers/PhotoPreviewSettingsController';
import { PhotoSourceSettingsController } from '../../controllers/PhotoSourceSettingsController';
import { PhotoSource } from '../../models/PhotoSourceModels';
import { pickTargetFolderViaSheet } from '../../../files/views/FolderPickerSheet';

/** 照片设置路由参数（对齐 Flutter AppPhotoSettingsView initialTabIndex） */
export class PhotoSettingsPageParam {
  initialTabIndex: number = 0;
}

/** 手机布局断点（对齐 Flutter DeviceUtils.phoneBreakpoint = 600） */
const PHONE_BREAKPOINT = 600;

/**
 * 照片设置页（对齐 Flutter AppPhotoSettingsView）：
 * 三个 Tab（来源/预览/AI）；手机 + 非管理员仅显示预览设置（无底部 TabBar）。
 */
@ComponentV2
export struct PhotoSettingsPage {
  @Param param: PhotoSettingsPageParam = new PhotoSettingsPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local currentTab: number = 0;
  /** 视口宽度（用于手机/宽屏布局切换） */
  @Local viewWidth: number = 0;

  aboutToAppear(): void {
    const idx = this.param.initialTabIndex;
    this.currentTab = Math.min(Math.max(idx, 0), 2);
  }

  private isNarrow(): boolean {
    return this.viewWidth <= 0 || this.viewWidth < PHONE_BREAKPOINT;
  }

  private isAdmin(): boolean {
    return CurrentUserStore.getInstance().isAdmin;
  }

  build() {
    PageScaffold({
      title: L10n.setting,
      showBack: true,
      onBack: (): void => {
        this.popPage();
      },
      content: (): void => {
        this.MainContent()
      }
    })
  }

  @Builder
  MainContent() {
    Column() {
      if (this.isNarrow() && !this.isAdmin()) {
        // 手机 + 非管理员：仅预览设置（对齐 Flutter showOnlyPreview）
        PhotoPreviewSettingsView({ viewWidth: this.viewWidth })
      } else {
        Tabs({ barPosition: BarPosition.End, index: this.currentTab }) {
          TabContent() {
            PhotoSourceSettingsView({ viewWidth: this.viewWidth })
          }
          .tabBar(this.TabBarIcon($r('sys.symbol.folder'), L10n.t('settings_source', '来源'), 0))

          TabContent() {
            PhotoPreviewSettingsView({ viewWidth: this.viewWidth })
          }
          .tabBar(this.TabBarIcon($r('sys.symbol.slider_horizontal_2'),
            L10n.t('photo_preview_settings_title', '预览'), 1))

          TabContent() {
            PhotoAiSettingsView({ viewWidth: this.viewWidth })
          }
          .tabBar(this.TabBarIcon($r('sys.symbol.wand_and_stars'),
            L10n.t('photo_ai_settings_title', 'AI 设置'), 2))
        }
        .width('100%')
        .layoutWeight(1)
        .barMode(BarMode.Fixed)
        .scrollable(false)
        .onChange((index: number) => {
          this.currentTab = index;
        })
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_o: Area, n: Area) => {
      this.viewWidth = Number(n.width);
    })
  }

  /** 底部 Tab 项（对齐 Flutter Tab：icon + text，选中主色） */
  @Builder
  TabBarIcon(icon: Resource, text: string, tab: number) {
    Column({ space: 2 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([this.currentTab === tab ? AppTheme.current().primary : AppTheme.current().subText])
      Text(text)
        .fontSize(10)
        .fontColor(this.currentTab === tab ? AppTheme.current().primary : AppTheme.current().subText)
        .maxLines(1)
    }
    .width('100%')
    .height(52)
    .justifyContent(FlexAlign.Center)
  }
}

// ===== 公共小组件 =====

@ComponentV2
struct SwitchRow {
  @Param title: string = '';
  @Param subtitle: string = '';
  /** 进度后缀（photo_ai_progress_suffix 已拼好） */
  @Param progressText: string = '';
  @Param value: boolean = false;
  /** 是否可编辑（避免与组件内置 enabled 属性重名） */
  @Param isEnabled: boolean = true;
  @Param onChanged: (v: boolean) => void = (_v: boolean): void => {
  };

  build() {
    Row() {
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(this.title)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.current().onSurface)
          if (this.progressText.length > 0) {
            Text(this.progressText)
              .fontSize(12)
              .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
          }
        }
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(12)
            .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Blank().width(12)
      Toggle({ type: ToggleType.Switch, isOn: this.value })
        .selectedColor(AppTheme.current().primary)
        .opacity(this.isEnabled ? 1 : 0.45)
        .onChange((v: boolean) => {
          if (this.isEnabled) {
            this.onChanged(v);
          }
        })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }
}

/** 帮助小图标按钮（对齐 Flutter IconButton(Icons.help_outline) + showInfoDialog） */
@ComponentV2
struct HelpIcon {
  @Param helpText: string = '';
  @Param iconSize: number = 18;

  private showHelp(): void {
    DialogUtil.showInfoDialog(L10n.tip, this.helpText);
  }

  build() {
    SymbolGlyph($r('sys.symbol.questionmark_circle'))
      .fontSize(this.iconSize)
      .fontColor([AppTheme.current().subText])
      .onClick(() => {
        this.showHelp();
      })
  }
}

/** 下拉选择框（对齐 Flutter CustomDropdownField，点击弹出 OptionPickSheet） */
@ComponentV2
struct DropdownField {
  @Param label: string = '';
  @Param isEnabled: boolean = true;
  @Param maxWidth: number = 360;
  @Param onOpen: () => void = (): void => {
  };

  build() {
    Row() {
      Text(this.label)
        .fontSize(14)
        .fontColor(AppTheme.current().onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(14)
        .fontColor([AppTheme.current().subText])
    }
    .constraintSize({ maxWidth: this.maxWidth })
    .height(44)
    .padding({ left: 12, right: 12 })
    .borderRadius(10)
    .border({
      width: 1,
      color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.16)
    })
    .opacity(this.isEnabled ? 1 : 0.5)
    .onClick(() => {
      if (this.isEnabled) {
        this.onOpen();
      }
    })
  }
}

// ===== AI 设置（对齐 Flutter photo_ai_settings_view.dart） =====

@ComponentV2
struct PhotoAiSettingsView {
  @Param viewWidth: number = 0;
  ctrl: PhotoAiSettingsController = new PhotoAiSettingsController();

  aboutToAppear(): void {
    this.ctrl.init();
  }

  /** 服务器版本 >= 10（对齐 Flutter ApiController.isServerVersionAtLeast(10)，未知视为支持） */
  private isServerVersionAtLeast(min: number): boolean {
    const version = APIClient.getInstance().state.serverVersion ?? '';
    const m = /(\d+)/.exec(version);
    if (m === null) {
      return true; // unknownAsSupported: true
    }
    return Number(m[1]) >= min;
  }

  private progressSuffix(percent: number): string {
    return L10n.t('photo_ai_progress_suffix', '(进度:@percent%)',
      L10n.paramsOf('percent', `${Math.min(Math.max(percent, 0), 100)}`));
  }

  /** 打开自动隐藏阈值选择（对齐 Flutter CustomDropdownField options 0/3/5/10） */
  private openAutoHidePicker(): void {
    const options: PickOption[] = [];
    for (const v of [0, 3, 5, 10]) {
      options.push(new PickOption(`${v}`,
        L10n.t(`photo_ai_auto_hide_face_album_option_${v}`, `${v}`)));
    }
    const selected = [0, 3, 5, 10].includes(this.ctrl.faceMinShowCount) ? `${this.ctrl.faceMinShowCount}` : '0';
    showOptionPickSheet(L10n.t('photo_ai_auto_hide_face_album', '自动隐藏人脸相册'), options, selected,
      (key: string): void => {
        void this.ctrl.setFaceMinShowCount(parseInt(key, 10));
      });
  }

  /** 重置去重扫描（确认弹窗对齐 Flutter resetSimilar） */
  private confirmResetSimilar(): void {
    DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('photo_ai_similar_reset_confirm', '确定要重置相似照片扫描吗？'),
      (): void => {
        void this.ctrl.resetSimilar();
      },
      L10n.ok,
      L10n.cancel);
  }

  build() {
    Column() {
      // 标题行：标题 + 帮助 + 刷新
      Row({ space: 10 }) {
        Text(L10n.t('photo_ai_settings_title', 'AI 设置'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
        HelpIcon({ helpText: L10n.t('photo_ai_settings_help_content', 'AI 功能说明') })
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(18)
          .fontColor([AppTheme.current().onSurface])
          .onClick(() => {
            void this.ctrl.fetchSettings(true);
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 10 })

      Scroll() {
        Column() {
          // GPU 优先（需要服务器版本 >= 10）
          if (this.isServerVersionAtLeast(10)) {
            Column() {
              SwitchRow({
                title: L10n.t('photo_ai_gpu_prefer', '优先使用 GPU'),
                subtitle: L10n.t('photo_ai_gpu_prefer_subtitle', '优先使用 GPU 加速 AI 识别'),
                value: this.ctrl.gpuPrefer,
                isEnabled: this.ctrl.canEdit,
                onChanged: (v: boolean): void => {
                  void this.ctrl.toggleGpu(v);
                }
              })
            }
            .width('100%')
            .padding({ left: 14, right: 14 })
            .borderRadius(16)
            .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.55))
            .border({
              width: 1,
              color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.06)
            })
            Blank().height(12)
          }

          // OCR / 场景 / 相似去重
          Column() {
            SwitchRow({
              title: L10n.t('photo_ai_enable_ocr', '文字识别 (OCR)'),
              subtitle: L10n.t('photo_ai_enable_ocr_subtitle', '识别照片中的文字'),
              progressText: this.progressSuffix(this.ctrl.ocrProgress),
              value: this.ctrl.ocrEnabled,
              isEnabled: this.ctrl.canEdit,
              onChanged: (v: boolean): void => {
                void this.ctrl.toggleOcr(v);
              }
            })
            Divider().height(1).color(AppTheme.current().divider)
            SwitchRow({
              title: L10n.t('photo_ai_enable_scene', '场景识别'),
              subtitle: L10n.t('photo_ai_enable_scene_subtitle', '识别照片拍摄场景与地点'),
              progressText: this.progressSuffix(this.ctrl.placeProgress),
              value: this.ctrl.placeEnabled,
              isEnabled: this.ctrl.canEdit,
              onChanged: (v: boolean): void => {
                void this.ctrl.togglePlace(v);
              }
            })
            Divider().height(1).color(AppTheme.current().divider)
            this.SimilarDedupRow()
          }
          .width('100%')
          .padding({ left: 14, right: 14 })
          .borderRadius(16)
          .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.55))
          .border({
            width: 1,
            color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.06)
          })
          Blank().height(12)

          // 人脸 / 自动隐藏
          Column() {
            SwitchRow({
              title: L10n.t('photo_ai_enable_face', '人脸识别'),
              progressText: this.progressSuffix(this.ctrl.faceProgress),
              value: this.ctrl.faceEnabled,
              isEnabled: this.ctrl.canEdit,
              onChanged: (v: boolean): void => {
                void this.ctrl.toggleFace(v);
              }
            })
            Divider().height(1).color(AppTheme.current().divider)
            Column({ space: 4 }) {
              Text(L10n.t('photo_ai_auto_hide_face_album', '自动隐藏人脸相册'))
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppTheme.current().onSurface)
              Text(L10n.t('photo_ai_auto_hide_face_album_subtitle', '照片数少于阈值的人脸相册将被隐藏'))
                .fontSize(12)
                .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
              Blank().height(10)
              Row() {
                DropdownField({
                  label: L10n.t(`photo_ai_auto_hide_face_album_option_${
                    [0, 3, 5, 10].includes(this.ctrl.faceMinShowCount) ? this.ctrl.faceMinShowCount : 0}`,
                  '不隐藏显示所有'),
                  isEnabled: this.ctrl.canEdit,
                  maxWidth: this.viewWidth > 392 ? 360 : this.viewWidth - 60,
                  onOpen: (): void => {
                    this.openAutoHidePicker();
                  }
                })
              }
              .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding({ top: 12, bottom: 12 })
          }
          .width('100%')
          .padding({ left: 14, right: 14 })
          .borderRadius(16)
          .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.55))
          .border({
            width: 1,
            color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.06)
          })
          Blank().height(12)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, bottom: 12 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
  }

  /** 相似照片去重行（对齐 Flutter _SimilarDedupItem：进度 + 重置 + 开关） */
  @Builder
  SimilarDedupRow() {
    Row() {
      Column({ space: 4 }) {
        Text(L10n.t('photo_ai_enable_similar', '相似照片去重'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
        Text(L10n.t('photo_ai_enable_similar_subtitle', '查找并整理相似的照片'))
          .fontSize(12)
          .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
        Row({ space: 10 }) {
          Text(L10n.t('photo_ai_similar_scan_progress_suffix', '扫描:@percent%',
            L10n.paramsOf('percent', `${Math.min(Math.max(this.ctrl.similarScanProgress, 0), 100)}`)))
            .fontSize(12)
            .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
          Text(L10n.t('photo_ai_similar_compare_progress_suffix', '对比:@percent%',
            L10n.paramsOf('percent', `${Math.min(Math.max(this.ctrl.similarCompareProgress, 0), 100)}`)))
            .fontSize(12)
            .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(L10n.t('reset', '重置'))
        .fontSize(14)
        .fontColor(this.ctrl.canEdit ? AppTheme.current().primary : AppTheme.current().hint)
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .onClick(() => {
          if (this.ctrl.canEdit) {
            this.confirmResetSimilar();
          }
        })
      Toggle({ type: ToggleType.Switch, isOn: this.ctrl.similarEnabled })
        .selectedColor(AppTheme.current().primary)
        .opacity(this.ctrl.canEdit ? 1 : 0.45)
        .onChange((v: boolean) => {
          if (this.ctrl.canEdit) {
            void this.ctrl.toggleSimilar(v);
          }
        })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }
}

// ===== 预览设置（对齐 Flutter photo_preview_settings_view.dart） =====

@ComponentV2
struct PhotoPreviewSettingsView {
  @Param viewWidth: number = 0;
  ctrl: PhotoPreviewSettingsController = new PhotoPreviewSettingsController();

  aboutToAppear(): void {
    this.ctrl.init();
  }

  private isNarrow(): boolean {
    return this.viewWidth <= 0 || this.viewWidth < PHONE_BREAKPOINT;
  }

  private sizeLabel(size: string): string {
    return size === 'origin'
      ? L10n.t('photo_preview_size_origin', '原图')
      : L10n.t('photo_preview_size_long_side', '长边尺寸 @size', L10n.paramsOf('size', size));
  }

  /** 打开尺寸选择（对齐 Flutter CustomDropdownField allowedSizes） */
  private openSizePicker(): void {
    const options: PickOption[] = [];
    for (const s of PhotoPreviewSettingsController.allowedSizes) {
      options.push(new PickOption(s, this.sizeLabel(s)));
    }
    showOptionPickSheet(L10n.t('photo_preview_size_label', '预览尺寸'), options, this.ctrl.previewSize,
      (key: string): void => {
        void this.ctrl.updatePreviewSize(key);
      });
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Text(L10n.t('photo_preview_settings_title', '预览'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(18)
          .fontColor([AppTheme.current().onSurface])
          .onClick(() => {
            void this.ctrl.fetchSettings(true);
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12, left: 16, right: 16 })

      Scroll() {
        Column() {
          // 尺寸卡片
          Column({ space: 4 }) {
            Text(L10n.t('photo_preview_size_label', '预览尺寸'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.current().onSurface)
            Text(L10n.t('photo_preview_size_subtitle', '预览图长边尺寸，越小加载越快'))
              .fontSize(12)
              .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
            Blank().height(10)
            Row() {
              DropdownField({
                label: this.sizeLabel(this.ctrl.previewSize),
                maxWidth: this.viewWidth > 392 ? 360 : this.viewWidth - 60,
                onOpen: (): void => {
                  this.openSizePicker();
                }
              })
            }
            .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(14)
          .borderRadius(16)
          .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.55))
          .border({
            width: 1,
            color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.06)
          })

          // WiFi 原图开关（手机 && 尺寸 != origin 时显示）
          if (this.isNarrow() && this.ctrl.previewSize !== 'origin') {
            Blank().height(12)
            Column() {
              SwitchRow({
                title: L10n.t('photo_preview_wifi_original', 'WiFi 下加载原图'),
                subtitle: L10n.t('photo_preview_wifi_original_subtitle', '连接 WiFi 时直接加载原图'),
                value: this.ctrl.wifiOriginalEnabled,
                isEnabled: true,
                onChanged: (v: boolean): void => {
                  this.ctrl.setWifiOriginalEnabled(v);
                }
              })
            }
            .width('100%')
            .padding({ left: 14, right: 14 })
            .borderRadius(16)
            .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.55))
            .border({
              width: 1,
              color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.06)
            })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, bottom: 12 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
  }
}

// ===== 来源设置（对齐 Flutter photo_source_settings_view.dart） =====

@ComponentV2
struct PhotoSourceSettingsView {
  @Param viewWidth: number = 0;
  ctrl: PhotoSourceSettingsController = new PhotoSourceSettingsController();

  aboutToAppear(): void {
    this.ctrl.init();
  }

  private isNarrow(): boolean {
    return this.viewWidth <= 0 || this.viewWidth < PHONE_BREAKPOINT;
  }

  /** 网格列数（对齐 Flutter 宽屏分支 _kBaseCardWidth=400 计算） */
  private gridColumns(): number {
    const available = this.viewWidth - 32;
    if (available <= 0) {
      return 1;
    }
    return Math.min(Math.max(Math.floor((available + 12) / (400 + 12)), 1), 99);
  }

  /** Grid columnsTemplate（'1fr 1fr ...'） */
  private columnsTemplate(): string {
    return new Array(this.gridColumns()).fill('1fr').join(' ');
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
  private confirmRelocate(source: PhotoSource): void {
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
  private confirmDelete(source: PhotoSource): void {
    DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('photo_source_delete_confirm', '确定删除来源目录：@path？', L10n.paramsOf('path', source.path)),
      (): void => {
        void this.ctrl.deleteSourceOptimistic(source);
      },
      L10n.t('delete', '删除'),
      L10n.cancel);
  }

  /** 全部扫描 / 重置缩略图入口（对齐 Flutter 顶部按钮） */
  private confirmResetThumbnails(): void {
    DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('photo_source_reset_thumbnails_confirm', '确定要重新生成所有缩略图吗？'),
      (): void => {
        void this.ctrl.preGenerateThumbnails();
      },
      L10n.confirm,
      L10n.cancel);
  }

  /** 定时扫描开关切换（对齐 Flutter interval switch） */
  private toggleInterval(source: PhotoSource, value: boolean): void {
    if (value) {
      const ms = this.ctrl.getIntervalHours(source) * 3600 * 1000;
      void this.ctrl.updateSourceOptimistic(source, undefined, undefined, 1, ms);
    } else {
      void this.ctrl.updateSourceOptimistic(source, undefined, undefined, 0, 0);
    }
  }

  /** 定时扫描小时选择（对齐 Flutter DropdownButton 1-24） */
  private openHoursPicker(source: PhotoSource): void {
    const options: PickOption[] = [];
    for (let h = 1; h <= 24; h++) {
      options.push(new PickOption(`${h}`, `${h}`));
    }
    showOptionPickSheet(L10n.t('photo_source_scan_interval_hours', '扫描间隔（小时）'), options,
      `${this.ctrl.getIntervalHours(source)}`, (key: string): void => {
        void this.ctrl.updateSourceOptimistic(source, undefined, undefined, 1,
          parseInt(key, 10) * 3600 * 1000);
      });
  }

  build() {
    Column() {
      // 顶部标题行：来源 + 全部扫描 + 重置缩略图
      Row({ space: 10 }) {
        Text(L10n.t('settings_source', '来源'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
        Text(L10n.t('photo_source_scan_all', '全部扫描'))
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .padding({ left: 4, right: 4, top: 6, bottom: 6 })
          .onClick(() => {
            void this.ctrl.scanSource('all');
          })
        Text(L10n.t('photo_source_reset_thumbnails', '重置缩略图'))
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .padding({ left: 4, right: 4, top: 6, bottom: 6 })
          .onClick(() => {
            this.confirmResetThumbnails();
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12, left: 16, right: 16 })

      if (this.isNarrow()) {
        this.NarrowList()
      } else {
        this.WideGrid()
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 手机布局（对齐 Flutter isNarrow ListView） */
  @Builder
  NarrowList() {
    List({ space: 12 }) {
      ForEach(this.ctrl.sources, (s: PhotoSource) => {
        ListItem() {
          Column() {
            SourceCard({
              ctrl: this.ctrl,
              source: s,
              narrow: true,
              onRelocate: (): void => {
                this.confirmRelocate(s);
              },
              onDelete: (): void => {
                this.confirmDelete(s);
              },
              onHoursPick: (): void => {
                this.openHoursPicker(s);
              }
            })
          }
        }
      }, (s: PhotoSource) => `source_${s.id}_${s.path}`)
      ListItem() {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.plus_circle'))
            .fontSize(20)
            .fontColor([AppTheme.current().primary])
          Text(L10n.t('photo_source_add_card', '添加照片来源'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.current().onSurface)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 14, bottom: 14 })
        .borderRadius(16)
        .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.55))
        .border({
          width: 1,
          color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.06)
        })
        .onClick(() => {
          this.pickAndAdd();
        })
      }
      ListItem() {
        Column()
          .width('100%')
          .height(8)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .padding({ left: 16, right: 16 })
  }

  /** 宽屏布局（对齐 Flutter 宽屏 GridView：400 宽 260 高卡片） */
  @Builder
  WideGrid() {
    Scroll() {
      Grid() {
        ForEach(this.ctrl.sources, (s: PhotoSource) => {
          GridItem() {
            Scroll() {
              Column() {
                SourceCard({
                  ctrl: this.ctrl,
                  source: s,
                  narrow: false,
                  onRelocate: (): void => {
                    this.confirmRelocate(s);
                  },
                  onDelete: (): void => {
                    this.confirmDelete(s);
                  },
                  onHoursPick: (): void => {
                    this.openHoursPicker(s);
                  }
                })
              }
            }
            .scrollBar(BarState.Off)
            .width('100%')
            .height('100%')
          }
          .height(260)
        }, (s: PhotoSource) => `source_${s.id}_${s.path}`)
        GridItem() {
          Column({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.plus_circle'))
              .fontSize(38)
              .fontColor([AppTheme.current().primary])
            Row({ space: 6 }) {
              Text(L10n.t('photo_source_add_card', '添加照片来源'))
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppTheme.current().onSurface)
              HelpIcon({
                helpText: L10n.t('photo_source_help_add_source', '添加服务器上的目录作为照片来源'),
                iconSize: 16
              })
            }
          }
          .width('100%')
          .height(260)
          .justifyContent(FlexAlign.Center)
          .borderRadius(16)
          .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.55))
          .border({
            width: 1,
            color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.06)
          })
          .onClick(() => {
            this.pickAndAdd();
          })
        }
        .height(260)
      }
      .columnsTemplate(this.columnsTemplate())
      .columnsGap(12)
      .rowsGap(12)
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16 })
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .layoutWeight(1)
  }
}

/**
 * 来源卡（对齐 Flutter _MobileSourceCard/_SourceCard）：
 * 路径 + 可用状态 + 操作按钮 + 三个开关行 + 定时扫描小时下拉。
 */
@ComponentV2
struct SourceCard {
  @Param ctrl: PhotoSourceSettingsController = new PhotoSourceSettingsController();
  @Param source: PhotoSource = new PhotoSource();
  @Param narrow: boolean = true;
  @Param onRelocate: () => void = (): void => {
  };
  @Param onDelete: () => void = (): void => {
  };
  @Param onHoursPick: () => void = (): void => {
  };

  private intervalEnabled(): boolean {
    return this.ctrl.getIntervalEnabled(this.source);
  }

  private showHelp(text: string): void {
    DialogUtil.showInfoDialog(L10n.tip, text);
  }

  /** 帮助图标 + 信息弹窗（对齐 Flutter switchRow 的 help IconButton） */
  @Builder
  HelpButton(text: string) {
    SymbolGlyph($r('sys.symbol.questionmark_circle'))
      .fontSize(16)
      .fontColor([AppTheme.current().subText])
      .onClick(() => {
        this.showHelp(text);
      })
  }

  /** 开关行（对齐 Flutter switchRow：标题 + 帮助图标 + Switch） */
  @Builder
  SwitchLine(title: string, helpKey: string, helpFallback: string, value: boolean,
    onChanged: (v: boolean) => void) {
    Row() {
      Row({ space: 6 }) {
        Text(title)
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        this.HelpButton(L10n.t(helpKey, helpFallback))
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)

      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(AppTheme.current().primary)
        .onChange((v: boolean) => {
          onChanged(v);
        })
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      // 路径 + 状态 + 操作
      Text(this.source.path)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.current().onSurface)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Blank().height(8)
      Row({ space: 8 }) {
        if (!this.source.exists) {
          Text(L10n.t('photo_source_relocate', '重新定位'))
            .fontSize(13)
            .fontColor(AppTheme.current().primary)
            .padding({ top: 4, bottom: 4, right: 4 })
            .onClick(() => {
              this.onRelocate();
            })
        }
        Text(this.source.exists
          ? `[${L10n.t('photo_source_available', '可用')}]`
          : `[${L10n.t('photo_source_unavailable', '不可用')}]`)
          .fontSize(12)
          .fontColor(this.source.exists ? '#2E9E44' : '#D64545')
        Blank()
        if (this.source.exists) {
          Text(L10n.t('photo_source_scan_now', '立即扫描'))
            .fontSize(13)
            .fontColor(AppTheme.current().primary)
            .padding({ top: 4, bottom: 4, left: 4 })
            .onClick(() => {
              void this.ctrl.scanSource(this.source.path);
            })
        }
        Text(L10n.t('delete', '删除'))
          .fontSize(13)
          .fontColor(AppTheme.current().error)
          .padding({ top: 4, bottom: 4, left: 4 })
          .onClick(() => {
            this.onDelete();
          })
      }
      .width('100%')
      Blank().height(6)

      // 三个开关行
      this.SwitchLine(
        L10n.t('photo_source_scan_when_start', '启动时扫描'),
        'photo_source_help_scan_when_start', '启动应用时自动扫描该来源',
        this.source.scanWhenStart === 1,
        (v: boolean): void => {
          void this.ctrl.updateSourceOptimistic(this.source, v ? 1 : 0);
        })
      this.SwitchLine(
        L10n.t('photo_source_scan_when_change', '变化时扫描'),
        'photo_source_help_scan_when_change', '目录内容变化时自动扫描该来源',
        this.source.scanWhenChange === 1,
        (v: boolean): void => {
          void this.ctrl.updateSourceOptimistic(this.source, undefined, v ? 1 : 0);
        })

      // 定时扫描开关
      Row() {
        Row({ space: 6 }) {
          Text(L10n.t('photo_source_scan_interval', '定时扫描'))
            .fontSize(14)
            .fontColor(AppTheme.current().onSurface)
          this.HelpButton(L10n.t('photo_source_help_scan_interval', '按设定间隔定时扫描该来源'))
        }
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.intervalEnabled() })
          .selectedColor(AppTheme.current().primary)
          .onChange((v: boolean) => {
            this.intervalToggled(v);
          })
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })

      // 小时下拉（启用时显示）
      if (this.intervalEnabled()) {
        Row() {
          Text(L10n.t('photo_source_scan_interval_hours', '扫描间隔（小时）'))
            .fontSize(13)
            .fontColor(AppTheme.current().onSurface)
          Blank()
          Row({ space: 4 }) {
            Text(`${this.ctrl.getIntervalHours(this.source)}`)
              .fontSize(14)
              .fontColor(AppTheme.current().onSurface)
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(12)
              .fontColor([AppTheme.current().subText])
          }
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(8)
          .border({
            width: 1,
            color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.16)
          })
          .onClick(() => {
            this.onHoursPick();
          })
        }
        .width('100%')
        .padding({ top: 2 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(this.narrow ? 12 : 14)
    .borderRadius(16)
    .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.55))
    .border({
      width: 1,
      color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.06)
    })
  }

  private intervalToggled(v: boolean): void {
    if (v) {
      const ms = this.ctrl.getIntervalHours(this.source) * 3600 * 1000;
      void this.ctrl.updateSourceOptimistic(this.source, undefined, undefined, 1, ms);
    } else {
      void this.ctrl.updateSourceOptimistic(this.source, undefined, undefined, 0, 0);
    }
  }
}
