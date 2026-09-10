import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { DialogUtil, DialogParamsBase } from '../../../common/DialogUtil';
import { UserManagementController } from '../controllers/UserManagementController';
import { UserProfile, uStr } from '../models/UserModels';

/**
 * 2FA 管理 Tab（对齐 Flutter _UserManagementTwofaTab）：
 * 启用开关 + 帮助弹窗；开启走 setup→绑定弹窗（二维码+密钥+验证码），关闭走确认→重置。
 */
@ComponentV2
export struct TwofaTab {
  @Require @Param uid: number;
  @Require @Param user: UserProfile;
  @Require @Param ctrl: UserManagementController;

  aboutToAppear(): void {
    // 未缓存时拉取状态（对齐 GetBuilder 内 lazy getTwofaStatus）
    void this.ctrl.loadTwofaStatus(this.uid);
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private status(): Record<string, Object> {
    return this.ctrl.getTwofaStatus(this.uid);
  }

  private twoFaEnabled(): boolean {
    return this.status()['enabled'] === true;
  }

  private helpText(): string {
    return L10n.t('user_mgmt_2fa_help',
      '在新设备上登录时启用TOTP双重验证(如微软/谷歌验证器),极大增强账号安全性');
  }

  private async onToggle(v: boolean): Promise<void> {
    if (v === this.twoFaEnabled()) {
      return;
    }
    if (!v) {
      const ok = await DialogUtil.showConfirmDialog(
        L10n.t('need_confirm', '需要确认'),
        L10n.t('user_mgmt_2fa_disable_confirm',
          '确定要关闭该用户的2FA吗？关闭将清除密钥并需要重新绑定。'),
        undefined, L10n.ok, L10n.cancel);
      if (ok === true) {
        await this.ctrl.resetTwofa(this.uid);
      }
      return;
    }
    const setupData = await this.ctrl.setupTwofa(this.uid, this.user.username);
    if (setupData === undefined) {
      return;
    }
    openTwofaBindDialog(this.uid, setupData);
  }

  build() {
    if (Object.keys(this.status()).length === 0) {
      // 状态未装载：居中加载（对齐 Flutter CircularProgressIndicator）
      Column() {
        LoadingProgress()
          .width(28)
          .height(28)
          .color(this.palette().primary)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      Scroll() {
        Column() {
          Row() {
            Row({ space: 6 }) {
              Text(L10n.t('user_mgmt_2fa_enabled_switch', '启用双重验证2FA'))
                .fontSize(14)
                .fontColor(this.palette().onSurface)
              SymbolGlyph($r('sys.symbol.questionmark_circle'))
                .fontSize(16)
                .fontColor([this.palette().subText])
                .onClick((): void => {
                  DialogUtil.showInfoDialog(L10n.t('tip', '提示'), this.helpText(),
                    L10n.ok);
                })
            }
            .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.twoFaEnabled() })
              .selectedColor(this.palette().primary)
              .enabled(!this.ctrl.isTwofaLoading(this.uid))
              .onChange((isOn: boolean): void => {
                void this.onToggle(isOn);
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding(12)
        .borderRadius(12)
        .backgroundColor(this.palette().cardBg)
        .border({ width: 1, color: AppTheme.withAlpha(this.palette().divider, 0.4) })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
  }
}

/** 2FA 绑定弹窗参数（对齐 Flutter _showTwofaBindDialog） */
class TwofaBindDialogParams extends DialogParamsBase {
  uid: number = 0;
  setupData: Record<string, Object> = {} as Record<string, Object>;
}

/** 打开 2FA 绑定弹窗（二维码 + 密钥 + 验证码，绑定成功返回 true） */
function openTwofaBindDialog(uid: number, setupData: Record<string, Object>): void {
  const p = new TwofaBindDialogParams();
  p.uid = uid;
  p.setupData = setupData;
  DialogUtil.openCustom(p, wrapBuilder(TwofaBindDialogContent), true,
    (_r: boolean | number | string | undefined): void => {
    });
}

@Builder
function TwofaBindDialogContent(p: TwofaBindDialogParams) {
  TwofaBindDialogInner({ p: p })
}

@ComponentV2
struct TwofaBindDialogInner {
  @Param p: TwofaBindDialogParams = new TwofaBindDialogParams();
  @Local qrPixelMap: image.PixelMap | undefined = undefined;
  @Local code: string = '';
  @Local binding: boolean = false;
  ctrl: UserManagementController = UserManagementController.getInstance();

  aboutToAppear(): void {
    void this.decodeQr();
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private secret(): string {
    return uStr(this.p.setupData['secret']);
  }

  /** 解析 qrDataUrl（data:image/png;base64,xxx）为 PixelMap */
  private async decodeQr(): Promise<void> {
    const dataUrl = uStr(this.p.setupData['qrDataUrl']);
    const idx = dataUrl.indexOf(',');
    if (idx < 0) {
      return;
    }
    const b64 = dataUrl.substring(idx + 1).trim();
    if (b64.length === 0) {
      return;
    }
    try {
      const bytes = new util.Base64Helper().decodeSync(b64);
      const source = image.createImageSource(bytes.buffer as ArrayBuffer);
      const pixelMap = await source.createPixelMap();
      this.qrPixelMap = pixelMap;
    } catch (_e) {
      // 二维码解析失败时仅展示密钥
    }
  }

  private async bind(): Promise<void> {
    const code = this.code.trim();
    if (code.length === 0) {
      DialogUtil.showErrorDialog(
        L10n.t('auth_2fa_code_required', '请输入2FA验证码'));
      return;
    }
    this.binding = true;
    try {
      const success = await this.ctrl.enableTwofa(this.p.uid, code);
      if (success) {
        this.p.onResult(true);
      }
    } finally {
      this.binding = false;
    }
  }

  build() {
    Column() {
      Text(L10n.t('user_mgmt_2fa_bind_title', '绑定2FA'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().onSurface)

      Scroll() {
        Column() {
          Text(L10n.t('user_mgmt_2fa_bind_tip',
            '请使用身份验证器(Google Authenticator,Microsoft Authenticator等)扫码后输入验证码以启用2FA'))
            .fontSize(14)
            .fontColor(this.palette().onSurface)
            .width('100%')

          if (this.qrPixelMap !== undefined) {
            Column() {
              Image(this.qrPixelMap)
                .width(220)
                .height(220)
                .objectFit(ImageFit.Contain)
                .draggable(false)
            }
            .padding(16)
            .borderRadius(15)
            .backgroundColor('#FFFFFF')
            .margin({ top: 12 })
          }

          if (this.secret().length > 0) {
            Text(`${L10n.t('user_mgmt_2fa_secret', '密钥')}: ${this.secret()}`)
              .fontSize(14)
              .fontColor(this.palette().onSurface)
              .copyOption(CopyOptions.InApp)
              .margin({ top: 12 })
              .width('100%')
          }

          TextInput({ placeholder: L10n.t('user_mgmt_2fa_code_hint', '请输入6位验证码') })
            .fontSize(14)
            .fontColor(this.palette().onSurface)
            .placeholderColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.5))
            .backgroundColor(this.palette().inputFill)
            .borderRadius(8)
            .border({ width: 1, color: this.palette().inputBorder })
            .height(42)
            .margin({ top: 12 })
            .width('100%')
            .onChange((v: string): void => {
              this.code = v;
            })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
      .constraintSize({ maxHeight: 420 })
      .margin({ top: 12 })
      .width('100%')

      Row({ space: 8 }) {
        Button(L10n.cancel)
          .fontSize(14)
          .fontColor(this.palette().primary)
          .backgroundColor(Color.Transparent)
          .height(36)
          .onClick(() => {
            this.p.onResult(undefined);
          })
        Button(L10n.t('user_mgmt_2fa_bind_action', '绑定/启用'))
          .fontSize(14)
          .fontColor(this.palette().buttonText)
          .backgroundColor(this.palette().buttonBg)
          .height(36)
          .opacity(this.binding ? 0.5 : 1)
          .onClick(() => {
            void this.bind();
          })
      }
      .justifyContent(FlexAlign.End)
      .margin({ top: 16 })
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(20)
    .backgroundColor(this.palette().surfaceBg)
    .borderRadius(24)
    .width('84%')
    .constraintSize({ maxWidth: 420 })
  }
}
