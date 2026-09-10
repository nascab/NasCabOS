import { L10n } from '../../../core/localization/L10n';
import { LengthMetrics } from '@kit.ArkUI';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { PageScaffold } from '../../../common/PageScaffold';
import { DialogUtil, DialogResult } from '../../../common/DialogUtil';
import { EmptyState } from '../../../common/components/EmptyState';
import { GlassCard } from '../../../common/components/GlassCard';
import { PickOption, showOptionPickSheet } from '../../../common/components/OptionPickSheet';
import { ImageCompressController } from '../controllers/MediaToolControllers';
import { MediaToolImageCompressResult } from '../services/MediaToolApiServices';
import { MediaToolRoutes, MediaToolImageCompressPageParam } from '../router/MediaToolRoutes';

/** 压缩尺寸档位（对齐 Flutter _SizeMenu） */
const SIZE_PRESETS: number[] = [512, 1024, 2048, 4096];
/** 质量档位（对齐 Flutter _QualityMenu） */
const QUALITY_PRESETS: number[] = [90, 80, 70, 60, 50, 40, 30];

/**
 * 图片压缩转换页（对齐 Flutter ImageCompressView appMode 移动端形态）：
 * 上传选择卡 + 设置菜单（质量/格式/尺寸/元数据）+ 统计栏 + 结果列表。
 */
@ComponentV2
export struct MediaToolImageCompressPage {
  @Param param: MediaToolImageCompressPageParam = new MediaToolImageCompressPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local ctrl: ImageCompressController = new ImageCompressController();

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private showHelp(): void {
    void DialogUtil.showInfoDialog(
      L10n.t('media_tool_menu_image_compress', '图片压缩转换'),
      L10n.t('media_tool_menu_image_compress_help', '压缩或转换图片格式'));
  }

  // ===== 设置菜单文案（对齐 Flutter 各菜单 label） =====

  private qualityLabel(): string {
    if (this.ctrl.quality === 'auto') {
      return L10n.t('media_tool_auto_quality', '自动画质');
    }
    return `${L10n.t('media_tool_quality', '质量')} ${this.ctrl.quality}`;
  }

  private formatLabel(): string {
    if (this.ctrl.format === 'auto') {
      return L10n.t('media_tool_auto_format', '自动格式');
    }
    return this.ctrl.format.toUpperCase();
  }

  private sizeLabel(): string {
    if (this.ctrl.size === 'auto') {
      return L10n.t('media_tool_auto_size', '自动尺寸');
    }
    if (this.ctrl.size === 'custom') {
      return this.ctrl.customOutSize > 0
        ? `${L10n.t('media_tool_out_size', '输出尺寸')} ${this.ctrl.customOutSize}`
        : L10n.t('media_tool_custom_size', '自定义尺寸');
    }
    return `${L10n.t('media_tool_out_size', '输出尺寸')} ${this.ctrl.size}`;
  }

  private metaLabel(): string {
    return this.ctrl.withMeta
      ? L10n.t('media_tool_with_meta', '保留元数据')
      : L10n.t('media_tool_without_meta', '去除元数据');
  }

  private qualityOptions(): PickOption[] {
    const out: PickOption[] = [new PickOption('auto', L10n.t('media_tool_auto_quality', '自动画质'))];
    QUALITY_PRESETS.forEach((q: number): void => {
      out.push(new PickOption(`${q}`, `${L10n.t('media_tool_quality', '质量')} ${q}`));
    });
    return out;
  }

  private formatOptions(): PickOption[] {
    return [
      new PickOption('auto', L10n.t('media_tool_auto_format', '自动格式')),
      new PickOption('jpeg', 'JPEG'),
      new PickOption('png', 'PNG'),
      new PickOption('webp', 'WEBP')
    ];
  }

  private sizeOptions(): PickOption[] {
    const out: PickOption[] = [new PickOption('auto', L10n.t('media_tool_auto_size', '自动尺寸'))];
    SIZE_PRESETS.forEach((s: number): void => {
      out.push(new PickOption(`${s}`, `${L10n.t('media_tool_out_size', '输出尺寸')} ${s}`));
    });
    out.push(new PickOption('custom', L10n.t('media_tool_custom_size', '自定义尺寸')));
    return out;
  }

  private metaOptions(): PickOption[] {
    return [
      new PickOption('keep', L10n.t('media_tool_with_meta', '保留元数据')),
      new PickOption('strip', L10n.t('media_tool_without_meta', '去除元数据'))
    ];
  }

  /** 自定义尺寸输入弹窗（对齐 Flutter _showSizeDialog：digits-only + clamp 10..20000） */
  private showCustomSizeDialog(): void {
    const title = L10n.t('media_tool_custom_size', '自定义尺寸');
    void DialogUtil.showInputDialog(
      title,
      L10n.t('media_tool_out_size_hint', '最大边长像素（10-20000）'),
      this.ctrl.customOutSize > 0 ? `${this.ctrl.customOutSize}` : '',
      L10n.confirm,
      L10n.cancel,
      (value: string): string | undefined => {
        const trimmed = value.trim();
        if (trimmed.length === 0) {
          return L10n.t('media_tool_out_size_hint', '请输入尺寸');
        }
        const n = Number(trimmed.replace(/[^0-9]/g, ''));
        if (Number.isNaN(n) || n <= 0) {
          return L10n.t('media_tool_out_size_hint', '请输入有效尺寸');
        }
        return undefined;
      }
    ).then((result: DialogResult): void => {
      if (typeof result !== 'string' || result.trim().length === 0) {
        return;
      }
      const n = Number(result.trim().replace(/[^0-9]/g, ''));
      if (Number.isNaN(n) || n <= 0) {
        return;
      }
      this.ctrl.setCustomOutSize(Math.min(20000, Math.max(10, Math.round(n))));
      this.ctrl.setSize('custom');
    });
  }

  /** 统计文本（对齐 Flutter _StatsBar） */
  private statsText(): string {
    let out = `${L10n.t('media_tool_optimized', '已优化')}: ${this.ctrl.optimizedCount()}`;
    if (this.ctrl.optimizedCount() > 0) {
      out += ` (${this.ctrl.optimizedSavedBytesText()})`;
    }
    return out;
  }

  build() {
    PageScaffold({
      title: L10n.t('media_tool_menu_image_compress', '图片压缩转换'),
      showBack: true,
      statusBarBg: AppTheme.current().pageBg,
      onBack: (): void => {
        this.popPage();
      },
      actions: (): void => {
        this.TitleActions()
      },
      content: (): void => {
        this.PageContent()
      }
    })
  }

  @Builder
  TitleActions() {
    SymbolGlyph($r('sys.symbol.questionmark_circle'))
      .fontSize(22)
      .fontColor([this.palette().appBarFg])
      .onClick((): void => {
        this.showHelp();
      })
  }

  @Builder
  PageContent() {
    Column() {
      Scroll() {
        Column() {
          // 上传选择卡（对齐 AppImageCompressUploadPicker）
          this.UploadPickerCard()
          // 设置菜单行（对齐 Wrap[_QualityMenu, _FormatMenu, _SizeMenu, _MetaMenu]）
          Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(10),
            cross: LengthMetrics.vp(10) } }) {
            this.MenuButton($r('sys.symbol.wand_and_stars'), this.qualityLabel(), (): void => {
              showOptionPickSheet(L10n.t('media_tool_quality', '质量'), this.qualityOptions(),
                this.ctrl.quality, (key: string): void => {
                  this.ctrl.setQuality(key);
                });
            })
            this.MenuButton($r('sys.symbol.picture'), this.formatLabel(), (): void => {
              showOptionPickSheet(L10n.t('media_tool_format', '输出格式'), this.formatOptions(),
                this.ctrl.format, (key: string): void => {
                  this.ctrl.setFormat(key);
                });
            })
            this.MenuButton($r('sys.symbol.rectangle_stack'), this.sizeLabel(), (): void => {
              showOptionPickSheet(L10n.t('media_tool_out_size', '输出尺寸'), this.sizeOptions(),
                this.ctrl.size, (key: string): void => {
                  if (key === 'custom') {
                    this.showCustomSizeDialog();
                    return;
                  }
                  this.ctrl.setSize(key);
                });
            })
            this.MenuButton($r('sys.symbol.info_circle'), this.metaLabel(), (): void => {
              showOptionPickSheet(L10n.t('media_tool_with_meta', '保留元数据'), this.metaOptions(),
                this.ctrl.withMeta ? 'keep' : 'strip', (key: string): void => {
                  this.ctrl.setWithMeta(key === 'keep');
                });
            })
          }
          .width('100%')
          .margin({ top: 10 })

          // 统计栏（对齐 _StatsBar）
          Column() {
            GlassCard({ padValue: { left: 12, right: 4, top: 10, bottom: 10 } }) {
              Row() {
                Text(this.statsText())
                  .fontSize(13)
                  .fontColor(this.palette().onSurface)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                this.IconAction($r('sys.symbol.trash'),
                  L10n.t('media_tool_clear', '清空'), (): void => {
                    this.ctrl.clearResults();
                  })
                this.IconAction($r('sys.symbol.archivebox'),
                  L10n.t('media_tool_download_zip', '打包下载'), (): void => {
                    void this.ctrl.downloadZip();
                  })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }
          }
          .width('100%')
          .margin({ top: 10 })

          // 结果列表（对齐 _ResultItem）
          if (this.ctrl.results.length === 0) {
            Column() {
              EmptyState({ message: L10n.t('no_data', '暂无数据') })
            }
            .width('100%')
            .margin({ top: 24 })
          } else {
            Column({ space: 8 }) {
              ForEach(this.ctrl.results, (item: MediaToolImageCompressResult,
                idx: number) => {
                this.ResultItem(item, idx)
              }, (item: MediaToolImageCompressResult, idx: number) => `${idx}_${item.outputFullPath}`)
            }
            .width('100%')
            .margin({ top: 10 })
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 12, bottom: 12 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().pageBg)
  }

  /** 上传选择卡（对齐 AppImageCompressUploadPicker） */
  @Builder
  UploadPickerCard() {
    Row() {
      Stack() {
        Column()
          .width(44)
          .height(44)
          .borderRadius(12)
          .backgroundColor(this.palette().primary)
          .opacity(0.10)
        SymbolGlyph($r('sys.symbol.picture'))
          .fontSize(22)
          .fontColor([this.palette().primary])
      }
      .width(44)
      .height(44)

      Column({ space: 4 }) {
        Text(L10n.t('media_tool_pick_images', '选择图片'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(L10n.t('media_tool_pick_images_subtitle', '支持批量选择，自动压缩并转换格式'))
          .fontSize(13)
          .fontColor(this.palette().subText)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })

      if (this.ctrl.busy) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(this.palette().primary)
          .margin({ left: 10 })
      } else {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([this.palette().hint])
          .margin({ left: 10 })
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor(this.palette().surfaceBg)
    .border({ width: 1, color: this.palette().divider })
    .onClick(() => {
      if (!this.ctrl.busy) {
        void this.ctrl.pickAndUpload();
      }
    })
  }

  /** 设置菜单按钮（对齐 CustomHoverSelectMenu 的移动端形态：图标+文字+下拉箭头） */
  @Builder
  MenuButton(icon: Resource, label: string, onTap: () => void) {
    Row({ space: 6 }) {
      SymbolGlyph(icon)
        .fontSize(15)
        .fontColor([this.palette().primary])
      Text(label)
        .fontSize(13)
        .fontColor(this.palette().onSurface)
        .maxLines(1)
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(12)
        .fontColor([this.palette().hint])
    }
    .padding({ left: 10, right: 10, top: 9, bottom: 9 })
    .borderRadius(10)
    .backgroundColor(this.palette().surfaceBg)
    .border({ width: 1, color: this.palette().divider })
    .onClick(() => {
      onTap();
    })
  }

  /** 统计栏图标按钮（对齐 IconButton，禁用置灰） */
  @Builder
  IconAction(icon: Resource, label: string, onTap: () => void) {
    Column({ space: 2 }) {
      SymbolGlyph(icon)
        .fontSize(19)
        .fontColor([this.disabledResult() ? this.palette().hint : this.palette().onSurface])
      Text(label)
        .fontSize(10)
        .fontColor(this.disabledResult() ? this.palette().hint : this.palette().subText)
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .opacity(this.disabledResult() ? 0.5 : 1)
    .onClick(() => {
      if (!this.disabledResult()) {
        onTap();
      }
    })
  }

  private disabledResult(): boolean {
    return this.ctrl.results.length === 0 || this.ctrl.busy;
  }

  /** 结果条目（对齐 _ResultItem + _DownloadTag） */
  @Builder
  ResultItem(item: MediaToolImageCompressResult, idx: number) {
    GlassCard({ padValue: { left: 12, right: 12, top: 10, bottom: 10 } }) {
      Row() {
        SymbolGlyph(item.outputSize <= item.inputSize
          ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.exclamationmark_circle'))
          .fontSize(20)
          .fontColor([item.outputSize <= item.inputSize ? '#4CAF50' : this.palette().error])

        Text(item.fileName)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ left: 10 })

        Column({ space: 6 }) {
          // 下载标签（对齐 _DownloadTag dense 形态）
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
              .fontSize(14)
              .fontColor([this.palette().onSurface])
            Text(item.outputFormat.trim().length === 0 ? '-' : item.outputFormat.toUpperCase())
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().onSurface)
          }
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(10)
          .backgroundColor(this.palette().pageBg)
          .border({ width: 1, color: this.palette().divider })
          .opacity(this.ctrl.busy ? 0.5 : 1)
          .onClick(() => {
            if (!this.ctrl.busy) {
              void this.ctrl.saveFile(item);
            }
          })

          Text(this.sizeRatioText(item, idx))
            .fontSize(11)
            .fontColor(this.palette().subText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
  }

  /** 尺寸与百分比文本（对齐 Flutter inputSizeText → outputSizeText + ratio） */
  private sizeRatioText(item: MediaToolImageCompressResult, _idx: number): string {
    const ratio = item.inputSize <= 0
      ? 0 : Math.round(((item.outputSize - item.inputSize) / item.inputSize) * 100);
    const ratioText = `${ratio > 0 ? '+' : ''}${ratio}%`;
    return `${this.formatSize(item.inputSize)} → ${this.formatSize(item.outputSize)}  ${ratioText}`;
  }

  private formatSize(bytes: number): string {
    if (bytes <= 0) {
      return '0 B';
    }
    const suffixes: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.min(suffixes.length - 1, Math.floor(Math.log(bytes) / Math.log(1024)));
    const v = bytes / Math.pow(1024, i);
    return `${v.toFixed(1)} ${suffixes[i]}`;
  }
}
