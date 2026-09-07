import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { DialogUtil } from '../../common/DialogUtil';
import { PickOption, showOptionPickSheet } from '../../common/components/OptionPickSheet';
import { pickTargetFolderViaSheet } from '../../files/views/FolderPickerSheet';
import { VideoOtherSettingsController, TranscodeHwDecoderOption } from '../controllers/VideoOtherSettingsController';

/**
 * 影音其他设置视图（对齐 Flutter VideoOtherSettingsView）：
 * 刮削设置卡片（Token/语言/代理）+ 字幕设置卡片 + 转码设置卡片。
 */

@ComponentV2
export struct VideoOtherSettingsView {
  ctrl: VideoOtherSettingsController = new VideoOtherSettingsController();

  aboutToAppear(): void {
    this.ctrl.init();
  }

  aboutToDisappear(): void {
    this.ctrl.dispose();
  }

  private languageOptions(): PickOption[] {
    return [
      new PickOption('', L10n.t('video_tmdb_language_follow_system', '跟随系统')),
      new PickOption('en-US', L10n.t('video_tmdb_language_en', '英语')),
      new PickOption('zh-CN', L10n.t('video_tmdb_language_zh', '中文')),
      new PickOption('es-ES', L10n.t('video_tmdb_language_es', '西班牙语')),
      new PickOption('fr-FR', L10n.t('video_tmdb_language_fr', '法语')),
      new PickOption('de-DE', L10n.t('video_tmdb_language_de', '德语')),
      new PickOption('ja-JP', L10n.t('video_tmdb_language_ja', '日语')),
      new PickOption('pt-BR', L10n.t('video_tmdb_language_pt', '葡萄牙语')),
      new PickOption('ru-RU', L10n.t('video_tmdb_language_ru', '俄语')),
      new PickOption('ar-SA', L10n.t('video_tmdb_language_ar', '阿拉伯语')),
      new PickOption('ko-KR', L10n.t('video_tmdb_language_ko', '韩语')),
      new PickOption('th-TH', L10n.t('video_tmdb_language_th', '泰语')),
      new PickOption('vi-VN', L10n.t('video_tmdb_language_vi', '越南语')),
      new PickOption('id-ID', L10n.t('video_tmdb_language_id', '印尼语'))
    ];
  }

  private languageLabel(): string {
    const opt = this.languageOptions().find((o: PickOption): boolean => o.key === this.ctrl.tmdbLanguage);
    return opt !== undefined ? opt.label : L10n.t('video_tmdb_language_follow_system', '跟随系统');
  }

  private showLanguagePick(): void {
    showOptionPickSheet(L10n.t('video_tmdb_language', '刮削语言'),
      this.languageOptions(), this.ctrl.tmdbLanguage, (key: string): void => {
        this.ctrl.tmdbLanguage = key.trim();
      });
  }

  private hwDecoderOptions(): PickOption[] {
    const out: PickOption[] = [new PickOption('', L10n.t('auto', '自动'))];
    for (const o of this.ctrl.availableHwDecoders) {
      out.push(new PickOption(o.key, o.label));
    }
    return out;
  }

  private showHwDecoderPick(): void {
    showOptionPickSheet(L10n.t('video_transcode_hwaccel_preferred', '优先硬件解码器'),
      this.hwDecoderOptions(), this.ctrl.preferredHwDecoder, (key: string): void => {
        this.ctrl.preferredHwDecoder = key.trim();
      });
  }

  private pickTempDir(): void {
    pickTargetFolderViaSheet(this.ctrl.transcodeTempDir, (paths: string[]): void => {
      if (paths.length === 0) {
        return;
      }
      this.ctrl.transcodeTempDir = paths[0].trim();
    });
  }

  private refreshAll(): void {
    void this.ctrl.fetchSettings(true);
    void this.ctrl.fetchTranscodeSettings(true);
    void this.ctrl.fetchSubtitleSettings(true);
  }

  /** 帮助图标（点击弹信息窗） */
  @Builder
  HelpButton(text: string) {
    SymbolGlyph($r('sys.symbol.questionmark_circle'))
      .fontSize(16)
      .fontColor([AppTheme.current().subText])
      .onClick(() => {
        DialogUtil.showInfoDialog(L10n.tip, text);
      })
  }

  /** 保存按钮（卡片右下角，对齐 Flutter ElevatedButton） */
  @Builder
  SaveButton(onTap: () => void) {
    Row() {
      Text(L10n.t('save', '保存'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.current().buttonText)
    }
    .justifyContent(FlexAlign.Center)
    .padding({ left: 20, right: 20, top: 8, bottom: 8 })
    .borderRadius(10)
    .backgroundColor(AppTheme.current().buttonBg)
    .onClick(() => {
      onTap();
    })
  }

  /** 带标题与提示的字段标签 */
  @Builder
  FieldTitle(title: string, tip: string) {
    Text(title)
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor(AppTheme.current().onSurface)
    if (tip.length > 0) {
      Text(tip)
        .fontSize(12)
        .fontColor(AppTheme.current().subText)
        .margin({ top: 4 })
    }
  }

  /** 下拉选择框外观（对齐 Flutter DropdownButtonFormField） */
  @Builder
  DropdownBox(text: string, onTap: () => void) {
    Row({ space: 6 }) {
      Text(text)
        .fontSize(14)
        .fontColor(AppTheme.current().onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(12)
        .fontColor([AppTheme.current().subText])
    }
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(8)
    .border({ width: 1, color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.3) })
    .width('100%')
    .onClick(() => {
      onTap();
    })
  }

  @Builder
  ScrapeCard() {
    Column() {
      Text(L10n.t('video_scrape_settings_title', '刮削设置'))
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .width('100%')
      Blank().height(12)
      // Token
      Row({ space: 6 }) {
        Text(L10n.t('video_tmdb_access_token', 'TMDB API 令牌'))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
        this.HelpButton(L10n.t('video_tmdb_access_token_help', '填写 TMDB API 读取令牌（v4 access token），用于刮削媒体信息'))
      }
      .width('100%')
      TextInput({ text: this.ctrl.tmdbToken, placeholder: L10n.t('video_tmdb_access_token_hint', '输入 TMDB 访问令牌') })
        .fontSize(14)
        .fontColor(AppTheme.current().onSurface)
        .placeholderColor(AppTheme.current().hint)
        .placeholderFont({ size: 13 })
        .backgroundColor(Color.Transparent)
        .borderRadius(8)
        .border({ width: 1, color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.3) })
        .height(42)
        .width('100%')
        .margin({ top: 8 })
        .onChange((v: string): void => {
          this.ctrl.tmdbToken = v;
        })
      // 语言
      Text(L10n.t('video_tmdb_language', '刮削语言'))
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .margin({ top: 12 })
      Column() {
        this.DropdownBox(this.languageLabel(), (): void => {
          this.showLanguagePick();
        })
      }
      .margin({ top: 8 })
      .width('100%')
      // 代理开关
      Row() {
        Column() {
          Text(L10n.t('video_tmdb_proxy_enable', '启用代理'))
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.current().onSurface)
          Text(L10n.t('video_tmdb_proxy_enable_tip', '通过代理服务器访问 TMDB'))
            .fontSize(12)
            .fontColor(AppTheme.current().subText)
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.ctrl.proxyEnabled })
          .selectedColor(AppTheme.current().primary)
          .onChange((v: boolean) => {
            this.ctrl.proxyEnabled = v;
          })
      }
      .alignItems(VerticalAlign.Top)
      .margin({ top: 12 })
      .width('100%')
      // 代理 URL（启用时显示）
      if (this.ctrl.proxyEnabled) {
        Text(L10n.t('video_tmdb_proxy_url', '代理地址'))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
          .margin({ top: 10 })
        TextInput({ text: this.ctrl.proxyUrl, placeholder: L10n.t('video_tmdb_proxy_url_hint', '如 http://127.0.0.1:7890') })
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
          .placeholderColor(AppTheme.current().hint)
          .placeholderFont({ size: 13 })
          .backgroundColor(Color.Transparent)
          .borderRadius(8)
          .border({ width: 1, color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.3) })
          .height(42)
          .width('100%')
          .margin({ top: 8 })
          .onChange((v: string): void => {
            this.ctrl.proxyUrl = v;
          })
        Text(L10n.t('video_tmdb_proxy_save_tip', '代理地址将在保存后生效'))
          .fontSize(12)
          .fontColor(AppTheme.current().subText)
          .margin({ top: 6 })
          .width('100%')
      }
      Row() {
        this.SaveButton((): void => {
          void this.ctrl.saveSettings();
        })
      }
      .justifyContent(FlexAlign.End)
      .margin({ top: 14 })
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(14)
  }

  @Builder
  SubtitleCard() {
    Column() {
      Text(L10n.t('video_subtitle_settings_title', '字幕设置'))
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .width('100%')
      Blank().height(12)
      Row({ space: 12 }) {
        Column() {
          Text(L10n.t('video_subtitle_pre_extract_enable', '启用字幕预提取'))
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.current().onSurface)
          Text(L10n.t('process.worker.subtitlePreExtract.purpose', '扫描时预先从视频中提取内嵌字幕，播放时可即时加载'))
            .fontSize(12)
            .fontColor(AppTheme.current().subText)
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.ctrl.subtitlePreExtractEnabled })
          .selectedColor(AppTheme.current().primary)
          .onChange((v: boolean) => {
            this.ctrl.subtitlePreExtractEnabled = v;
          })
      }
      .alignItems(VerticalAlign.Top)
      .width('100%')
      Row() {
        this.SaveButton((): void => {
          void this.ctrl.saveSubtitleSettings();
        })
      }
      .justifyContent(FlexAlign.End)
      .margin({ top: 14 })
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(14)
  }

  @Builder
  HwDecoderSummaryBox() {
    Column() {
      if (this.ctrl.findHwDecoderOption(this.ctrl.preferredHwDecoder) !== undefined) {
        Text(`${this.ctrl.findHwDecoderOption(this.ctrl.preferredHwDecoder)!.label} · ${this.ctrl.buildHwDecoderSummary(this.ctrl.findHwDecoderOption(this.ctrl.preferredHwDecoder)!)}`)
          .fontSize(13)
          .fontColor(AppTheme.current().onSurface)
          .width('100%')
      }
      if (this.ctrl.effectiveHwDecoderLabel.length > 0) {
        Text(`${L10n.t('video_transcode_hwaccel_current', '当前使用')}: ${this.ctrl.effectiveHwDecoderLabel}`)
          .fontSize(12)
          .fontColor(AppTheme.current().subText)
          .margin({ top: this.ctrl.findHwDecoderOption(this.ctrl.preferredHwDecoder) !== undefined ? 6 : 0 })
      }
      if (this.ctrl.findHwDecoderOption(this.ctrl.preferredHwDecoder) === undefined &&
        this.ctrl.effectiveHwDecoderLabel.length === 0) {
        Text(L10n.t('auto', '自动'))
          .fontSize(13)
          .fontColor(AppTheme.current().onSurface)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.4))
    .borderRadius(8)
    .width('100%')
  }

  @Builder
  TranscodeCard() {
    Column() {
      Text(L10n.t('video_transcode_settings_title', '转码设置'))
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .width('100%')
      Blank().height(12)
      // 硬解
      Text(L10n.t('video_transcode_hwaccel_preferred', '优先硬件解码器'))
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
      Text(L10n.t('video_transcode_hwaccel_preferred_tip', '转码时优先使用的硬件解码器，选择自动由系统决定'))
        .fontSize(12)
        .fontColor(AppTheme.current().subText)
        .margin({ top: 4 })
      if (this.ctrl.availableHwDecoders.length === 0) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.memory_module'))
            .fontSize(16)
            .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.65)])
          Text(L10n.t('video_transcode_hwaccel_none', '未检测到可用硬件解码器'))
            .fontSize(14)
            .fontColor(AppTheme.current().onSurface)
        }
        .padding({ left: 12, right: 12, top: 12, bottom: 12 })
        .borderRadius(8)
        .border({ width: 1, color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.3) })
        .width('100%')
        .margin({ top: 8 })
      } else {
        Column() {
          this.DropdownBox(this.ctrl.preferredHwDecoder.length === 0 ? L10n.t('auto', '自动')
            : (this.ctrl.findHwDecoderOption(this.ctrl.preferredHwDecoder)?.label ?? ''), (): void => {
            this.showHwDecoderPick();
          })
          Column() {
            this.HwDecoderSummaryBox()
          }
          .margin({ top: 8 })
          .width('100%')
        }
        .margin({ top: 8 })
        .width('100%')
      }
      // 临时目录
      Row({ space: 8 }) {
        Column() {
          Text(L10n.t('video_transcode_temp_dir', '转码临时目录'))
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.current().onSurface)
          Text(L10n.t('video_transcode_temp_dir_tip', '转码过程中的临时文件存放目录'))
            .fontSize(12)
            .fontColor(AppTheme.current().subText)
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text(L10n.t('select', '选择'))
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .onClick(() => {
            this.pickTempDir();
          })
        Text(L10n.t('reset', '重置'))
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .onClick(() => {
            this.ctrl.transcodeTempDir = '';
          })
      }
      .alignItems(VerticalAlign.Top)
      .margin({ top: 12 })
      .width('100%')
      Text(this.ctrl.transcodeTempDir.length > 0 ? this.ctrl.transcodeTempDir : L10n.t('default', '默认'))
        .fontSize(13)
        .fontColor(AppTheme.current().onSurface)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .borderRadius(6)
        .border({ width: 1, color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.3) })
        .width('100%')
        .margin({ top: 8 })
      Row() {
        this.SaveButton((): void => {
          void this.ctrl.saveTranscodeSettings();
        })
      }
      .justifyContent(FlexAlign.End)
      .margin({ top: 14 })
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(14)
  }

  build() {
    Column() {
      // 标题 + 刷新
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        Text(L10n.t('video_other_settings_title', '其他设置'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
          .margin({ right: 10 })
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(20)
          .fontColor([AppTheme.current().primary])
          .onClick(() => {
            this.refreshAll();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 10 })

      Scroll() {
        Column() {
          this.ScrapeCard()
          Blank().height(12)
          this.SubtitleCard()
          Blank().height(12)
          this.TranscodeCard()
          Blank().height(16)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.current().cardBg)
  }
}
