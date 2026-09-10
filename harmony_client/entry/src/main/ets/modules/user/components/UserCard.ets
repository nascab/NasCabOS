import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { UserManagementController } from '../controllers/UserManagementController';
import { UserProfile } from '../models/UserModels';

/**
 * 用户卡片（对齐 Flutter CustomUserCard 移动端形态）：
 * 圆形头像 + 用户类型徽标 + 用户名 + 电话/备注（有值才显示），点击进入详情。
 */
@ComponentV2
export struct UserCard {
  @Require @Param user: UserProfile;
  @Param onTap: () => void = (): void => {
  };
  /** 类型徽标回调所需（动态 key），由组件内部直接翻译 */
  ctrl: UserManagementController = UserManagementController.getInstance();

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  @Builder
  TypeBadge() {
    Text(this.ctrl.userTypeLabel(this.user.type))
      .fontSize(11)
      .fontColor(this.palette().buttonText)
      .padding({ left: 4, right: 4, top: 2, bottom: 3 })
      .borderRadius(8)
      .backgroundColor(this.user.type === 'super_admin'
        ? this.palette().primary
        : AppTheme.withAlpha(this.palette().onSurface, 0.5))
  }

  build() {
    Row({ space: 12 }) {
      // 圆形头像（对齐 CircleAvatar person）
      Column() {
        SymbolGlyph($r('sys.symbol.person_fill'))
          .fontSize(22)
          .fontColor([this.palette().surfaceBg])
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .width(44)
      .height(44)
      .borderRadius(22)
      .backgroundColor(AppTheme.withAlpha(this.palette().onSurface, 0.6))

      Column() {
        // 行 1：用户类型徽标（对齐 Flutter 顶部类型容器）
        Row() {
          this.TypeBadge()
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)

        // 行 2：用户名
        Text(this.user.username)
          .fontSize(14)
          .fontColor(this.palette().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 6 })
          .width('100%')

        // 行 3：电话（有值才显示）
        if (this.user.phone.trim().length > 0) {
          Text(`${L10n.t('user_mgmt_phone', '电话')}: ${this.user.phone}`)
            .fontSize(12)
            .fontColor(AppTheme.withAlpha(this.palette().onSurface, 0.65))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
            .width('100%')
        }

        // 行 4：备注（有值才显示）
        if (this.user.userRemark.trim().length > 0) {
          Text(`${L10n.t('user_mgmt_remark', '备注')}: ${this.user.userRemark}`)
            .fontSize(12)
            .fontColor(AppTheme.withAlpha(this.palette().onSurface, 0.65))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding(12)
    .borderRadius(12)
    .backgroundColor(this.palette().cardBg)
    .border({ width: 1, color: AppTheme.withAlpha(this.palette().divider, 0.4) })
    .onClick((): void => {
      this.onTap();
    })
  }
}
