import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { ToastUtil } from '../../../common/ToastUtil';
import { GlassCard } from '../../../common/components/GlassCard';
import { ServiceMainController } from '../controllers/ServiceMainController';
import { ServiceNotLoggedInCard, ServiceLoadingOverlay, ServiceFilledButton } from './ServiceParts';
import { formatDdnsTime, formatErrorCode } from '../services/ServiceFormat';

/**
 * DDNS 视图（对齐 Flutter ServiceDdnsView）：
 * 介绍与开关卡 + 请求状态卡（加载/失败重试）+ 绑定设备卡 + 域名/类型设置卡 + 状态信息卡。
 * showTitle=false 时由外层页签标题栏承载标题（对齐 Flutter 移动端 IndexedStack 用法）。
 */
@ComponentV2
export struct ServiceDdnsView {
  @Param showTitle: boolean = true;
  @Param onGotoAccount: () => void = (): void => {
  };
  @Local ctrl: ServiceMainController = ServiceMainController.getInstance();
  /** 域名前缀输入（Flutter _domainCtrl 对应物） */
  @Local domainText: string = '';
  /** 主题变化刷新计数（AppTheme.current() 非响应式） */
  @Local themeTick: number = 0;

  aboutToAppear(): void {
    this.syncDomainText();
  }

  /** 服务端域名变化时同步输入框（对齐 Flutter _domainCtrl.text 同步逻辑） */
  @Monitor('ctrl.ddnsDomain')
  onDomainChanged(): void {
    this.syncDomainText();
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  // ===== 派生状态（对齐 Flutter build 内推导） =====

  private get loading(): boolean {
    return this.ctrl.ddnsLoading;
  }

  private get loggedIn(): boolean {
    return this.ctrl.nascabLoggedIn;
  }

  /** 需要先绑定设备（deviceId 为空或最近错误为未绑定） */
  private get needBind(): boolean {
    return this.ctrl.ddnsDeviceId.length === 0 || this.ctrl.ddnsLastError === 'P2P.ERR_DEVICE_NOT_BIND';
  }

  /** 类型单选当前值（草稿 > 已保存 > 默认 ipv4） */
  private get typeSelected(): string {
    if (this.ctrl.ddnsTypeDraft.trim().length > 0) {
      return this.ctrl.ddnsTypeDraft.trim();
    }
    return this.ctrl.ddnsType.trim().length > 0 ? this.ctrl.ddnsType.trim() : 'ipv4';
  }

  private get showRequestState(): boolean {
    return !this.ctrl.ddnsStatusReady;
  }

  private get showLoadingState(): boolean {
    return this.loading || !this.ctrl.ddnsStatusLoadFailed;
  }

  private typeLabel(type: string): string {
    return type === 'ipv6'
      ? L10n.t('service_ddns_type_ipv6', 'IPv6')
      : L10n.t('service_ddns_type_ipv4', 'IPv4');
  }

  /** 输入框与服务端域名同步（对齐 Flutter _domainCtrl.text 同步逻辑） */
  private syncDomainText(): void {
    const domain = this.ctrl.ddnsDomain.trim();
    if (this.domainText.trim() !== domain && !this.loading) {
      this.domainText = domain;
    }
  }

  // ===== 交互 =====

  private async saveDomain(): Promise<void> {
    const ok = await this.ctrl.setDdnsDomainPrefix(this.domainText.trim());
    if (!ok) {
      return;
    }
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }

  private async saveType(): Promise<void> {
    const ok = await this.ctrl.setDdnsTypeValue(this.typeSelected);
    if (!ok) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      return;
    }
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }

  private async toggleEnabled(next: boolean): Promise<void> {
    const ok = await this.ctrl.setDdnsEnabled(next);
    if (!ok) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
    }
  }

  private async bindDevice(): Promise<void> {
    const result = await this.ctrl.bindP2pDevice();
    if (result.success) {
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      await this.ctrl.refreshDdnsStatus(false);
      return;
    }
    const ec = result.errorCode.trim();
    if (ec.length > 0) {
      const translated = formatErrorCode(ec);
      ToastUtil.show(translated !== ec ? translated : ec);
    } else {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
    }
    await this.ctrl.refreshDdnsStatus(false);
  }

  // ===== UI =====

  build() {
    Stack() {
      Scroll() {
        Column({ space: 12 }) {
          if (this.showTitle) {
            Text(L10n.t('service_menu_remote_access_ddns', '远程访问 DDNS'))
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().onSurface)
              .width('100%')
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
          this.IntroCard()
          if (this.showRequestState) {
            if (this.showLoadingState) {
              this.RequestLoadingCard()
            } else {
              this.RequestFailedCard()
            }
          }
          if (!this.showRequestState && this.loggedIn && this.needBind) {
            this.BindCard()
          }
          if (!this.showRequestState && this.loggedIn && !this.needBind) {
            this.DomainCard()
            this.TypeCard()
          }
          if (!this.showRequestState && this.loggedIn) {
            this.StatusCard()
          }
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

  /** 介绍与开关卡（对齐 Flutter 介绍卡） */
  @Builder
  IntroCard() {
    GlassCard({ padValue: 16 }) {
      Column({ space: 12 }) {
        Text(L10n.t('service_ddns_intro', 'DDNS 可以将动态家庭宽带 IP 绑定到一个固定域名，方便外网访问。'))
          .fontSize(14)
          .fontColor(this.palette().subText)
          .lineHeight(20)
          .width('100%')
        Row({ space: 12 }) {
          Column({ space: 6 }) {
            Text(L10n.t('service_ddns_toggle', '启用 DDNS'))
              .fontSize(15)
              .fontColor(this.palette().onSurface)
            Text(L10n.t('service_ddns_toggle_hint', '启用后系统会自动把当前公网 IP 更新到您的域名'))
              .fontSize(12.5)
              .fontColor(this.palette().subText)
              .lineHeight(18)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.ctrl.ddnsEnabled })
            .selectedColor(this.palette().primary)
            .enabled(this.loggedIn && !this.needBind && this.ctrl.ddnsDomain.trim().length > 0 && !this.loading)
            .onChange((on: boolean): void => {
              if (on !== this.ctrl.ddnsEnabled) {
                void this.toggleEnabled(on);
              }
            })

          SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
            .fontSize(20)
            .fontColor([this.loading ? this.palette().hint : this.palette().onSurface])
            .padding(6)
            .enabled(!this.loading)
            .onClick((): void => {
              void this.ctrl.refreshDdnsStatus(true);
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  /** 请求中卡（对齐 Flutter _buildRequestStateCard loading 分支） */
  @Builder
  RequestLoadingCard() {
    GlassCard({ padValue: 24 }) {
      Row({ space: 12 }) {
        LoadingProgress()
          .width(28)
          .height(28)
          .color(this.palette().primary)
        Text(L10n.t('loading', '加载中...'))
          .fontSize(14)
          .fontColor(this.palette().subText)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
  }

  /** 请求失败卡（对齐 Flutter _buildRequestStateCard 失败分支） */
  @Builder
  RequestFailedCard() {
    GlassCard({ padValue: 24 }) {
      Column({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.icloud_slash'))
          .fontSize(32)
          .fontColor([this.palette().error])
        Text(L10n.t('network_failure', '网络请求失败，请检查服务器连接'))
          .fontSize(14)
          .fontColor(this.palette().error)
          .textAlign(TextAlign.Center)
          .width('100%')
        ServiceFilledButton({
          icon: $r('sys.symbol.arrow_counterclockwise'),
          label: L10n.t('retry', '重试'),
          onTap: (): void => {
            void this.ctrl.refreshDdnsStatus(true, true);
          }
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
  }

  /** 绑定设备卡（对齐 Flutter needBind 分支） */
  @Builder
  BindCard() {
    GlassCard({ padValue: 16 }) {
      Column({ space: 16 }) {
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.icloud_slash'))
            .fontSize(24)
            .fontColor([AppTheme.withAlpha(this.palette().primary, 0.9)])
          Text(L10n.t('service_p2p_device_not_bind_message', '当前设备尚未绑定到您的 NasCab 账号，绑定后即可使用 DDNS 功能'))
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

  /** 域名设置卡（对齐 Flutter 域名卡） */
  @Builder
  DomainCard() {
    GlassCard({ padValue: 16 }) {
      Column({ space: 12 }) {
        Text(L10n.t('service_ddns_domain_setting', '域名设置'))
          .fontSize(15)
          .fontColor(this.palette().onSurface)
          .width('100%')
        TextInput({
          text: this.domainText,
          placeholder: L10n.t('service_ddns_domain_prefix_hint', '请输入域名前缀，如 myhome')
        })
          .fontSize(14)
          .fontColor(this.palette().onSurface)
          .placeholderColor(this.palette().hint)
          .backgroundColor(this.palette().inputFill)
          .borderRadius(8)
          .border({ width: 1, color: this.palette().inputBorder })
          .height(42)
          .width('100%')
          .enabled(!this.loading)
          .onChange((v: string): void => {
            this.domainText = v;
          })
        ServiceFilledButton({
          icon: $r('sys.symbol.checkmark_square'),
          label: L10n.t('save', '保存'),
          isEnabled: !this.loading,
          onTap: (): void => {
            void this.saveDomain();
          }
        })
        if (this.ctrl.ddnsFullDomain.trim().length > 0) {
          Text(this.ctrl.ddnsFullDomain.trim())
            .fontSize(14)
            .fontColor(this.palette().subText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  /** 类型选择卡（对齐 Flutter 类型卡 RadioListTile） */
  @Builder
  TypeCard() {
    GlassCard({ padValue: 16 }) {
      Column({ space: 10 }) {
        Text(L10n.t('service_ddns_type', '解析类型'))
          .fontSize(15)
          .fontColor(this.palette().onSurface)
          .width('100%')
        this.RadioRow('ipv4', L10n.t('service_ddns_type_ipv4', 'IPv4'))
        this.RadioRow('ipv6', L10n.t('service_ddns_type_ipv6', 'IPv6'))
        ServiceFilledButton({
          icon: $r('sys.symbol.checkmark_square'),
          label: L10n.t('save', '保存'),
          isEnabled: !this.loading && this.typeSelected.length > 0,
          onTap: (): void => {
            void this.saveType();
          }
        })
        if (this.ctrl.ddnsType.trim().length > 0 && this.ctrl.ddnsTypeDraft.trim().length === 0) {
          Text(`${L10n.t('service_ddns_type', '解析类型')}: ${this.typeLabel(this.ctrl.ddnsType.trim())}`)
            .fontSize(12.5)
            .fontColor(this.palette().subText)
            .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  RadioRow(value: string, label: string) {
    Row({ space: 10 }) {
      Circle()
        .width(18)
        .height(18)
        .fill(Color.Transparent)
        .stroke(this.typeSelected === value ? this.palette().primary : this.palette().hint)
        .strokeWidth(this.typeSelected === value ? 6 : 1.5)
      Text(label)
        .fontSize(14)
        .fontColor(this.palette().onSurface)
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
    .onClick((): void => {
      if (!this.loading) {
        this.ctrl.ddnsTypeDraft = value;
      }
    })
  }

  /** 状态信息卡（对齐 Flutter 状态卡 _InfoRow） */
  @Builder
  StatusCard() {
    GlassCard({ padValue: 16 }) {
      Column({ space: 10 }) {
        Text(L10n.t('service_ddns_status', 'DDNS 状态'))
          .fontSize(15)
          .fontColor(this.palette().onSurface)
          .width('100%')
        this.InfoRow(L10n.t('service_ddns_current_domain', '当前域名'),
          this.ctrl.ddnsFullDomain.trim().length > 0 ? this.ctrl.ddnsFullDomain.trim() : '—')
        this.InfoRow(L10n.t('service_ddns_public_ip', '公网 IP'),
          this.ctrl.ddnsPublicIp.trim().length > 0 ? this.ctrl.ddnsPublicIp.trim() : '—')
        this.InfoRow(L10n.t('service_ddns_last_ip', '上次解析 IP'),
          this.ctrl.ddnsLastIp.trim().length > 0 ? this.ctrl.ddnsLastIp.trim() : '—')
        this.InfoRow(L10n.t('service_ddns_last_time', '上次解析时间'),
          formatDdnsTime(this.ctrl.ddnsLastTime).length > 0 ? formatDdnsTime(this.ctrl.ddnsLastTime) : '—')
        if (this.ctrl.ddnsLastError.trim().length > 0) {
          Text(`${L10n.t('service_ddns_last_error', '最近错误')}: ${formatErrorCode(this.ctrl.ddnsLastError.trim())}`)
            .fontSize(12.5)
            .fontColor(this.palette().error)
            .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  InfoRow(label: string, value: string) {
    Row({ space: 8 }) {
      Text(label)
        .fontSize(12.5)
        .fontColor(this.palette().subText)
        .width(140)
      Text(value)
        .fontSize(14)
        .fontColor(this.palette().onSurface)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 4, bottom: 4 })
  }
}
