import { L10n } from '../../core/localization/L10n';
import { ToastUtil } from '../../common/ToastUtil';
import { DialogUtil } from '../../common/DialogUtil';
import { VideoTmdbSettingsApiService } from '../service/VideoApiServices';

/** 转码硬件解码器选项（对齐 Flutter TranscodeHwDecoderOption） */
export class TranscodeHwDecoderOption {
  key: string = '';
  label: string = '';
  kind: string = '';
  codecs: string[] = [];

  static fromJson(e: Object): TranscodeHwDecoderOption {
    const m = e as Record<string, Object>;
    const o = new TranscodeHwDecoderOption();
    o.key = `${m['key'] ?? ''}`.trim();
    o.label = `${m['label'] ?? ''}`.trim();
    o.kind = `${m['kind'] ?? ''}`.trim();
    const codecsRaw = m['codecs'];
    if (Array.isArray(codecsRaw)) {
      for (const c of codecsRaw as Object[]) {
        const s = `${c}`.trim();
        if (s.length > 0) {
          o.codecs.push(s);
        }
      }
    }
    return o;
  }
}

/**
 * 影音其他设置控制器（对齐 Flutter VideoOtherSettingsController）：
 * TMDB 刮削配置（token/代理/语言）+ 转码配置（临时目录/硬解）+ 字幕预提取配置。
 */
@ObservedV2
export class VideoOtherSettingsController {
  /** TMDB 支持的语言（与国际化 13 种一致：空为跟随系统） */
  static readonly allowedTmdbLanguages: string[] =
    ['', 'en-US', 'zh-CN', 'es-ES', 'fr-FR', 'de-DE', 'ja-JP', 'pt-BR',
      'ru-RU', 'ar-SA', 'ko-KR', 'th-TH', 'vi-VN', 'id-ID'];

  private api: VideoTmdbSettingsApiService = new VideoTmdbSettingsApiService();

  @Trace loading: boolean = false;
  // 表单草稿（Token/代理 URL 为输入框文本，非 @Trace 也可，但统一可观察）
  @Trace tmdbToken: string = '';
  @Trace proxyUrl: string = '';
  @Trace proxyEnabled: boolean = false;
  @Trace tmdbLanguage: string = '';
  @Trace transcodeTempDir: string = '';
  @Trace preferredHwDecoder: string = '';
  @Trace effectiveHwDecoderLabel: string = '';
  @Trace availableHwDecoders: TranscodeHwDecoderOption[] = [];
  @Trace subtitlePreExtractEnabled: boolean = true;

  init(): void {
    void this.fetchSettings();
    void this.fetchTranscodeSettings();
    void this.fetchSubtitleSettings();
  }

  dispose(): void {
  }

  /** 拉取 TMDB 刮削配置（对齐 Flutter fetchSettings；enc. 开头 token 不回填） */
  async fetchSettings(showLoading: boolean = false): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    if (showLoading) {
      DialogUtil.showLoading(L10n.loading);
    }
    try {
      const res = await this.api.getTmdbConfig();
      if (!res.success) {
        if (showLoading) {
          ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
        }
        return;
      }
      const data = res.data ?? {};
      const rawToken = `${data['accessToken'] ?? ''}`.trim();
      // 已加密的 token（enc. 开头）不显示、不回填
      this.tmdbToken = rawToken.startsWith('enc.') ? '' : rawToken;
      this.proxyEnabled = data['proxyEnable'] === 1 || data['proxyEnable'] === '1';
      this.proxyUrl = `${data['proxyUrl'] ?? ''}`.trim();
      const lang = `${data['language'] ?? ''}`.trim();
      this.tmdbLanguage = VideoOtherSettingsController.allowedTmdbLanguages.includes(lang) ? lang : '';
    } finally {
      this.loading = false;
      if (showLoading) {
        DialogUtil.dismissLoading();
      }
    }
  }

  /** 拉取转码配置（对齐 Flutter fetchTranscodeSettings） */
  async fetchTranscodeSettings(showLoading: boolean = false): Promise<void> {
    if (showLoading) {
      DialogUtil.showLoading(L10n.loading);
    }
    try {
      const res = await this.api.getTranscodeConfig();
      if (!res.success) {
        if (showLoading) {
          ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
        }
        return;
      }
      const data = res.data ?? {};
      this.transcodeTempDir = `${data['tempDir'] ?? ''}`.trim();
      const optionsRaw = data['availableHwDecoders'];
      const options: TranscodeHwDecoderOption[] = [];
      if (Array.isArray(optionsRaw)) {
        for (const item of optionsRaw as Object[]) {
          const o = TranscodeHwDecoderOption.fromJson(item);
          if (o.key.length > 0) {
            options.push(o);
          }
        }
      }
      this.availableHwDecoders = options;
      const preferred = `${data['preferredHwDecoder'] ?? ''}`.trim();
      this.preferredHwDecoder = options.some((item: TranscodeHwDecoderOption): boolean => item.key === preferred)
        ? preferred : '';
      const eff = data['effectiveHwDecoder'] as Record<string, Object> | undefined;
      this.effectiveHwDecoderLabel = eff === undefined ? '' : `${eff['label'] ?? ''}`.trim();
    } finally {
      if (showLoading) {
        DialogUtil.dismissLoading();
      }
    }
  }

  /** 拉取字幕配置（对齐 Flutter fetchSubtitleSettings） */
  async fetchSubtitleSettings(showLoading: boolean = false): Promise<void> {
    if (showLoading) {
      DialogUtil.showLoading(L10n.loading);
    }
    try {
      const res = await this.api.getSubtitleConfig();
      if (!res.success) {
        if (showLoading) {
          ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
        }
        return;
      }
      const data = res.data ?? {};
      const v = data['preExtractEnable'];
      this.subtitlePreExtractEnabled = v === 1 || v === '1' || v === true;
    } finally {
      if (showLoading) {
        DialogUtil.dismissLoading();
      }
    }
  }

  /** 保存 TMDB 刮削配置（对齐 Flutter saveSettings） */
  async saveSettings(): Promise<void> {
    const accessToken = this.tmdbToken.trim();
    const enableProxy = this.proxyEnabled;
    const proxyUrl = this.proxyUrl.trim();
    const language = this.tmdbLanguage.trim();
    if (enableProxy && proxyUrl.length === 0) {
      ToastUtil.show(L10n.t('video_tmdb_proxy_required', '启用代理时必须填写代理地址'));
      return;
    }
    DialogUtil.showLoading(L10n.loading);
    try {
      const res = await this.api.setTmdbConfig(accessToken, enableProxy, proxyUrl, language);
      if (!res.success) {
        DialogUtil.dismissLoading();
        ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
        return;
      }
      DialogUtil.dismissLoading();
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      await this.fetchSettings();
    } finally {
      DialogUtil.dismissLoading();
    }
  }

  /** 保存字幕配置（对齐 Flutter saveSubtitleSettings） */
  async saveSubtitleSettings(): Promise<void> {
    DialogUtil.showLoading(L10n.loading);
    try {
      const res = await this.api.setSubtitleConfig(this.subtitlePreExtractEnabled);
      if (!res.success) {
        DialogUtil.dismissLoading();
        ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
        return;
      }
      DialogUtil.dismissLoading();
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      await this.fetchSubtitleSettings();
    } finally {
      DialogUtil.dismissLoading();
    }
  }

  /** 保存转码配置（对齐 Flutter saveTranscodeSettings） */
  async saveTranscodeSettings(): Promise<void> {
    DialogUtil.showLoading(L10n.loading);
    try {
      const res = await this.api.setTranscodeConfig(this.transcodeTempDir.trim(), this.preferredHwDecoder.trim());
      if (!res.success) {
        DialogUtil.dismissLoading();
        ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
        return;
      }
      DialogUtil.dismissLoading();
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      await this.fetchTranscodeSettings();
    } finally {
      DialogUtil.dismissLoading();
    }
  }

  findHwDecoderOption(key: string): TranscodeHwDecoderOption | undefined {
    const value = key.trim();
    for (const item of this.availableHwDecoders) {
      if (item.key === value) {
        return item;
      }
    }
    return undefined;
  }

  /** 硬解摘要（类型 + 编解码，对齐 Flutter buildHwDecoderSummary） */
  buildHwDecoderSummary(option: TranscodeHwDecoderOption): string {
    const parts: string[] = [];
    if (option.kind.length > 0) {
      parts.push(option.kind === 'discrete'
        ? L10n.t('video_transcode_hwaccel_kind_discrete', '独立显卡')
        : option.kind === 'integrated'
          ? L10n.t('video_transcode_hwaccel_kind_integrated', '集成显卡')
          : option.kind);
    }
    if (option.codecs.length > 0) {
      const uniq: string[] = [];
      for (const c of option.codecs) {
        const up = c.toUpperCase();
        if (!uniq.includes(up)) {
          uniq.push(up);
        }
      }
      parts.push(uniq.join(' / '));
    }
    return parts.join(' · ');
  }
}
