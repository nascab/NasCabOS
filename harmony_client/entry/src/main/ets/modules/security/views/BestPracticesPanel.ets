import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { ToastUtil } from '../../../common/ToastUtil';
import { GlassCard } from '../../../common/components/GlassCard';
import { SecurityCenterController } from '../controllers/SecurityCenterController';

/**
 * 最佳实践面板（对齐 Flutter BestPracticesPanel）：
 * 标题 + 建议说明卡（3 条编号建议）；第 2 条尾随「去开启」入口。
 * Flutter 端该入口跳转用户管理应用（PcHomeController.openApp('user')），
 * 鸿蒙端用户管理模块尚未迁移，暂以 Toast 提示兜底，待 user 模块上线后改为 NavUtil.push。
 */
@ComponentV2
export struct BestPracticesPanel {
  @Require @Param ctrl: SecurityCenterController;

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    Scroll() {
      Column() {
        Text(L10n.t('security.best_practices', '最佳实践'))
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().onSurface)
          .width('100%')

        // 自定义组件不支持直接链式属性，外层 Column 承载与标题的 12 间距
        Column() {
          GlassCard({ padValue: 20 }) {
            Column() {
              Text(L10n.t('security.best_practices_desc', '为了安全使用本系统，建议安全设置如下：'))
                .fontSize(14)
                .fontColor(this.palette().subText)
                .width('100%')

              Column({ space: 16 }) {
                this.BestItem('1', L10n.t('security.best_practices_item1', '不使用简单密码，如111222等简单重复的字符'))
                Column({ space: 8 }) {
                  this.BestItem('2', L10n.t('security.best_practices_item2', '开启2FA双重验证'))
                  this.GoToUserLink()
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                this.BestItem('3', L10n.t('security.best_practices_item3',
                  '尽量不要公开自己的远程访问匹配码（匹配码只是P2P的通道标识，即使别人知道了你的匹配码，仍然需要用户名/密码/2FA等信息才能登录你的系统）'))
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .margin({ top: 20 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }
        .width('100%')
        .margin({ top: 12 })
      }
      .width('100%')
      // 对齐 Flutter Padding(all: 12)
      .padding(12)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  /** 编号建议项（对齐 _buildItem：主色圆形编号 + 文本） */
  @Builder
  BestItem(number: string, text: string) {
    Row({ space: 12 }) {
      Text(number)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().primary)
        .width(24)
        .height(24)
        .textAlign(TextAlign.Center)
        .borderRadius(12)
        .backgroundColor(AppTheme.withAlpha(this.palette().primary, 0.1))
      Text(text)
        .fontSize(14)
        .fontColor(this.palette().onSurface)
        .lineHeight(20)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  /** 「去开启」链接（对齐 _buildGoToUserButton 的 RichText 可点击文案） */
  @Builder
  GoToUserLink() {
    Text(L10n.t('security.go_to_user', '去开启'))
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.palette().primary)
      .onClick((): void => {
        // 鸿蒙端用户管理模块尚未迁移：以提示兜底（对齐 Flutter 跳转 user 应用的入口语义）
        ToastUtil.show(L10n.t('security.user_app_not_available', '请在服务器端用户管理中开启2FA'));
      })
  }
}
