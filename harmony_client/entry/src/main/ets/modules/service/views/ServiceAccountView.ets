import pasteboard from '@ohos.pasteboard';
import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { ToastUtil } from '../../../common/ToastUtil';
import { GlassCard } from '../../../common/components/GlassCard';
import { NasCabAccountController } from '../controllers/NasCabAccountController';
import { ServiceLoadingOverlay, ServiceFilledButton, ServiceTextLink } from './ServiceParts';
import { formatLastLoginText, formatMembershipTime, isMembershipExpired } from '../services/ServiceFormat';
import { svcRecord, svcStr } from '../models/ServiceModels';

/**
 * NasCab 账号视图（对齐 Flutter NasCabAccountView）：
 * 错误提示卡 + 登录态卡（头像/账号名/ID 复制/上次登录/退出与切换）+ 会员信息卡（购买/续费、我的设备等）。
 * showTitle=false 时由外层页签标题栏承载标题（对齐 Flutter 移动端 IndexedStack 用法）。
 */

/** 整数安全解析（对齐 Flutter _parseInt） */
function parseSvcInt(v: Object | undefined | null): number {
  if (v === undefined || v === null) {
    return 0;
  }
  if (typeof v === 'number') {
    return Math.trunc(v);
  }
  const n = Number(`${v}`);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
}

function copyText(text: string): void {
  try {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setPasteData(data);
  } catch (_e) {
    // 剪贴板写入失败不阻塞
  }
}

@ComponentV2
export struct ServiceAccountView {
  @Param showTitle: boolean = true;
  @Local ctrl: NasCabAccountController = NasCabAccountController.getInstance();
  /** 主题变化刷新计数（AppTheme.current() 非响应式） */
  @Local themeTick: number = 0;

  build() {
    Stack() {
      Scroll() {
        Column({ space: 12 }) {
          if (this.showTitle) {
            Text(L10n.t('service_nascab_title', 'NasCab 账号'))
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().onSurface)
              .width('100%')
          }
          if (this.ctrl.errorText.trim().length > 0) {
            this.ErrorCard(this.ctrl.errorText.trim())
          }
          GlassCard({ padValue: 14 }) {
            if (this.ctrl.isLoggedIn) {
              this.LoggedInCard()
            } else {
              this.LoggedOutCard()
            }
          }
          if (this.ctrl.isLoggedIn) {
            this.MembershipCard()
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

      if (this.ctrl.isLoading) {
        ServiceLoadingOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .opacity(this.themeTick >= 0 ? 1 : 1)
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  // ===== 错误提示卡（对齐 Flutter errorText 卡） =====

  @Builder
  ErrorCard(errorText: string) {
    GlassCard({ padValue: 14 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(20)
          .fontColor([this.palette().error])
        Text(errorText)
          .fontSize(14)
          .fontColor(this.palette().onSurface)
          .layoutWeight(1)
        ServiceTextLink({
          label: L10n.t('retry', '重试'),
          onTap: (): void => {
            void this.ctrl.refreshUser();
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
  }

  // ===== 未登录卡（对齐 _LoggedOutCard） =====

  @Builder
  LoggedOutCard() {
    Column({ space: 8 }) {
      Text(L10n.t('service_nascab_not_logged_in', '未登录'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette().onSurface)
        .width('100%')
      Text(L10n.t('service_nascab_not_logged_in_hint', '登录后可使用 NasCab 远程服务能力'))
        .fontSize(14)
        .fontColor(this.palette().subText)
        .width('100%')
      Row() {
        ServiceFilledButton({
          icon: $r('sys.symbol.entrance_and_exit'),
          label: L10n.t('service_nascab_login', '登录 NasCab 账号'),
          onTap: (): void => {
            void this.ctrl.login();
          }
        })
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ===== 已登录卡（对齐 _LoggedInCard） =====

  /** 第三方登录类型标识（wechat/google/apple），用于显示登录来源图标 */
  private loginType(): string {
    const loginType = svcStr(this.ctrl.user?.['loginType']).trim().toLowerCase();
    return ['wechat', 'google', 'apple'].indexOf(loginType) >= 0 ? loginType : '';
  }

  private displayName(): string {
    const nickname = svcStr(this.ctrl.user?.['nickname']).trim();
    if (nickname.length > 0) {
      return nickname;
    }
    const email = svcStr(this.ctrl.user?.['email']).trim();
    if (email.length > 0) {
      return email;
    }
    return svcStr(this.ctrl.user?.['id']);
  }

  @Builder
  LoggedInCard() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Stack() {
          Circle()
            .width(44)
            .height(44)
            .fill(AppTheme.withAlpha(this.palette().onSurface, 0.2))
          SymbolGlyph($r('sys.symbol.person_fill'))
            .fontSize(22)
            .fontColor([AppTheme.withAlpha(this.palette().primary, 0.9)])
        }
        .width(44)
        .height(44)

        Column({ space: 4 }) {
          Row({ space: 8 }) {
            if (this.loginType().length > 0) {
              Image($rawfile(`icons/${this.loginType()}.png`))
                .width(22)
                .height(22)
                .objectFit(ImageFit.Contain)
            }
            Text(this.displayName())
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().onSurface)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')

          Text(`ID:${svcStr(this.ctrl.user?.['id'])}`)
            .fontSize(13)
            .fontColor(this.palette().subText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .onClick((): void => {
              const id = svcStr(this.ctrl.user?.['id']);
              if (id.length > 0) {
                copyText(id);
                ToastUtil.show(L10n.t('copied', '已复制'));
              }
            })

          Row({ space: 8 }) {
            Text(`${L10n.t('service_nascab_last_login', '上次登录：@time', L10n.paramsOf('time',
              formatLastLoginText(this.ctrl.user?.['lastLoginAt']).length > 0
                ? formatLastLoginText(this.ctrl.user?.['lastLoginAt']) : '-'))}`)
              .fontSize(12)
              .fontColor(this.palette().subText)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            ServiceTextLink({
              label: L10n.t('refresh', '刷新'),
              onTap: (): void => {
                void this.ctrl.refreshAccount();
              }
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Row({ space: 10 }) {
        ServiceFilledButton({
          icon: $r('sys.symbol.entrance_and_exit'),
          label: L10n.t('service_nascab_logout', '退出登录'),
          onTap: (): void => {
            void this.ctrl.logout();
          }
        })
        ServiceFilledButton({
          icon: $r('sys.symbol.person_crop_circle_fill'),
          label: L10n.t('service_nascab_switch_account', '切换账号'),
          onTap: (): void => {
            void this.ctrl.switchAccount();
          }
        })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ===== 会员卡（对齐 _MembershipCard） =====

  private membership(): Record<string, Object> {
    return svcRecord(this.ctrl.user?.['membership']);
  }

  private vipTypeLabel(): string {
    const vipType = parseSvcInt(this.membership()['vipType'] ?? this.membership()['vip_type']);
    if (vipType === 1) {
      return L10n.t('service_nascab_membership_vip_family', '家庭版');
    }
    if (vipType === 2) {
      return L10n.t('service_nascab_membership_vip_enterprise', '企业版');
    }
    return L10n.t('service_nascab_membership_free', '免费版');
  }

  private statusLabel(): string {
    const status = svcStr(this.membership()['status']).trim();
    if (status.length === 0) {
      return '-';
    }
    return status.toLowerCase() === 'active'
      ? L10n.t('service_nascab_membership_status_active', '生效中')
      : L10n.t('service_nascab_membership_status_inactive', '未生效');
  }

  @Builder
  InfoRow(label: string, value: string, valueColor: ResourceColor | undefined) {
    Row({ space: 8 }) {
      Text(label)
        .fontSize(12.5)
        .fontColor(this.palette().subText)
        .width(120)
      Text(value)
        .fontSize(14)
        .fontColor(valueColor !== undefined ? valueColor : this.palette().onSurface)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: 8, bottom: 8 })
  }

  @Builder
  MembershipCard() {
    GlassCard({ padValue: 16 }) {
      Column({ space: 14 }) {
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.star_fill'))
            .fontSize(20)
            .fontColor([AppTheme.withAlpha(this.palette().primary, 0.9)])
          Text(L10n.t('service_nascab_membership_title', '会员信息'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().onSurface)
          Blank()
          ServiceTextLink({
            label: L10n.t('service_nascab_membership_user_center', '个人中心'),
            onTap: (): void => {
              void this.ctrl.openUserCenterUrl();
            }
          })
          ServiceTextLink({
            label: L10n.t('refresh', '刷新'),
            onTap: (): void => {
              void this.ctrl.refreshAccount();
            }
          })
        }
        .width('100%')

        if (Object.keys(this.membership()).length === 0) {
          Text(L10n.t('service_nascab_membership_free', '免费版'))
            .fontSize(14)
            .fontColor(this.palette().subText)
            .width('100%')
          ServiceFilledButton({
            label: L10n.t('service_nascab_membership_purchase', '购买会员'),
            onTap: (): void => {
              void this.onPurchase();
            }
          })
        } else {
          Row({ space: 8 }) {
            Text(L10n.t('service_nascab_membership_vip_type', '会员类型'))
              .fontSize(12.5)
              .fontColor(this.palette().subText)
              .width(120)
            Text(this.vipTypeLabel())
              .fontSize(14)
              .fontColor(this.palette().onSurface)
              .layoutWeight(1)
            ServiceTextLink({
              label: L10n.t('service_nascab_membership_vip_diff', '版本区别'),
              onTap: (): void => {
                void this.ctrl.openVipDiffUrl();
              }
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)

          this.InfoRow(L10n.t('service_nascab_membership_max_devices', '可绑定设备数'),
            `${parseSvcInt(this.membership()['maxBindServer'] ?? this.membership()['max_bind_server'])}`,
            undefined)

          Row({ space: 8 }) {
            Text(L10n.t('service_nascab_membership_bound_devices', '已绑定设备数'))
              .fontSize(12.5)
              .fontColor(this.palette().subText)
              .width(120)
            Text(`${parseSvcInt(this.membership()['bindServerCount'] ?? this.membership()['bind_server_count'])}`)
              .fontSize(14)
              .fontColor(this.palette().onSurface)
              .layoutWeight(1)
            ServiceTextLink({
              label: L10n.t('service_nascab_membership_my_devices', '我的设备'),
              onTap: (): void => {
                void this.ctrl.openMyDevicesUrl();
              }
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)

          this.ExpiresRow()

          this.InfoRow(L10n.t('service_nascab_membership_status', '会员状态'),
            this.statusLabel(),
            svcStr(this.membership()['status']).trim().toLowerCase() !== 'active'
              ? this.palette().error : undefined)

          ServiceFilledButton({
            label: L10n.t('service_nascab_membership_renew_or_upgrade', '续费或升级会员'),
            onTap: (): void => {
              void this.onPurchase();
            }
          })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  /** 到期时间行（过期时追加红色「已过期」后缀，对齐 Flutter valueSuffix） */
  @Builder
  ExpiresRow() {
    Row({ space: 8 }) {
      Text(L10n.t('service_nascab_membership_expires_at', '到期时间'))
        .fontSize(12.5)
        .fontColor(this.palette().subText)
        .width(120)
      Text(formatMembershipTime(this.membership()['expiresAt'] ?? this.membership()['expires_at']))
        .fontSize(14)
        .fontColor(this.palette().onSurface)
      if (isMembershipExpired(this.membership()['expiresAt'] ?? this.membership()['expires_at'])) {
        Text(L10n.t('service_nascab_membership_expired', '已过期'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().error)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: 8, bottom: 8 })
  }

  /** 购买会员（对齐 Flutter onPurchase：成功打开网页后提示刷新） */
  private async onPurchase(): Promise<void> {
    const opened = await this.ctrl.openPurchaseUrl();
    if (opened) {
      ToastUtil.show(L10n.t('membership_purchase_refresh_tip', '购买完成后请点击「刷新」以更新会员信息'));
    }
  }
}
