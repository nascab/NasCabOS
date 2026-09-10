import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { PageScaffold } from '../../../common/PageScaffold';
import { DialogUtil } from '../../../common/DialogUtil';
import { GlassCard } from '../../../common/components/GlassCard';
import { ShareServerController } from '../controllers/ShareServerController';
import { SharePortsPageParam } from '../router/ShareServerRoutes';
import { PortsSaveErrorInfo } from '../models/ShareServerModels';

/**
 * 端口设置页（对齐 Flutter _PortsSettingsView；Flutter 移动端为独立页 _FileSharePortsSettingsPage）：
 * WebDav（HTTP/HTTPS 双端口）/ FTP / SFTP（单端口）三卡片，逐类型保存；
 * 校验失败与服务端结构化错误（fields/suggestedRange）提示对齐 Flutter。
 */
@ComponentV2
export struct SharePortsSettingsPage {
  @Param param: SharePortsPageParam = new SharePortsPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local ctrl: ShareServerController = ShareServerController.getInstance();
  // 各类型状态（不可变更新，保证 V2 重渲染）
  @Local httpText: Map<string, string> = new Map();
  @Local httpsText: Map<string, string> = new Map();
  @Local httpError: Map<string, string> = new Map();
  @Local httpsError: Map<string, string> = new Map();
  @Local saving: Map<string, boolean> = new Map();

  aboutToAppear(): void {
    this.syncFromCtrl();
    // 控制器为全局单例：打开时补一次静默刷新并回填（对齐 Flutter portsByType 响应式同步）
    void this.refreshThenSync();
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private types(): string[] {
    return ShareServerController.SUPPORTED_TYPES;
  }

  private typeName(t: string): string {
    if (t === 'FTP') {
      return L10n.t('file_share_server_ftp', 'FTP');
    }
    if (t === 'SFTP') {
      return L10n.t('file_share_server_sftp', 'SFTP');
    }
    return L10n.t('file_share_server_webdav', 'WebDAV');
  }

  // ===== 状态读写（Map 不可变更新） =====

  private mapGet(m: Map<string, string>, k: string): string {
    const v = m.get(k);
    return v === undefined ? '' : v;
  }

  private mapSet(m: Map<string, string>, k: string, v: string): Map<string, string> {
    const next = new Map<string, string>(m);
    next.set(k, v);
    return next;
  }

  private mapRemove(m: Map<string, string>, k: string): Map<string, string> {
    const next = new Map<string, string>(m);
    next.delete(k);
    return next;
  }

  private isSaving(t: string): boolean {
    return this.saving.get(t) === true;
  }

  private setSaving(t: string, v: boolean): void {
    const next = new Map<string, boolean>(this.saving);
    next.set(t, v);
    this.saving = next;
  }

  private syncFromCtrl(): void {
    for (const t of this.types()) {
      const ports = this.ctrl.portsByType.get(t);
      const httpPort = ports !== undefined ? ports.httpPort : '';
      const httpsPort = t === 'WebDav' && ports !== undefined ? ports.httpsPort : '';
      this.httpText = this.mapSet(this.httpText, t, httpPort);
      this.httpsText = this.mapSet(this.httpsText, t, httpsPort);
    }
  }

  private async refreshThenSync(): Promise<void> {
    for (const t of this.types()) {
      await this.ctrl.refreshType(t, false);
    }
    this.syncFromCtrl();
  }

  // ===== 校验与保存（对齐 _saveType） =====

  /** 解析端口输入：空 → 不设置；非法 → invalid（ArkTS 不支持对象字面量类型，用类承载） */
  private parsePort(text: string): PortParseResult {
    const v = text.trim();
    if (v.length === 0) {
      return new PortParseResult(undefined, false);
    }
    if (!/^\d+$/.test(v)) {
      return new PortParseResult(undefined, true);
    }
    const n = parseInt(v);
    if (n < 1 || n > 65535) {
      return new PortParseResult(undefined, true);
    }
    return new PortParseResult(n, false);
  }

  private portInvalidMessage(): string {
    return L10n.t('file_share_server_port_invalid', '端口不合法');
  }

  private async saveType(t: string): Promise<void> {
    if (this.isSaving(t)) {
      return;
    }
    const httpText = this.mapGet(this.httpText, t);
    const httpsText = this.mapGet(this.httpsText, t);
    const httpRes = this.parsePort(httpText);
    const httpsRes = this.parsePort(httpsText);
    const isWebDav = t === 'WebDav';

    // 非法输入（对齐 Flutter _parsePort 失败分支）
    if ((httpText.trim().length > 0 && httpRes.invalid)
      || (isWebDav && httpsText.trim().length > 0 && httpsRes.invalid)) {
      this.httpError = httpText.trim().length > 0 && httpRes.invalid
        ? this.mapSet(this.httpError, t, this.portInvalidMessage())
        : this.mapRemove(this.httpError, t);
      this.httpsError = isWebDav && httpsText.trim().length > 0 && httpsRes.invalid
        ? this.mapSet(this.httpsError, t, this.portInvalidMessage())
        : this.mapRemove(this.httpsError, t);
      DialogUtil.showErrorDialog(this.portInvalidMessage(),
        L10n.t('file_share_server_ports_save_failed_title', '端口设置失败'));
      return;
    }
    // WebDav 双端口相等校验
    if (isWebDav && httpRes.value !== undefined && httpsRes.value !== undefined
      && httpRes.value === httpsRes.value) {
      const msg = this.portInvalidMessage();
      this.httpError = this.mapSet(this.httpError, t, msg);
      this.httpsError = this.mapSet(this.httpsError, t, msg);
      DialogUtil.showErrorDialog(msg,
        L10n.t('file_share_server_ports_save_failed_title', '端口设置失败'));
      return;
    }

    this.setSaving(t, true);
    this.httpError = this.mapRemove(this.httpError, t);
    this.httpsError = this.mapRemove(this.httpsError, t);
    try {
      const info: PortsSaveErrorInfo | undefined = await this.ctrl.setPorts(t, httpRes.value,
        isWebDav ? httpsRes.value : undefined);
      if (info === undefined) {
        return;
      }
      // 服务端结构化错误：按 fields 定位到具体端口输入框
      if (info.hitHttp) {
        this.httpError = this.mapSet(this.httpError, t, info.message);
      }
      if (isWebDav && info.hitHttps) {
        this.httpsError = this.mapSet(this.httpsError, t, info.message);
      }
      const rangeParams = L10n.paramsOf('min', info.minPort);
      rangeParams.set('max', info.maxPort);
      const reasonText =
        `${L10n.t('file_share_server_ports_save_failed_reason_label', '原因：')}${PortsSaveErrorInfoMessage(info)}`;
      const solutionText = info.minPort.length > 0 && info.maxPort.length > 0
        ? `${L10n.t('file_share_server_ports_save_failed_solution_label', '建议：')}${L10n.t('file_share_server_ports_save_failed_solution_range', '请选择 @min-@max 范围内的可用端口', rangeParams)}`
        : `${L10n.t('file_share_server_ports_save_failed_solution_label', '建议：')}${L10n.t('file_share_server_ports_save_failed_solution_default', '请更换为可用端口后重试')}`;
      DialogUtil.showErrorDialog(`${reasonText}\n\n${solutionText}`,
        L10n.t('file_share_server_ports_save_failed_title', '端口设置失败'));
    } finally {
      this.setSaving(t, false);
    }
  }

  build() {
    PageScaffold({
      title: this.param.title.trim().length > 0
        ? this.param.title : L10n.t('file_share_server_ports_settings', '端口设置'),
      onBack: (): void => {
        this.popPage();
      },
      content: (): void => {
        this.Content()
      }
    })
  }

  @Builder
  Content() {
    Scroll() {
      Column() {
        ForEach(this.types(), (t: string) => {
          this.TypeCard(t)
        }, (t: string) => t)
      }
      .width('100%')
      .padding(12)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .align(Alignment.Top)
    .opacity(this.ctrl.portsByType.size >= 0 ? 1 : 1)
  }

  /** 类型卡片（标题 + 保存按钮 + 端口输入） */
  @Builder
  TypeCard(t: string) {
    Column() {
      GlassCard({
        padValue: 12
      }) {
        Column() {
          Row() {
            Text(this.typeName(t))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().onSurface)
              .layoutWeight(1)
            this.SaveButton(t)
          }
          .width('100%')

          if (t === 'WebDav') {
            this.PortField(t, true,
              L10n.t('file_share_server_port_http', 'HTTP 端口'), true)
            this.PortField(t, false,
              L10n.t('file_share_server_port_https', 'HTTPS 端口'), true)
          } else {
            this.PortField(t, true, L10n.t('file_share_server_port', '端口'), false)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .margin({ bottom: 12 })
  }

  /** 保存按钮（保存中转圈禁用，对齐 Flutter CustomButton isDisabled） */
  @Builder
  SaveButton(t: string) {
    Row({ space: 6 }) {
      if (this.isSaving(t)) {
        LoadingProgress()
          .width(15)
          .height(15)
          .color(this.palette().primary)
      } else {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(15)
          .fontColor([this.palette().primary])
      }
      Text(L10n.save)
        .fontSize(13)
        .fontColor(this.palette().primary)
        .maxLines(1)
    }
    .padding({ left: 10, right: 10, top: 7, bottom: 7 })
    .borderRadius(10)
    .border({ width: 1, color: this.palette().divider })
    .opacity(this.isSaving(t) ? 0.6 : 1)
    .onClick(() => {
      void this.saveType(t);
    })
  }

  /**
   * 端口输入框（对齐 CustomTextField labelText/errorText + error 图标）。
   * isHttp=true 取 http 输入/错误；showError 控制 HTTPS 字段仅 WebDav 展示错误。
   */
  @Builder
  PortField(t: string, isHttp: boolean, label: string, hasErrorSlot: boolean) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(12)
        .fontColor(this.palette().subText)
      TextInput({ text: isHttp ? this.mapGet(this.httpText, t) : this.mapGet(this.httpsText, t) })
        .type(InputType.Number)
        .fontSize(14)
        .fontColor(this.palette().onSurface)
        .backgroundColor(this.palette().inputFill)
        .borderRadius(8)
        .border({
          width: 1,
          color: this.errorTextOf(t, isHttp).length > 0
            ? this.palette().error : this.palette().inputBorder
        })
        .height(42)
        .width('100%')
        .onChange((v: string) => {
          if (isHttp) {
            this.httpText = this.mapSet(this.httpText, t, v);
            if (this.errorTextOf(t, true).length > 0) {
              this.httpError = this.mapRemove(this.httpError, t);
            }
          } else {
            this.httpsText = this.mapSet(this.httpsText, t, v);
            if (this.errorTextOf(t, false).length > 0) {
              this.httpsError = this.mapRemove(this.httpsError, t);
            }
          }
        })
      if (hasErrorSlot && this.errorTextOf(t, isHttp).length > 0) {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(14)
            .fontColor([this.palette().error])
          Text(this.errorTextOf(t, isHttp))
            .fontSize(12)
            .fontColor(this.palette().error)
            .layoutWeight(1)
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 12 })
  }

  private errorTextOf(t: string, isHttp: boolean): string {
    const v = isHttp ? this.httpError.get(t) : this.httpsError.get(t);
    return v === undefined ? '' : v;
  }
}

/** 端口输入解析结果（value=undefined 表示空输入不设置；invalid=true 表示非法） */
class PortParseResult {
  value: number | undefined = undefined;
  invalid: boolean = false;

  constructor(value: number | undefined, invalid: boolean) {
    this.value = value;
    this.invalid = invalid;
  }
}

/** 兜底：错误信息为空时展示通用失败文案 */
function PortsSaveErrorInfoMessage(info: PortsSaveErrorInfo): string {
  return info.message.length > 0 ? info.message : L10n.operationFailed;
}
