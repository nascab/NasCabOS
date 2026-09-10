import { common } from '@kit.AbilityKit';
import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { AppEventBus } from '../../../common/AppEventBus';
import { LanguageService } from '../../../core/localization/LanguageService';
import { PageScaffold } from '../../../common/PageScaffold';
import { ToastUtil } from '../../../common/ToastUtil';
import { CircleCheckbox } from '../../../common/components/CircleCheckbox';
import { PickOption, showOptionPickSheet } from '../../../common/components/OptionPickSheet';
import { pickTargetFolderViaSheet } from '../../../files/views/FolderPickerSheet';
import { OpenlistMountController } from '../controllers/FileMountControllers';
import { OpenlistDriverI18n } from '../services/OpenlistDriverI18n';
import { OpenlistMountEditPageParam } from '../router/FileMountRoutes';
import { DriverField, MountItem, parseDriverFields, recRecord } from '../models/FileMountModels';
import { OpenlistDriverInfo } from '../services/FileMountApiServices';

/** 驱动字段排除项（OAuth 相关字段不展示，对齐 Flutter _applyDriverFields 过滤） */
const EXCLUDED_FIELDS: string[] =
  ['client_id', 'client_secret', 'redirect_uri', 'use_online_api', 'api_url_address'];

/** 打开系统浏览器访问外部链接（对齐 Flutter launchUrl externalApplication） */
function openExternalUrl(context: Context, url: string): void {
  try {
    (context as common.UIAbilityContext).openLink(url);
  } catch (_e) {
    // 打开失败时静默处理
  }
}

/** 驱动字段输入项（字段定义 + 输入状态，@ObservedV2 使输入值可观察） */
@ObservedV2
class DriverFieldInput {
  readonly field: DriverField;
  @Trace text: string = '';
  @Trace checked: boolean = false;

  constructor(field: DriverField) {
    this.field = field;
    this.text = field.defaultValue;
    this.checked = field.defaultBool;
  }

  get label(): string {
    return OpenlistDriverI18n.fieldLabel(this.field);
  }

  /** help 与显示名相同时不作为提示（对齐 Flutter hint != label 判断） */
  get hint(): string {
    const h = this.field.help.trim();
    return h.length > 0 && h !== this.label ? h : '';
  }
}

/**
 * 网盘挂载 新增/编辑页（对齐 Flutter _OpenlistMountDialog，对话框转为移动端编辑页，功能不变）。
 * 驱动列表懒加载；字段按所选驱动 additional 动态渲染（bool/select/text，secret 掩码）。
 */
@ComponentV2
export struct OpenlistMountEditPage {
  @Param param: OpenlistMountEditPageParam = new OpenlistMountEditPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local ctrl: OpenlistMountController = OpenlistMountController.getInstance();
  @Local nameText: string = '';
  @Local mountPath: string = '';
  @Local driver: string = '';
  @Local inputs: DriverFieldInput[] = [];
  @Local saving: boolean = false;
  /** 依赖 localeBump：切换语言后刷新驱动显示名（中英映射不走语言包） */
  @Local localeBump: number = 0;
  private localeListener: (data: string) => void = (_data: string): void => {
    this.localeBump++;
  };

  private get isEdit(): boolean {
    return this.param.initial !== undefined;
  }

  private get isRunning(): boolean {
    return this.param.initial !== undefined && this.param.initial.isRunning;
  }

  aboutToAppear(): void {
    AppEventBus.on(LanguageService.EVENT_LOCALE_CHANGED, this.localeListener);
    const init: MountItem | undefined = this.param.initial;
    this.nameText = init !== undefined ? init.name : '';
    this.mountPath = init !== undefined ? init.mountPath : '';
    this.driver = init !== undefined ? init.driver : '';
    void this.initDrivers(init);
  }

  aboutToDisappear(): void {
    AppEventBus.off(LanguageService.EVENT_LOCALE_CHANGED, this.localeListener);
  }

  /** 加载驱动并初始化字段（对齐 Flutter initState 中 loadDrivers().then 逻辑） */
  private async initDrivers(init: MountItem | undefined): Promise<void> {
    await this.ctrl.loadDrivers();
    if (this.driver.length === 0 && this.ctrl.drivers.length > 0) {
      this.driver = this.ctrl.drivers[0].name;
      this.applyDriverFields(this.driver);
    } else if (this.driver.length > 0) {
      this.applyDriverFields(this.driver);
    }
    this.loadInitialAddition(init);
  }

  /** 解析所选驱动 additional 并重建输入项（对齐 Flutter _applyDriverFields） */
  private applyDriverFields(driverName: string): void {
    const list: DriverFieldInput[] = [];
    parseDriverFields(this.ctrl.driverAdditional(driverName)).forEach((f: DriverField): void => {
      if (EXCLUDED_FIELDS.indexOf(f.name) >= 0) {
        return;
      }
      list.push(new DriverFieldInput(f));
    });
    this.inputs = list;
  }

  /** 编辑回填 addition（对齐 Flutter _loadInitialAddition） */
  private loadInitialAddition(init: MountItem | undefined): void {
    if (init === undefined) {
      return;
    }
    const addition = recRecord(init.config, 'addition');
    Object.keys(addition).forEach((key: string): void => {
      const input = this.findInput(key);
      if (input === undefined) {
        return;
      }
      const val = addition[key];
      if (input.field.isBool) {
        input.checked = val === true;
      } else {
        input.text = val === undefined || val === null ? '' : `${val}`;
      }
    });
  }

  private findInput(name: string): DriverFieldInput | undefined {
    return this.inputs.find((i: DriverFieldInput): boolean => i.field.name === name);
  }

  private get usesOnlineAuth(): boolean {
    return OpenlistDriverI18n.usesOnlineAuth(this.driver);
  }

  /** 驱动文档地址：API 覆盖优先，其次内置目录（对齐 Flutter _driverDocUrlFor） */
  private driverDocUrl(): string {
    if (this.driver.length === 0) {
      return '';
    }
    const fromApi = this.ctrl.driverDocUrlFromApi(this.driver);
    if (fromApi.length > 0) {
      return fromApi;
    }
    return OpenlistDriverI18n.driverDocUrl(this.driver);
  }

  private driverDisplayName(): string {
    return this.driver.length > 0 ? OpenlistDriverI18n.driverName(this.driver) : '';
  }

  private pickDriver(): void {
    if (this.isRunning || this.ctrl.isDriversLoading) {
      return;
    }
    const seen: string[] = [];
    this.ctrl.drivers.forEach((d: OpenlistDriverInfo): void => {
      if (d.name.length > 0 && seen.indexOf(d.name) < 0) {
        seen.push(d.name);
      }
    });
    if (seen.length === 0) {
      return;
    }
    const options: PickOption[] = [];
    seen.forEach((n: string): void => {
      options.push(new PickOption(n, OpenlistDriverI18n.driverName(n)));
    });
    showOptionPickSheet(L10n.t('openlist_mount_driver', '网盘类型'), options, this.driver,
      (key: string): void => {
        this.driver = key;
        this.applyDriverFields(key);
      });
  }

  private pickMountPath(): void {
    pickTargetFolderViaSheet(this.mountPath.trim(), (paths: string[]): void => {
      if (paths.length === 0) {
        return;
      }
      this.mountPath = paths[0];
    });
  }

  private openOAuthHelp(): void {
    if (this.driver.length === 0) {
      return;
    }
    openExternalUrl(getContext(this), OpenlistDriverI18n.oauthUrlForDriver(this.driver));
  }

  private openDriverDoc(): void {
    const url = this.driverDocUrl();
    if (url.length === 0) {
      return;
    }
    openExternalUrl(getContext(this), url);
  }

  /** 组装 addition（对齐 Flutter _collectAddition：文本非空才收集，bool 恒收集） */
  private collectAddition(): Record<string, Object> {
    const out: Record<string, Object> = {};
    this.inputs.forEach((input: DriverFieldInput): void => {
      if (input.field.isBool) {
        out[input.field.name] = input.checked;
        return;
      }
      const v = input.text.trim();
      if (v.length > 0) {
        out[input.field.name] = v;
      }
    });
    return out;
  }

  /** 必填校验（对齐 Flutter _validateDriverFields：required / help 含 one of + required） */
  private validateDriverFields(): boolean {
    const params = new Map<string, string>();
    for (const input of this.inputs) {
      const f = input.field;
      if (f.isBool || (!f.required && !f.oneOfRequired)) {
        continue;
      }
      if (input.text.trim().length > 0) {
        continue;
      }
      params.set('field', OpenlistDriverI18n.fieldLabel(f));
      ToastUtil.show(L10n.t('openlist_mount_field_required', '必填：@field', params));
      return false;
    }
    return true;
  }

  private async submit(): Promise<void> {
    if (this.saving || this.isRunning) {
      return;
    }
    const name = this.nameText.trim();
    const mountPath = this.mountPath.trim();
    const driver = this.driver.trim();
    if (name.length === 0 || mountPath.length === 0 || driver.length === 0) {
      ToastUtil.show(L10n.t('openlist_mount_required', '名称、父路径、网盘类型必填'));
      return;
    }
    if (!this.validateDriverFields()) {
      return;
    }
    const init: MountItem | undefined = this.param.initial;
    const id = init !== undefined && init.id > 0 ? init.id : undefined;
    this.saving = true;
    const ok = await this.ctrl.upsert(id, name, mountPath, driver, this.collectAddition());
    this.saving = false;
    if (ok) {
      this.popPage();
    }
  }

  build() {
    PageScaffold({
      title: this.isEdit
        ? L10n.t('openlist_mount_edit', '编辑网盘挂载')
        : L10n.t('openlist_mount_create', '添加网盘挂载'),
      showBack: true,
      statusBarBg: AppTheme.current().pageBg,
      onBack: (): void => {
        this.popPage();
      },
      content: (): void => {
        this.FormBody()
      }
    })
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  @Builder
  FormBody() {
    Column() {
      Scroll() {
        Column({ space: 14 }) {
          this.NameField()
          this.MountPathField()
          this.DriverField()
          if (this.driver.length > 0 && this.usesOnlineAuth) {
            Text(L10n.t('openlist_mount_oauth_hint',
              '打开 OpenList 授权页获取 Refresh Token，Client ID / Client Secret 无需填写。'))
              .fontSize(12)
              .fontColor(this.palette().primary)
              .width('100%')
          }
          if (this.driver.length > 0 && this.driverDocUrl().length > 0) {
            Text(L10n.t('openlist_mount_driver_doc_hint',
              '字段说明与配置示例见 OpenList 驱动文档。'))
              .fontSize(12)
              .fontColor(this.palette().subText)
              .width('100%')
          }
          if (this.usesOnlineAuth) {
            this.LinkButton(L10n.t('openlist_mount_oauth_help', '获取 Token（OpenList 授权页）'),
              $r('sys.symbol.arrow_up_right'), this.driver.length > 0, (): void => {
                this.openOAuthHelp();
              })
          }
          if (this.driverDocUrl().length > 0) {
            this.LinkButton(L10n.t('openlist_mount_driver_doc_help', '配置指南'),
              $r('sys.symbol.book'), this.driver.length > 0, (): void => {
                this.openDriverDoc();
              })
          }
          if (this.inputs.length > 0) {
            Text(L10n.t('openlist_mount_driver_config', '驱动配置'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().onSurface)
              .width('100%')
            ForEach(this.inputs, (input: DriverFieldInput, index: number): void => {
              if (input.field.isBool) {
                this.BoolFieldRow(input)
              } else if (input.field.isSelect && input.field.options.length > 0) {
                this.SelectFieldRow(input)
              } else {
                this.TextFieldRow(input)
              }
            }, (input: DriverFieldInput, index: number): string =>
              `${this.driver}_${index}_${input.field.name}`)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Auto)
      this.BottomActions()
    }
    .width('100%')
    .height('100%')
    // 依赖 localeBump：切换语言后刷新驱动显示名
    .opacity(this.localeBump >= 0 ? 1 : 1)
  }

  @Builder
  FieldLabel(label: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.palette().subText)
  }

  @Builder
  NameField() {
    Column({ space: 6 }) {
      this.FieldLabel(L10n.t('file_mount_name', '挂载名称'))
      TextInput({ text: this.nameText, placeholder: L10n.inputPlease })
        .fontSize(14)
        .fontColor(this.palette().onSurface)
        .placeholderColor(AppTheme.withAlpha(this.palette().onSurface, 0.5))
        .backgroundColor(this.palette().inputFill)
        .borderRadius(8)
        .border({ width: 1, color: this.palette().inputBorder })
        .height(42)
        .width('100%')
        .enabled(!this.isRunning)
        .onChange((v: string): void => {
          this.nameText = v;
        })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  /** 挂载父路径（只读 + 点击选目录，对齐 Flutter readOnly + onTap + suffixIcon） */
  @Builder
  MountPathField() {
    Column({ space: 6 }) {
      this.FieldLabel(L10n.t('file_mount_mount_path', '挂载父路径'))
      Row({ space: 8 }) {
        Text(this.mountPath.trim().length > 0
          ? this.mountPath
          : L10n.t('openlist_mount_pick_folder', '点击选择本地挂载目录'))
          .fontSize(14)
          .fontColor(this.mountPath.trim().length > 0
            ? this.palette().onSurface
            : AppTheme.withAlpha(this.palette().onSurface, 0.5))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(18)
          .fontColor([this.palette().primary])
      }
      .width('100%')
      .height(42)
      .padding({ left: 12, right: 12 })
      .borderRadius(8)
      .backgroundColor(this.palette().inputFill)
      .border({ width: 1, color: this.palette().inputBorder })
      .onClick((): void => {
        if (!this.isRunning) {
          this.pickMountPath();
        }
      })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  DriverField() {
    Column({ space: 6 }) {
      this.FieldLabel(L10n.t('openlist_mount_driver', '网盘类型'))
      if (this.ctrl.isDriversLoading) {
        Row() {
          LoadingProgress()
            .width(22)
            .height(22)
            .color(this.palette().primary)
        }
        .width('100%')
        .height(42)
        .justifyContent(FlexAlign.Center)
      } else {
        Row({ space: 8 }) {
          Text(this.driverDisplayName().length > 0 ? this.driverDisplayName() : L10n.inputPlease)
            .fontSize(14)
            .fontColor(this.driverDisplayName().length > 0
              ? this.palette().onSurface
              : AppTheme.withAlpha(this.palette().onSurface, 0.5))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(14)
            .fontColor([this.palette().hint])
        }
        .width('100%')
        .height(42)
        .padding({ left: 12, right: 12 })
        .borderRadius(8)
        .backgroundColor(this.palette().inputFill)
        .border({ width: 1, color: this.palette().inputBorder })
        .onClick((): void => {
          this.pickDriver();
        })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  /** 文字链接按钮（对齐 Flutter TextButton.icon） */
  @Builder
  LinkButton(label: string, icon: Resource, enabled: boolean, onTap: () => void) {
    Row({ space: 6 }) {
      SymbolGlyph(icon)
        .fontSize(16)
        .fontColor([this.palette().primary])
      Text(label)
        .fontSize(14)
        .fontColor(this.palette().primary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .opacity(enabled ? 1 : 0.45)
    .onClick((): void => {
      if (enabled) {
        onTap();
      }
    })
  }

  /** bool 字段：勾选行（对齐 Flutter CheckboxListTile） */
  @Builder
  BoolFieldRow(input: DriverFieldInput) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(input.label)
          .fontSize(14)
          .fontColor(this.palette().onSurface)
        if (input.hint.length > 0) {
          Text(input.hint)
            .fontSize(12)
            .fontColor(this.palette().subText)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      CircleCheckbox({
        value: input.checked,
        boxSize: 20,
        onChanged: (v: boolean): void => {
          if (!this.isRunning) {
            input.checked = v;
          }
        }
      })
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
    .alignItems(VerticalAlign.Top)
  }

  /** select 字段：下拉行（对齐 Flutter CustomDropdownField；显示值回退首个选项） */
  @Builder
  SelectFieldRow(input: DriverFieldInput) {
    Column({ space: 6 }) {
      this.FieldLabel(input.label)
      Row({ space: 8 }) {
        Text(this.selectDisplayText(input))
          .fontSize(14)
          .fontColor(this.palette().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(14)
          .fontColor([this.palette().hint])
      }
      .width('100%')
      .height(42)
      .padding({ left: 12, right: 12 })
      .borderRadius(8)
      .backgroundColor(this.palette().inputFill)
      .border({ width: 1, color: this.palette().inputBorder })
      .opacity(this.isRunning ? 0.45 : 1)
      .onClick((): void => {
        this.pickSelectField(input);
      })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ bottom: 2 })
  }

  /** 显示值：当前值在选项内取当前值，否则取首个选项（对齐 Flutter value 计算） */
  private selectDisplayText(input: DriverFieldInput): string {
    if (input.field.options.indexOf(input.text) >= 0) {
      return input.text;
    }
    return input.field.options.length > 0 ? input.field.options[0] : '';
  }

  private pickSelectField(input: DriverFieldInput): void {
    if (this.isRunning) {
      return;
    }
    const options: PickOption[] = [];
    input.field.options.forEach((o: string): void => {
      options.push(new PickOption(o, o));
    });
    if (options.length === 0) {
      return;
    }
    showOptionPickSheet(input.label, options, this.selectDisplayText(input),
      (key: string): void => {
        input.text = key;
      });
  }

  /** text/string 字段：text 类型多行，secret 类掩码（对齐 Flutter maxLines/obscureText） */
  @Builder
  TextFieldRow(input: DriverFieldInput) {
    Column({ space: 6 }) {
      this.FieldLabel(input.label)
      if (input.field.isText && !input.field.isSecret) {
        TextArea({ text: input.text, placeholder: input.hint.length > 0 ? input.hint : L10n.inputPlease })
          .fontSize(14)
          .fontColor(this.palette().onSurface)
          .placeholderColor(AppTheme.withAlpha(this.palette().onSurface, 0.5))
          .backgroundColor(this.palette().inputFill)
          .borderRadius(8)
          .border({ width: 1, color: this.palette().inputBorder })
          .height(84)
          .width('100%')
          .enabled(!this.isRunning)
          .onChange((v: string): void => {
            input.text = v;
          })
      } else {
        TextInput({ text: input.text, placeholder: input.hint.length > 0 ? input.hint : L10n.inputPlease })
          .type(input.field.isSecret ? InputType.Password : InputType.Normal)
          .fontSize(14)
          .fontColor(this.palette().onSurface)
          .placeholderColor(AppTheme.withAlpha(this.palette().onSurface, 0.5))
          .backgroundColor(this.palette().inputFill)
          .borderRadius(8)
          .border({ width: 1, color: this.palette().inputBorder })
          .height(42)
          .width('100%')
          .enabled(!this.isRunning)
          .onChange((v: string): void => {
            input.text = v;
          })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  /** 底部操作（对齐 Flutter dialog actions：取消 + 确定，保存中显示加载圈） */
  @Builder
  BottomActions() {
    Row({ space: 12 }) {
      Button(L10n.cancel)
        .fontSize(15)
        .fontColor(this.palette().primary)
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: this.palette().divider })
        .borderRadius(20)
        .height(40)
        .layoutWeight(1)
        .onClick((): void => {
          this.popPage();
        })
      Button() {
        if (this.saving) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(this.palette().buttonText)
        } else {
          Text(L10n.ok)
            .fontSize(15)
            .fontColor(this.palette().buttonText)
        }
      }
      .backgroundColor(this.palette().buttonBg)
      .borderRadius(20)
      .height(40)
      .layoutWeight(1)
      .enabled(!this.saving && !this.isRunning)
      .opacity(this.saving || this.isRunning ? 0.5 : 1)
      .onClick((): void => {
        void this.submit();
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 16 })
  }
}
