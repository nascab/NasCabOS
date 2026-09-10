import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';

/**
 * 服务模块共享小部件：
 * - ServiceTextLink：文本按钮（对齐 Flutter TextButton）
 * - ServiceTonalButton：浅底小按钮（对齐 Flutter FilledButton.tonal）
 * - ServiceFilledButton：主色实心按钮（对齐 Flutter CustomButton icon+text 形态）
 * - ServiceNotLoggedInCard：未登录提示卡（对齐 Flutter 远程访问/DDNS 页的未登录卡）
 * - ServiceLoadingOverlay：页面级半透明加载遮罩（对齐 Flutter Positioned.fill + CircularProgressIndicator）
 */

@ComponentV2
export struct ServiceTextLink {
  @Param label: string = '';
  @Param onTap: () => void = (): void => {
  };

  build() {
    Text(this.label)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor(AppTheme.current().primary)
      .padding({ left: 6, right: 6, top: 4, bottom: 4 })
      .onClick((): void => {
        this.onTap();
      })
  }
}

@ComponentV2
export struct ServiceTonalButton {
  @Param label: string = '';
  @Param onTap: () => void = (): void => {
  };

  build() {
    Text(this.label)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor(AppTheme.current().primary)
      .padding({ left: 16, right: 16, top: 9, bottom: 9 })
      .borderRadius(20)
      .backgroundColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.08))
      .onClick((): void => {
        this.onTap();
      })
  }
}

@ComponentV2
export struct ServiceFilledButton {
  @Param icon: Resource | undefined = undefined;
  @Param label: string = '';
  /** 置可用（命名避开系统通用属性 enabled，防遮蔽） */
  @Param isEnabled: boolean = true;
  @Param onTap: () => void = (): void => {
  };

  build() {
    Row({ space: 6 }) {
      if (this.icon !== undefined) {
        SymbolGlyph(this.icon)
          .fontSize(16)
          .fontColor([AppTheme.current().buttonText])
      }
      Text(this.label)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.current().buttonText)
        .maxLines(1)
    }
    .justifyContent(FlexAlign.Center)
    .constraintSize({ minWidth: 120 })
    .height(40)
    .padding({ left: 18, right: 18 })
    .borderRadius(20)
    .backgroundColor(AppTheme.current().buttonBg)
    .opacity(this.isEnabled ? 1 : 0.4)
    .enabled(this.isEnabled)
    .onClick((): void => {
      if (this.isEnabled) {
        this.onTap();
      }
    })
  }
}

@ComponentV2
export struct ServiceNotLoggedInCard {
  @Param isNarrow: boolean = true;
  @Param onGotoAccount: () => void = (): void => {
  };
  @Param title: string = L10n.t('service_nascab_not_logged_in', '未登录');
  @Param hint: string = L10n.t('service_nascab_not_logged_in_hint', '登录后可使用 NasCab 远程服务能力');
  /** 窄屏按钮文案（远程访问/DDNS 均为「去登录 NasCab 账号」页签切换） */
  @Param actionLabel: string = L10n.t('service_menu_account_nascab', 'NasCab账号');

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.info_circle'))
          .fontSize(20)
          .fontColor([this.palette().onSurface])
          .margin({ top: 1 })
        if (this.isNarrow) {
          Column({ space: 6 }) {
            Text(this.title)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().onSurface)
            Text(this.hint)
              .fontSize(12.5)
              .fontColor(this.palette().subText)
              .lineHeight(18)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        } else {
          Text(this.title)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().onSurface)
            .layoutWeight(1)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      if (this.isNarrow) {
        Row() {
          Blank()
          ServiceTonalButton({
            label: this.actionLabel,
            onTap: (): void => {
              this.onGotoAccount();
            }
          })
        }
        .width('100%')
        .margin({ top: 10 })
      } else {
        Row({ space: 10 }) {
          Blank()
          ServiceTextLink({
            label: this.actionLabel,
            onTap: (): void => {
              this.onGotoAccount();
            }
          })
        }
        .width('100%')
      }
    }
  }
}

@ComponentV2
export struct ServiceLoadingOverlay {
  build() {
    Stack() {
      LoadingProgress()
        .width(28)
        .height(28)
        .color(AppTheme.current().primary)
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
    .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.2))
    // 对齐 Flutter IgnorePointer：不拦截下层交互
    .hitTestBehavior(HitTestMode.None)
  }
}
