import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { GlassCard } from '../../../common/components/GlassCard';
import { SecurityCenterController } from '../controllers/SecurityCenterController';

/**
 * 安全设置面板（对齐 Flutter SecuritySettingsPanel appMode: true 移动端形态）：
 * IP 封禁规则卡片：启用开关 + 错误次数/封禁分钟输入 + 保存按钮 + 局域网免验证开关。
 * 开关变更经控制器 450ms 防抖自动保存；输入通过保存按钮手动提交（与 Flutter 一致）。
 */
@ComponentV2
export struct SecuritySettingsPanel {
  @Require @Param ctrl: SecurityCenterController;

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    Scroll() {
      Column() {
        GlassCard({ padValue: 16 }) {
          Column({ space: 12 }) {
            Text(L10n.t('security.ip_ban_rules', 'IP封禁规则'))
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().onSurface)
              .width('100%')

            SecuritySwitchRow({
              title: L10n.t('security.enable_ip_ban', '启用IP封禁'),
              isOn: this.ctrl.banEnabled,
              onChange: (v: boolean): void => {
                this.ctrl.setBanEnabled(v);
              }
            })

            Row({ space: 12 }) {
              SecurityNumberField({
                label: L10n.t('security.failed_attempts', '密码错误次数'),
                text: this.ctrl.maxFailedAttemptsText,
                onChange: (v: string): void => {
                  this.ctrl.onMaxFailedAttemptsInput(v);
                }
              })
              SecurityNumberField({
                label: L10n.t('security.ban_minutes', '封禁分钟数'),
                text: this.ctrl.banMinutesText,
                onChange: (v: string): void => {
                  this.ctrl.onBanMinutesInput(v);
                }
              })
              Button(L10n.t('save', '保存'), { type: ButtonType.Capsule })
                .height(44)
                .fontSize(14)
                .backgroundColor(this.palette().buttonBg)
                .fontColor(this.palette().buttonText)
                .onClick((): void => {
                  void this.ctrl.saveConfig();
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Bottom)

            SecuritySwitchRow({
              title: L10n.t('security.bypass_lan_auth', '局域网环境不验证'),
              isOn: this.ctrl.bypassLanAuth,
              onChange: (v: boolean): void => {
                this.ctrl.setBypassLanAuth(v);
              }
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      }
      .width('100%')
      // 对齐 Flutter appMode padding: fromLTRB(18, 10, 18, 16)
      .padding({ left: 18, right: 18, top: 10, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }
}

/** 开关行（对齐 SwitchListTile：左标题 + 右开关；独立组件保证配置回填后开关状态同步） */
@ComponentV2
struct SecuritySwitchRow {
  @Param title: string = '';
  @Param isOn: boolean = false;
  @Param onChange: (v: boolean) => void = (_v: boolean): void => {
  };

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    Row() {
      Text(this.title)
        .fontSize(14)
        .fontColor(this.palette().onSurface)
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor(this.palette().primary)
        .onChange((v: boolean): void => {
          this.onChange(v);
        })
    }
    .width('100%')
  }
}

/**
 * 数字输入小字段（对齐 Flutter CustomTextField keyboardType: number）。
 * 独立组件承载 @Param text：配置回填（loadConfig 网络刷新）后输入框内容可同步更新。
 */
@ComponentV2
struct SecurityNumberField {
  @Param label: string = '';
  @Param text: string = '';
  @Param onChange: (v: string) => void = (_v: string): void => {
  };

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    Column() {
      Text(this.label)
        .fontSize(12)
        .fontColor(this.palette().subText)
        .width('100%')
      TextInput({ text: this.text })
        .type(InputType.Number)
        .fontSize(14)
        .fontColor(this.palette().onSurface)
        .placeholderColor(this.palette().hint)
        .backgroundColor(this.palette().inputFill)
        .borderRadius(8)
        .border({ width: 1, color: this.palette().inputBorder })
        .height(42)
        .width('100%')
        .margin({ top: 6 })
        .onChange((v: string): void => {
          this.onChange(v);
        })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }
}
