import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { ThemeManager } from '../../../core/theme/ThemeManager';
import { AppEventBus } from '../../../common/AppEventBus';
import { GlassCard } from '../../../common/components/GlassCard';
import { cfgBool, cfgNum, cfgNumText, cfgStr } from '../models/TransmissionModels';
import { TransmissionController } from '../controllers/TransmissionController';

/** Tracker 拉取超时上限（秒），与 Flutter clamp(1, 120) 一致 */
const TRACKER_TIMEOUT_MIN_S = 1;
const TRACKER_TIMEOUT_MAX_S = 120;

/**
 * 设置标签页（对齐 Flutter _SettingsTab）：
 * RPC 端口/限速/peer 端口与连接数/默认 Tracker/超时 + 5 个功能开关 + 保存与重启按钮。
 * 配置到达后同步一次表单初值（对齐 initState._loadFromConfig，但容忍异步加载）。
 */
@ComponentV2
export struct TransmissionSettingsTab {
  @Param ctrl: TransmissionController = new TransmissionController();
  /** 主题变化刷新计数（AppTheme.current() 非响应式） */
  @Local themeTick: number = 0;
  // 表单状态（对齐 _SettingsTabState 字段）
  @Local rpcPortText: string = '';
  @Local speedDownText: string = '0';
  @Local speedUpText: string = '0';
  @Local peerPortText: string = '';
  @Local peerLimitGlobalText: string = '200';
  @Local peerLimitPerTorrentText: string = '50';
  @Local trackersText: string = '';
  @Local trackerTimeoutText: string = '10';
  @Local autoStart: boolean = false;
  @Local dhtEnabled: boolean = true;
  @Local pexEnabled: boolean = true;
  @Local utpEnabled: boolean = true;
  @Local portForwarding: boolean = true;
  /** 配置首次到达后不再覆盖用户输入 */
  private syncedFromConfig: boolean = false;
  private themeListener: (data: string) => void = (_data: string): void => {
    this.themeTick++;
  };

  aboutToAppear(): void {
    AppEventBus.on(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    this.syncFromConfigIfNeeded();
  }

  aboutToDisappear(): void {
    AppEventBus.off(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
  }

  /** 配置异步到达后同步表单（对齐 _loadFromConfig） */
  @Monitor('ctrl.config')
  onConfigChanged(): void {
    this.syncFromConfigIfNeeded();
  }

  private syncFromConfigIfNeeded(): void {
    if (this.syncedFromConfig) {
      return;
    }
    const cfg = this.ctrl.config;
    const keys = Object.keys(cfg);
    if (keys.length === 0) {
      return;
    }
    this.syncedFromConfig = true;
    this.rpcPortText = cfgNumText(cfg, 'rpc_port');
    this.speedDownText = `${cfgNum(cfg, 'speed_limit_down', 0)}`;
    this.speedUpText = `${cfgNum(cfg, 'speed_limit_up', 0)}`;
    this.peerPortText = cfgNumText(cfg, 'peer_port');
    this.peerLimitGlobalText = `${cfgNum(cfg, 'peer_limit_global', 200)}`;
    this.peerLimitPerTorrentText = `${cfgNum(cfg, 'peer_limit_per_torrent', 50)}`;
    this.trackersText = cfgStr(cfg, 'default_trackers');
    const timeoutMs = Math.trunc(cfgNum(cfg, 'tracker_url_fetch_timeout_ms', 10000));
    this.trackerTimeoutText = `${Math.round(timeoutMs / 1000)}`;
    this.autoStart = cfgBool(cfg, 'auto_start', false);
    this.dhtEnabled = cfgBool(cfg, 'dht_enabled', true);
    this.pexEnabled = cfgBool(cfg, 'pex_enabled', true);
    this.utpEnabled = cfgBool(cfg, 'utp_enabled', true);
    this.portForwarding = cfgBool(cfg, 'port_forwarding', true);
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  /** 保存（对齐 _save：组装配置体后交给控制器） */
  private save(): Promise<void> {
    const timeoutS = clampInt(parseIntOr(this.trackerTimeoutText, 10),
      TRACKER_TIMEOUT_MIN_S, TRACKER_TIMEOUT_MAX_S);
    const body: Record<string, Object | null> = {
      'rpc_port': parseIntOrNull(this.rpcPortText),
      'speed_limit_down': parseIntOr(this.speedDownText, 0),
      'speed_limit_up': parseIntOr(this.speedUpText, 0),
      'peer_port': parseIntOrNull(this.peerPortText),
      'peer_limit_global': parseIntOr(this.peerLimitGlobalText, 200),
      'peer_limit_per_torrent': parseIntOr(this.peerLimitPerTorrentText, 50),
      'default_trackers': this.trackersText.trim(),
      'tracker_url_fetch_timeout_ms': timeoutS * 1000,
      'auto_start': this.autoStart,
      'dht_enabled': this.dhtEnabled,
      'pex_enabled': this.pexEnabled,
      'utp_enabled': this.utpEnabled,
      'port_forwarding': this.portForwarding
    };
    return this.ctrl.saveConfig(body);
  }

  build() {
    Scroll() {
      Column() {
        GlassCard({ padValue: 16 }) {
          this.SettingsForm()
        }
      }
      .width('100%')
      .padding(12)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.Top)
    .opacity(this.themeTick >= 0 ? 1 : 1)
  }

  @Builder
  SettingsForm() {
    Column({ space: 12 }) {
      Text(L10n.t('transmission_tab_settings', '设置'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().onSurface)
        .width('100%')

      this.NumberField(L10n.t('transmission_rpc_port', 'RPC 端口'), this.rpcPortText,
        (v: string): void => {
          this.rpcPortText = v;
        })
      Row({ space: 12 }) {
        Column() {
          this.NumberField(L10n.t('transmission_speed_limit_down', '下载限速 (KB/s，0=不限)'),
            this.speedDownText, (v: string): void => {
              this.speedDownText = v;
            })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Column() {
          this.NumberField(L10n.t('transmission_speed_limit_up', '上传限速 (KB/s，0=不限)'),
            this.speedUpText, (v: string): void => {
              this.speedUpText = v;
            })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)

      this.NumberField(L10n.t('transmission_peer_port', 'Peer 端口'), this.peerPortText,
        (v: string): void => {
          this.peerPortText = v;
        })
      Row({ space: 12 }) {
        Column() {
          this.NumberField(L10n.t('transmission_peer_limit_global', '全局连接数上限'),
            this.peerLimitGlobalText, (v: string): void => {
              this.peerLimitGlobalText = v;
            })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Column() {
          this.NumberField(L10n.t('transmission_peer_limit_per_torrent', '单任务连接数上限'),
            this.peerLimitPerTorrentText, (v: string): void => {
              this.peerLimitPerTorrentText = v;
            })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)

      // 默认 Tracker（多行，对齐 minLines:3 maxLines:8）
      Column({ space: 6 }) {
        Text(L10n.t('transmission_default_trackers', '默认 Tracker 列表'))
          .fontSize(12)
          .fontColor(this.palette().subText)
        TextArea({ text: this.trackersText,
          placeholder: L10n.t('transmission_default_trackers_hint', '每行一个 Tracker 地址，或 https 的 .txt 订阅链接') })
          .fontSize(13)
          .fontColor(this.palette().onSurface)
          .placeholderColor(this.palette().hint)
          .backgroundColor(this.palette().inputFill)
          .borderRadius(8)
          .border({ width: 1, color: this.palette().inputBorder })
          .height(88)
          .width('100%')
          .onChange((v: string): void => {
            this.trackersText = v;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      this.NumberField(L10n.t('transmission_tracker_fetch_timeout', 'Tracker 列表拉取超时（秒）'),
        this.trackerTimeoutText, (v: string): void => {
          this.trackerTimeoutText = v;
        })

      this.SwitchRow(L10n.t('transmission_auto_start', '随 NasCab 自动启动'),
        this.autoStart, (v: boolean): void => {
          this.autoStart = v;
        })
      this.SwitchRow(L10n.t('transmission_dht_enabled', '启用 DHT'),
        this.dhtEnabled, (v: boolean): void => {
          this.dhtEnabled = v;
        })
      this.SwitchRow(L10n.t('transmission_pex_enabled', '启用 PEX'),
        this.pexEnabled, (v: boolean): void => {
          this.pexEnabled = v;
        })
      this.SwitchRow(L10n.t('transmission_utp_enabled', '启用 uTP'),
        this.utpEnabled, (v: boolean): void => {
          this.utpEnabled = v;
        })
      this.SwitchRow(L10n.t('transmission_port_forwarding', '启用端口转发'),
        this.portForwarding, (v: boolean): void => {
          this.portForwarding = v;
        })

      // 动作行（对齐 Save + Restart 按钮）
      Row({ space: 12 }) {
        Button(L10n.t('save', '保存'), { type: ButtonType.Capsule })
          .fontSize(14)
          .fontColor(this.palette().buttonText)
          .backgroundColor(this.palette().buttonBg)
          .height(40)
          .enabled(!this.ctrl.savingConfig)
          .opacity(this.ctrl.savingConfig ? 0.5 : 1)
          .onClick((): void => {
            void this.save();
          })
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(15)
            .fontColor([this.palette().onSurface])
          Text(L10n.t('transmission_restart_service', '重启服务'))
            .fontSize(14)
            .fontColor(this.palette().onSurface)
        }
        .justifyContent(FlexAlign.Center)
        .height(40)
        .padding({ left: 16, right: 16 })
        .borderRadius(20)
        .border({ width: 1, color: this.palette().divider })
        .opacity(this.ctrl.serviceOperating ? 0.5 : 1)
        .onClick((): void => {
          if (!this.ctrl.serviceOperating) {
            void this.ctrl.restartService();
          }
        })
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 数字输入框（对齐 OutlineInputBorder TextField + number 键盘） */
  @Builder
  NumberField(label: string, text: string, onChanged: (v: string) => void) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(12)
        .fontColor(this.palette().subText)
      TextInput({ text: text })
        .fontSize(13)
        .fontColor(this.palette().onSurface)
        .placeholderColor(this.palette().hint)
        .backgroundColor(this.palette().inputFill)
        .borderRadius(8)
        .border({ width: 1, color: this.palette().inputBorder })
        .type(InputType.NUMBER_DECIMAL)
        .height(42)
        .width('100%')
        .onChange((v: string): void => {
          onChanged(v);
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 开关行（对齐 _SettingsSwitchRow） */
  @Builder
  SwitchRow(label: string, value: boolean, onChanged: (v: boolean) => void) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(this.palette().onSurface)
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(this.palette().primary)
        .onChange((on: boolean): void => {
          onChanged(on);
        })
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }
}

/** 文本 → 整数（非法 → fallback） */
function parseIntOr(text: string, fallback: number): number {
  const v = parseInt(text.trim(), 10);
  return Number.isFinite(v) ? v : fallback;
}

/** 文本 → 整数（空/非法 → null，对齐 Dart int.tryParse） */
function parseIntOrNull(text: string): number | null {
  const t = text.trim();
  if (t.length === 0) {
    return null;
  }
  const v = parseInt(t, 10);
  return Number.isFinite(v) ? v : null;
}

function clampInt(v: number, lo: number, hi: number): number {
  return Math.min(Math.max(Math.trunc(v), lo), hi);
}
