import pasteboard from '@ohos.pasteboard';
import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { ToastUtil } from '../../../common/ToastUtil';
import { DialogUtil } from '../../../common/DialogUtil';
import { WindowStore } from '../../../common/WindowStore';
import { GlassCard } from '../../../common/components/GlassCard';
import { PickOption, showOptionPickSheet } from '../../../common/components/OptionPickSheet';
import { ServiceMainController } from '../controllers/ServiceMainController';
import { P2pServer } from '../models/ServiceModels';
import { ServiceNotLoggedInCard, ServiceLoadingOverlay, ServiceFilledButton, ServiceTextLink } from './ServiceParts';
import { NASCAB_WEBSITE_BASE_URL } from '../services/ServiceApiService';
import { formatErrorCode } from '../services/ServiceFormat';
import { QrCodeView } from '../../share_server/views/parts/QrCodeView';

/**
 * P2P 远程访问视图（对齐 Flutter ServiceRemoteAccessView）：
 * 开关卡（开启后展示配对码/二维码/错误或绑定设备卡）+ 节点选择卡 + 使用指南卡。
 * showTitle=false 时由外层页签标题栏承载标题（对齐 Flutter 移动端 IndexedStack 用法）。
 */
@ComponentV2
export struct ServiceRemoteAccessView {
  @Param showTitle: boolean = true;
  @Param onGotoAccount: () => void = (): void => {
  };
  @Local ctrl: ServiceMainController = ServiceMainController.getInstance();
  /** 主题变化刷新计数（AppTheme.current() 非响应式） */
  @Local themeTick: number = 0;
  private readonly qrSize: number = 120;

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  // ===== 展示辅助（对齐 Flutter _serverDisplayName / _serverOptionLabel 等） =====

  /** P2P 开关状态（命名避开系统通用属性 enabled，防遮蔽） */
  private get p2pEnabled(): boolean {
    return this.ctrl.remoteAccessEnabled;
  }

  private get loading(): boolean {
    return this.ctrl.remoteAccessLoading;
  }

  private get loggedIn(): boolean {
    return this.ctrl.nascabLoggedIn;
  }

  private get isBindError(): boolean {
    return this.ctrl.p2pErrorCode === 'P2P.ERR_DEVICE_NOT_BIND';
  }

  /** 节点状态文案 key（对齐 Flutter nodeStatusKey 推导） */
  private nodeStatusKey(): string {
    if (!this.p2pEnabled) {
      return 'service_remote_access_node_status_disabled';
    }
    if (this.isBindError) {
      return 'service_remote_access_node_status_unbound';
    }
    if (this.ctrl.p2pErrorCode.length > 0) {
      return 'service_remote_access_node_status_error';
    }
    if (this.ctrl.p2pConnectedDomain.length > 0) {
      return 'service_remote_access_node_status_connected';
    }
    return 'service_remote_access_node_status_connecting';
  }

  private serverDisplayName(s: P2pServer): string {
    const languageCode = L10n.locale.split('_')[0].toLowerCase();
    if (languageCode === 'zh' && s.chineseName.trim().length > 0) {
      return s.chineseName.trim();
    }
    if (s.englishName.trim().length > 0) {
      return s.englishName.trim();
    }
    if (s.name.trim().length > 0) {
      return s.name.trim();
    }
    return s.domain.trim();
  }

  private serverOptionLabel(s: P2pServer): string {
    const name = this.serverDisplayName(s);
    const domain = s.domain.trim();
    if (name.length === 0) {
      return domain;
    }
    if (domain.length === 0 || domain === name) {
      return name;
    }
    return `${name} · ${domain}`;
  }

  private findServerByDomain(domain: string): P2pServer | undefined {
    const normalized = domain.trim().toLowerCase();
    if (normalized.length === 0) {
      return undefined;
    }
    return this.ctrl.p2pServers.find((s: P2pServer): boolean =>
      s.domain.trim().toLowerCase() === normalized);
  }

  /** 当前连接节点展示文案（空 → 提示文案；找不到匹配服务器 → 原始 domain） */
  private currentConnectedLabel(): string {
    if (this.ctrl.p2pConnectedDomain.length === 0) {
      return L10n.t('service_remote_access_node_connected_empty', '暂未连接节点');
    }
    const server = this.findServerByDomain(this.ctrl.p2pConnectedDomain);
    const label = server !== undefined ? this.serverOptionLabel(server) : '';
    return label.length > 0 ? label : this.ctrl.p2pConnectedDomain;
  }

  private openExternal(url: string): void {
    const ctx = WindowStore.appContext;
    if (ctx === undefined) {
      return;
    }
    try {
      ctx.openLink(url);
    } catch (_e) {
      // 打开失败静默处理
    }
  }

  /** P2P 帮助页（对齐 Flutter 帮助链接，language 取语言主码） */
  private openHelpPage(): void {
    const lang = L10n.locale.split('_')[0];
    this.openExternal(`${NASCAB_WEBSITE_BASE_URL}/others/helpP2p.html?language=${lang}`);
  }

  // ===== 交互 =====

  private async toggleEnabled(next: boolean): Promise<void> {
    if (next && !this.loggedIn) {
      ToastUtil.show(L10n.t('service_nascab_not_logged_in', '未登录'));
      await this.ctrl.refreshRemoteAccess();
      return;
    }
    const ok = await this.ctrl.setRemoteAccessEnabled(next);
    if (!ok) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      await this.ctrl.refreshRemoteAccess();
    }
  }

  private async resetPairCode(): Promise<void> {
    const confirmed = await DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('service_remote_access_pair_code_reset_confirm', '确定重置配对码吗？重置后原配对码将失效'),
      undefined,
      L10n.t('reset', '重置'),
      L10n.t('cancel', '取消'));
    if (confirmed !== true) {
      return;
    }
    const resetOk = await this.ctrl.resetPairCode();
    if (!resetOk) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      await this.ctrl.refreshRemoteAccess();
      return;
    }
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }

  private copyPairCode(): void {
    if (this.ctrl.pairCode.length === 0) {
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.ctrl.pairCode);
      pasteboard.getSystemPasteboard().setPasteData(data);
      ToastUtil.show(L10n.t('service_remote_access_copied', '已复制配对码'));
    } catch (_e) {
      // 剪贴板写入失败不阻塞
    }
  }

  private async editPairCode(): Promise<void> {
    if (this.loading || !this.loggedIn) {
      return;
    }
    const next = await DialogUtil.showInputDialog(
      L10n.t('service_remote_access_custom_pair_code_title', '自定义配对码'),
      L10n.t('service_remote_access_custom_pair_code_subtitle', '仅支持 6-30 位数字与英文字母'),
      this.ctrl.pairCode,
      L10n.t('confirm', '确认'),
      L10n.t('cancel', '取消'),
      (value: string): string | undefined => {
        if (value.length === 0 || /^[0-9a-zA-Z]{6,30}$/.test(value)) {
          return undefined;
        }
        return L10n.t('P2P_CUSTOM_PAIR_CODE_INVALID_FORMAT', '配对码格式无效，仅支持6-30位数字与英文字母');
      });
    if (next === undefined || typeof next !== 'string' || next.trim().length === 0) {
      return;
    }
    const ok = await this.ctrl.customPairCode(next.trim());
    if (ok) {
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      return;
    }
    await this.ctrl.refreshRemoteAccess();
  }

  private async bindDevice(): Promise<void> {
    const result = await this.ctrl.bindP2pDevice();
    if (result.success) {
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      return;
    }
    const errCode = result.errorCode.trim();
    if (errCode === 'P2P.ERR_DEVICE_COUNT_LIMIT') {
      const goDevices = await DialogUtil.showConfirmDialog(
        L10n.t('need_confirm', '需要确认'),
        L10n.t('P2P.ERR_DEVICE_COUNT_LIMIT', '绑定设备数量已达上限'),
        undefined,
        L10n.t('service_nascab_membership_my_devices', '我的设备'),
        L10n.t('cancel', '取消'));
      if (goDevices === true) {
        void this.ctrl.openMyDevicesUrl();
      }
    } else {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
    }
    await this.ctrl.refreshRemoteAccess();
  }

  /** 节点选择弹层（对齐 Flutter DropdownButtonFormField：auto + 服务器列表） */
  private pickNode(): void {
    if (this.loading) {
      return;
    }
    const options: PickOption[] = [new PickOption('', L10n.t('auto', '自动'))];
    this.ctrl.p2pServers.forEach((s: P2pServer): void => {
      options.push(new PickOption(s.domain.trim(), this.serverOptionLabel(s)));
    });
    const fixDomain = this.ctrl.p2pFixNodeDomain.trim();
    const dropdownValue = fixDomain.length === 0
      || this.ctrl.p2pServers.some((s: P2pServer): boolean => s.domain.trim().toLowerCase() === fixDomain.toLowerCase())
      ? fixDomain
      : '';
    showOptionPickSheet(L10n.t('service_remote_access_node_label', '指定节点'), options, dropdownValue,
      (key: string): void => {
        void this.applyNodePreference(key);
      });
  }

  private async applyNodePreference(next: string): Promise<void> {
    if (next === this.ctrl.p2pFixNodeDomain.trim()) {
      return;
    }
    const ok = await this.ctrl.setP2pNodePreference(next);
    if (!ok) {
      ToastUtil.show(L10n.t('service_remote_access_node_save_failed', '节点偏好保存失败'));
      await this.ctrl.refreshRemoteAccess(false);
      return;
    }
    ToastUtil.show(L10n.t('service_remote_access_node_saved', '节点偏好已保存'));
  }

  // ===== UI =====

  build() {
    Stack() {
      Scroll() {
        Column({ space: 12 }) {
          if (this.showTitle) {
            this.TitleRow()
          }
          if (!this.loggedIn) {
            GlassCard({ padValue: 14 }) {
              ServiceNotLoggedInCard({
                isNarrow: true,
                onGotoAccount: (): void => {
                  this.onGotoAccount();
                }
              })
            }
          }
          this.MainCard()
          if (this.p2pEnabled) {
            this.NodeCard()
          }
          this.GuideCard()
        }
        .constraintSize({ maxWidth: 720 })
        .width('100%')
        .padding(16)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      if (this.loading) {
        ServiceLoadingOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .opacity(this.themeTick >= 0 ? 1 : 1)
  }

  /** 标题行（对齐 Flutter showTitle 分支：标题 + 帮助 + 我的设备） */
  @Builder
  TitleRow() {
    Row({ space: 10 }) {
      Text(L10n.t('service_menu_remote_access', '远程访问'))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().onSurface)
      ServiceTextLink({
        label: L10n.t('help', '帮助'),
        onTap: (): void => {
          this.openHelpPage();
        }
      })
      ServiceTextLink({
        label: L10n.t('service_nascab_membership_my_devices', '我的设备'),
        onTap: (): void => {
          void this.ctrl.openMyDevicesUrl();
        }
      })
    }
    .width('100%')
  }

  /** 开关 + 配对码主卡（对齐 Flutter 开关卡） */
  @Builder
  MainCard() {
    GlassCard({ padValue: 14 }) {
      Column({ space: 10 }) {
        Row({ space: 12 }) {
          Column({ space: 6 }) {
            Text(L10n.t('service_remote_access_toggle', '启用 P2P 远程访问'))
              .fontSize(15)
              .fontColor(this.palette().onSurface)
            Text(L10n.t('service_remote_access_toggle_hint', '开启后可在任何地方通过配对码连接本机'))
              .fontSize(12.5)
              .fontColor(this.palette().subText)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.p2pEnabled })
            .selectedColor(this.palette().primary)
            .enabled(!this.loading)
            .onChange((on: boolean): void => {
              if (on !== this.p2pEnabled) {
                void this.toggleEnabled(on);
              }
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        if (this.p2pEnabled) {
          if (this.isBindError) {
            this.BindErrorCard()
          } else if (this.ctrl.p2pErrorCode.length > 0) {
            this.ErrorCodeCard()
          } else {
            this.PairCodeSection()
          }
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  /** 未绑定设备卡（对齐 Flutter P2P.ERR_DEVICE_NOT_BIND 分支） */
  @Builder
  BindErrorCard() {
    GlassCard({ padValue: 16 }) {
      Column({ space: 16 }) {
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.icloud_slash'))
            .fontSize(24)
            .fontColor([AppTheme.withAlpha(this.palette().primary, 0.9)])
          Text(L10n.t('service_p2p_device_not_bind_message', '当前设备尚未绑定到您的 NasCab 账号，绑定后即可使用 P2P 远程访问'))
            .fontSize(14)
            .fontColor(this.palette().onSurface)
            .lineHeight(20)
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        ServiceFilledButton({
          icon: $r('sys.symbol.pad_and_iphone'),
          label: L10n.t('service_p2p_bind_device_button', '绑定当前设备'),
          isEnabled: !this.loading,
          onTap: (): void => {
            void this.bindDevice();
          }
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  /** 其他错误码卡（对齐 Flutter p2pErrorCode.isNotEmpty 分支） */
  @Builder
  ErrorCodeCard() {
    GlassCard({ padValue: 14 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(20)
          .fontColor([this.palette().error])
        Text(formatErrorCode(this.ctrl.p2pErrorCode))
          .fontSize(14)
          .fontColor(this.palette().error)
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
  }

  /** 配对码区（对齐 Flutter 配对码 + 二维码分支） */
  @Builder
  PairCodeSection() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(L10n.t('service_remote_access_pair_code_label', '配对码'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().onSurface)
          .layoutWeight(1)
        ServiceTextLink({
          label: L10n.t('service_remote_access_pair_code_reset', '重置配对码'),
          onTap: (): void => {
            void this.resetPairCode();
          }
        })
        ServiceTextLink({
          label: L10n.t('refresh', '刷新'),
          onTap: (): void => {
            void this.ctrl.refreshRemoteAccess();
          }
        })
      }
      .width('100%')

      Row({ space: 6 }) {
        Text(this.ctrl.pairCode.length > 0 ? this.ctrl.pairCode
          : L10n.t('service_remote_access_pair_code_empty', '暂无配对码'))
          .fontSize(16)
          .fontColor(this.palette().onSurface)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.ctrl.pairCode.length > 0) {
          SymbolGlyph($r('sys.symbol.text_clipboard'))
            .fontSize(20)
            .fontColor([this.palette().onSurface])
            .padding(6)
            .onClick((): void => {
              this.copyPairCode();
            })
        }
        SymbolGlyph($r('sys.symbol.square_and_pencil'))
          .fontSize(20)
          .fontColor([this.loading || !this.loggedIn ? this.palette().hint : this.palette().onSurface])
          .padding(6)
          .enabled(!this.loading && this.loggedIn)
          .onClick((): void => {
            void this.editPairCode();
          })
      }
      .width('100%')

      Column() {
        if (this.ctrl.pairCode.length > 0) {
          QrCodeView({
            text: this.ctrl.pairCode,
            viewSize: this.qrSize,
            darkColor: '#000000',
            lightColor: '#FFFFFF'
          })
        } else {
          Text(L10n.t('service_remote_access_pair_code_empty', '暂无配对码'))
            .fontSize(12.5)
            .fontColor(this.palette().subText)
            .textAlign(TextAlign.Center)
            .width(this.qrSize)
            .height(this.qrSize)
        }
      }
      .padding(6)
      .borderRadius(12)
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: AppTheme.withAlpha(this.palette().divider, 0.4) })
      .margin({ top: 2 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 节点卡（对齐 Flutter 节点卡：图标标题 + 当前节点 + 状态 chip + 节点选择） */
  @Builder
  NodeCard() {
    GlassCard({ padValue: 14 }) {
      Column({ space: 14 }) {
        Row({ space: 12 }) {
          Stack() {
            Column()
              .width(40)
              .height(40)
              .borderRadius(12)
              .backgroundColor(AppTheme.withAlpha(this.palette().primary, 0.12))
            SymbolGlyph($r('sys.symbol.computer'))
              .fontSize(20)
              .fontColor([this.palette().primary])
          }
          .width(40)
          .height(40)

          Column({ space: 4 }) {
            Text(L10n.t('service_remote_access_node_title', '连接节点'))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().onSurface)
            Text(L10n.t('service_remote_access_node_subtitle', '系统会自动选择最快节点，也可以手动指定'))
              .fontSize(12.5)
              .fontColor(this.palette().subText)
              .lineHeight(17)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        Text(L10n.t('service_remote_access_node_current', '当前节点'))
          .fontSize(13)
          .fontColor(this.palette().subText)
          .width('100%')

        Row({ space: 8 }) {
          Text(this.currentConnectedLabel())
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().onSurface)
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.nodeStatusText())
            .fontSize(12.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.nodeStatusKey() === 'service_remote_access_node_status_error'
              ? this.palette().error : this.palette().onSurface)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(999)
            .backgroundColor(this.nodeStatusKey() === 'service_remote_access_node_status_connected'
              ? AppTheme.withAlpha(this.palette().primary, 0.12)
              : AppTheme.withAlpha(this.palette().onSurface, 0.08))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Row({ space: 8 }) {
          Text(this.nodePickerValueLabel())
            .fontSize(14)
            .fontColor(this.palette().onSurface)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(14)
            .fontColor([this.palette().hint])
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 11, bottom: 11 })
        .borderRadius(14)
        .border({ width: 1, color: AppTheme.withAlpha(this.palette().onSurface, 0.14) })
        .onClick((): void => {
          this.pickNode();
        })

        if (this.ctrl.p2pServers.length === 0) {
          Text(L10n.t('service_remote_access_node_server_list_empty', '暂无可用节点列表'))
            .fontSize(12)
            .fontColor(this.palette().hint)
            .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  private nodeStatusText(): string {
    return L10n.t(this.nodeStatusKey(), this.nodeStatusKey() === 'service_remote_access_node_status_connected'
      ? '已连接' : '连接中');
  }

  /** 节点选择框当前值文案（auto 或指定节点展示名） */
  private nodePickerValueLabel(): string {
    const fixDomain = this.ctrl.p2pFixNodeDomain.trim();
    if (fixDomain.length === 0) {
      return L10n.t('auto', '自动');
    }
    const server = this.findServerByDomain(fixDomain);
    return server !== undefined ? this.serverOptionLabel(server) : fixDomain;
  }

  /** 使用指南卡（对齐 Flutter 指南卡） */
  @Builder
  GuideCard() {
    GlassCard({ padValue: 14 }) {
      Column({ space: 6 }) {
        Text(L10n.t('service_remote_access_guide_title', '使用指南'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().onSurface)
          .margin({ bottom: 4 })
        Text(L10n.t('service_remote_access_guide_how_title', '如何远程连接？'))
          .fontSize(13.5)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().onSurface)
        Text(L10n.t('service_remote_access_guide_how_body', '在其他设备上安装 NasCab 客户端，选择「配对码连接」，输入本机配对码即可连接。'))
          .fontSize(12.5)
          .fontColor(this.palette().subText)
          .lineHeight(18)
        Text(L10n.t('service_remote_access_guide_use_title', '连接后可以做什么？'))
          .fontSize(13.5)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().onSurface)
          .margin({ top: 6 })
        Text(L10n.t('service_remote_access_guide_use_body', '远程连接后可以像局域网一样浏览文件、管理照片影音以及使用服务端提供的各项功能。'))
          .fontSize(12.5)
          .fontColor(this.palette().subText)
          .lineHeight(18)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }
}
