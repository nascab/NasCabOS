import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { PageScaffold } from '../../../common/PageScaffold';
import { DialogUtil } from '../../../common/DialogUtil';
import { CircleCheckbox } from '../../../common/components/CircleCheckbox';
import { PickOption, showOptionPickSheet } from '../../../common/components/OptionPickSheet';
import { pickTargetFolderViaSheet } from '../../../files/views/FolderPickerSheet';
import { FileMountController } from '../controllers/FileMountControllers';
import { FileMountEditPageParam } from '../router/FileMountRoutes';
import { MountItem, recStr } from '../models/FileMountModels';

/** WebDAV vendor 合法值（与 rclone --webdav-vendor 一致；选错时部分服务端会列目录为空） */
const WEBDAV_VENDORS: string[] = ['other', 'nextcloud', 'owncloud', 'infinitescale',
  'sharepoint', 'sharepoint-ntlm', 'fastmail', 'rclone'];

/**
 * 文件协议挂载 新增/编辑页（对齐 Flutter _MountDialog，对话框转为移动端编辑页，功能不变）。
 * 运行中挂载所有字段锁定（对齐 Flutter enabled: !_isRunning && !_saving）。
 */
@ComponentV2
export struct FileMountEditPage {
  @Param param: FileMountEditPageParam = new FileMountEditPageParam();
  @Param popPage: () => void = (): void => {
  };
  private ctrl: FileMountController = FileMountController.getInstance();

  @Local nameText: string = '';
  @Local mountPath: string = '';
  @Local hostText: string = '';
  @Local portText: string = '';
  @Local usernameText: string = '';
  @Local passwordText: string = '';
  @Local remotePathText: string = '';
  @Local protocol: string = 'webdav';
  @Local webdavScheme: string = 'http';
  @Local webdavVendor: string = 'other';
  /** 默认跳过 HTTPS 证书校验；仅当配置显式为 false 时关闭（对齐 Flutter） */
  @Local webdavSkipTls: boolean = true;
  @Local webdavTrailingSlash: boolean = false;
  @Local showPassword: boolean = false;
  @Local saving: boolean = false;

  private get isEdit(): boolean {
    return this.param.initial !== undefined;
  }

  private get isRunning(): boolean {
    return this.param.initial !== undefined && this.param.initial.isRunning;
  }

  private get locked(): boolean {
    return this.isRunning || this.saving;
  }

  aboutToAppear(): void {
    const init: MountItem | undefined = this.param.initial;
    if (init === undefined) {
      return;
    }
    this.nameText = init.name;
    this.mountPath = init.mountPath;
    const cfg = init.config;
    const protocol = recStr(cfg, 'protocol').trim().toLowerCase();
    if (protocol === 'webdav' || protocol === 'ftp' || protocol === 'sftp') {
      this.protocol = protocol;
    }
    const scheme = recStr(cfg, 'scheme').trim().toLowerCase();
    if (scheme === 'http' || scheme === 'https') {
      this.webdavScheme = scheme;
    }
    const vendor = recStr(cfg, 'vendor').trim().toLowerCase();
    if (WEBDAV_VENDORS.indexOf(vendor) >= 0) {
      this.webdavVendor = vendor;
    }
    this.webdavSkipTls = cfg['webdav_skip_verify'] !== false;
    this.webdavTrailingSlash = cfg['webdav_trailing_slash'] === true;
    this.hostText = recStr(cfg, 'host');
    this.portText = recStr(cfg, 'port');
    this.usernameText = recStr(cfg, 'username');
    this.remotePathText = recStr(cfg, 'remote_path');
    // 密码一律留空：编辑时留空表示保持不变（对齐 Flutter）
  }

  private defaultPort(): number {
    if (this.protocol === 'sftp') {
      return 22;
    }
    if (this.protocol === 'ftp') {
      return 21;
    }
    if (this.protocol === 'webdav') {
      return this.webdavScheme === 'https' ? 443 : 80;
    }
    return 0;
  }

  /** 纯数字端口解析（对齐 Flutter int.tryParse 的取值范围判断） */
  private parsePort(raw: string): number | undefined {
    const t = raw.trim();
    if (t.length === 0 || !/^\d+$/.test(t)) {
      return undefined;
    }
    const v = Number.parseInt(t, 10);
    if (!Number.isFinite(v) || v <= 0 || v > 65535) {
      return undefined;
    }
    return v;
  }

  private isValidMountFolderName(value: string): boolean {
    const t = value.trim();
    if (t.length === 0 || t === '.' || t === '..') {
      return false;
    }
    if (t.includes('/') || t.includes('\\')) {
      return false;
    }
    if (/[\x00-\x1F]/.test(t)) {
      return false;
    }
    if (t.endsWith(' ') || t.endsWith('.')) {
      return false;
    }
    if (/[<>:"|?*]/.test(t)) {
      return false;
    }
    return true;
  }

  private normalizePath(raw: string): string {
    const t = raw.trim();
    if (t.length === 0) {
      return '/';
    }
    if (t.startsWith('/')) {
      return t;
    }
    return `/${t}`;
  }

  private buildRemoteDisplay(port: number): string {
    const path = this.normalizePath(this.remotePathText);
    if (this.protocol === 'webdav') {
      return `${this.webdavScheme}://${this.hostText.trim()}:${port}${path}`;
    }
    return `${this.protocol}://${this.hostText.trim()}:${port}${path}`;
  }

  private pickMountPath(): void {
    pickTargetFolderViaSheet(this.mountPath.trim(), (paths: string[]): void => {
      if (paths.length === 0) {
        return;
      }
      this.mountPath = paths[0];
    });
  }

  private pickProtocol(): void {
    const options: PickOption[] = [
      new PickOption('webdav', L10n.t('file_share_server_webdav', 'WebDAV')),
      new PickOption('ftp', L10n.t('file_share_server_ftp', 'FTP')),
      new PickOption('sftp', L10n.t('file_share_server_sftp', 'SFTP'))
    ];
    showOptionPickSheet(L10n.t('file_mount_protocol', '协议'), options, this.protocol,
      (key: string): void => {
        this.protocol = key;
      });
  }

  private pickScheme(): void {
    const options: PickOption[] = [
      new PickOption('http', 'http'),
      new PickOption('https', 'https')
    ];
    showOptionPickSheet(L10n.t('file_mount_webdav_scheme', 'WebDAV 协议类型'), options, this.webdavScheme,
      (key: string): void => {
        this.webdavScheme = key;
      });
  }

  private pickVendor(): void {
    const options: PickOption[] = [];
    WEBDAV_VENDORS.forEach((v: string): void => {
      options.push(new PickOption(v, v));
    });
    showOptionPickSheet(L10n.t('file_mount_webdav_vendor', 'WebDAV 服务端类型'), options, this.webdavVendor,
      (key: string): void => {
        this.webdavVendor = key;
      });
  }

  /** 提交（对齐 Flutter _submit：校验 → 组装 config/remote → upsert） */
  private async submit(): Promise<void> {
    if (this.saving) {
      return;
    }
    const init: MountItem | undefined = this.param.initial;
    const id = init !== undefined && init.id > 0 ? init.id : undefined;
    const name = this.nameText.trim();
    const mountPath = this.mountPath.trim();
    const host = this.hostText.trim();
    const username = this.usernameText.trim();
    const password = this.passwordText.trim();
    const port = this.parsePort(this.portText) ?? this.defaultPort();

    if (name.length === 0 || mountPath.length === 0 || host.length === 0
      || username.length === 0 || (!this.isEdit && password.length === 0)) {
      void DialogUtil.showErrorDialog(L10n.t('file_mount_required', '挂载名称/挂载父路径/服务器信息必填'));
      return;
    }
    if (!this.isValidMountFolderName(name)) {
      void DialogUtil.showErrorDialog(
        L10n.t('file_mount_name_invalid', '挂载名称不是合法的文件夹名称，请修改。'));
      return;
    }
    if (port <= 0) {
      void DialogUtil.showErrorDialog(L10n.t('file_share_server_port_invalid', '端口不合法'));
      return;
    }

    const cfg: Record<string, Object> = {
      'protocol': this.protocol,
      'host': host,
      'port': port,
      'username': username,
      'remote_path': this.normalizePath(this.remotePathText)
    };
    if (this.protocol === 'webdav') {
      cfg['scheme'] = this.webdavScheme;
      cfg['vendor'] = this.webdavVendor;
      cfg['webdav_skip_verify'] = this.webdavSkipTls;
      cfg['webdav_trailing_slash'] = this.webdavTrailingSlash;
    }
    if (password.length > 0) {
      cfg['password'] = password;
    }
    const remote = this.buildRemoteDisplay(port);

    this.saving = true;
    void DialogUtil.showLoading(L10n.loading);
    try {
      const ok = await this.ctrl.upsert(id, name, mountPath, remote, cfg);
      if (ok) {
        this.popPage();
        return;
      }
    } finally {
      void DialogUtil.dismissLoading(true);
      this.saving = false;
    }
  }

  build() {
    PageScaffold({
      title: this.isEdit
        ? L10n.t('file_mount_edit', '编辑挂载')
        : L10n.t('file_mount_create', '创建挂载'),
      showBack: true,
      statusBarBg: AppTheme.current().pageBg,
      // 保存中阻止返回（对齐 Flutter WillPopScope onWillPop: !_saving）
      customBack: (): boolean => {
        return this.saving;
      },
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
          this.InputField(L10n.t('file_mount_name', '挂载名称'), this.nameText, L10n.inputPlease,
            (v: string): void => {
              this.nameText = v;
            })
          this.MountPathField()
          this.SelectRow(L10n.t('file_mount_protocol', '协议'), this.protocolLabel(), (): void => {
            this.pickProtocol();
          })
          if (this.protocol === 'webdav') {
            this.SelectRow(L10n.t('file_mount_webdav_scheme', 'WebDAV 协议类型'), this.webdavScheme,
              (): void => {
                this.pickScheme();
              })
            this.SelectRow(L10n.t('file_mount_webdav_vendor', 'WebDAV 服务端类型'), this.webdavVendor,
              (): void => {
                this.pickVendor();
              })
            if (this.webdavScheme === 'https') {
              this.CheckRow(L10n.t('file_mount_webdav_skip_tls',
                '跳过 HTTPS 证书校验（默认开启；自签名/内网环境）'), this.webdavSkipTls,
                (v: boolean): void => {
                  this.webdavSkipTls = v;
                })
            }
            this.CheckRow(L10n.t('file_mount_webdav_trailing_slash',
              '远程路径强制补全末尾斜杠（若列目录为空）'), this.webdavTrailingSlash,
              (v: boolean): void => {
                this.webdavTrailingSlash = v;
              })
          }
          Row({ space: 8 }) {
            Column({ space: 6 }) {
              this.FieldLabel(L10n.t('file_mount_server_host', '主机'))
              this.HostInput()
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Column({ space: 6 }) {
              this.FieldLabel(L10n.t('file_mount_server_port', '端口'))
              this.PortInput()
            }
            .alignItems(HorizontalAlign.Start)
            .width(120)
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)
          this.InputField(L10n.t('username', '用户名'), this.usernameText, L10n.inputPlease,
            (v: string): void => {
              this.usernameText = v;
            })
          this.PasswordField()
          this.InputField(L10n.t('file_mount_remote_path', '远程路径（可选，默认为“/”）'),
            this.remotePathText, '/',
            (v: string): void => {
              this.remotePathText = v;
            })
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
  }

  private protocolLabel(): string {
    if (this.protocol === 'webdav') {
      return L10n.t('file_share_server_webdav', 'WebDAV');
    }
    if (this.protocol === 'ftp') {
      return L10n.t('file_share_server_ftp', 'FTP');
    }
    if (this.protocol === 'sftp') {
      return L10n.t('file_share_server_sftp', 'SFTP');
    }
    return this.protocol;
  }

  @Builder
  FieldLabel(label: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.palette().subText)
  }

  @Builder
  InputField(label: string, text: string, placeholder: string, onChange: (v: string) => void) {
    Column({ space: 6 }) {
      this.FieldLabel(label)
      TextInput({ text: text, placeholder: placeholder })
        .fontSize(14)
        .fontColor(this.palette().onSurface)
        .placeholderColor(AppTheme.withAlpha(this.palette().onSurface, 0.5))
        .backgroundColor(this.palette().inputFill)
        .borderRadius(8)
        .border({ width: 1, color: this.palette().inputBorder })
        .height(42)
        .width('100%')
        .enabled(!this.locked)
        .onChange((v: string): void => {
          onChange(v);
        })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  HostInput() {
    TextInput({ text: this.hostText, placeholder: L10n.inputPlease })
      .fontSize(14)
      .fontColor(this.palette().onSurface)
      .placeholderColor(AppTheme.withAlpha(this.palette().onSurface, 0.5))
      .backgroundColor(this.palette().inputFill)
      .borderRadius(8)
      .border({ width: 1, color: this.palette().inputBorder })
      .height(42)
      .width('100%')
      .enabled(!this.locked)
      .onChange((v: string): void => {
        this.hostText = v;
      })
  }

  @Builder
  PortInput() {
    TextInput({ text: this.portText, placeholder: `${this.defaultPort()}` })
      .type(InputType.Number)
      .fontSize(14)
      .fontColor(this.palette().onSurface)
      .placeholderColor(AppTheme.withAlpha(this.palette().onSurface, 0.5))
      .backgroundColor(this.palette().inputFill)
      .borderRadius(8)
      .border({ width: 1, color: this.palette().inputBorder })
      .height(42)
      .width('100%')
      .enabled(!this.locked)
      .onChange((v: string): void => {
        this.portText = v;
      })
  }

  @Builder
  PasswordField() {
    Column({ space: 6 }) {
      this.FieldLabel(L10n.t('password', '密码'))
      Row({ space: 8 }) {
        TextInput({ text: this.passwordText,
          placeholder: this.isEdit
            ? L10n.t('file_mount_password_keep_tip', '留空表示保持不变')
            : L10n.inputPlease })
          .type(this.showPassword ? InputType.Normal : InputType.Password)
          .fontSize(14)
          .fontColor(this.palette().onSurface)
          .placeholderColor(AppTheme.withAlpha(this.palette().onSurface, 0.5))
          .backgroundColor(this.palette().inputFill)
          .borderRadius(8)
          .border({ width: 1, color: this.palette().inputBorder })
          .height(42)
          .layoutWeight(1)
          .enabled(!this.locked)
          .onChange((v: string): void => {
            this.passwordText = v;
          })
        SymbolGlyph(this.showPassword ? $r('sys.symbol.eye_slash') : $r('sys.symbol.eye'))
          .fontSize(20)
          .fontColor([this.palette().hint])
          .onClick((): void => {
            this.showPassword = !this.showPassword;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  /** 挂载父路径（只读 + 点击选目录，对齐 Flutter readOnly + onTap） */
  @Builder
  MountPathField() {
    Column({ space: 6 }) {
      this.FieldLabel(L10n.t('file_mount_mount_path', '挂载父路径'))
      Row({ space: 8 }) {
        Text(this.mountPath.trim().length > 0 ? this.mountPath : L10n.inputPlease)
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
        if (!this.locked) {
          this.pickMountPath();
        }
      })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  /** 下拉选择行（对齐 Flutter CustomDropdownField，鸿蒙端以底部弹层选择） */
  @Builder
  SelectRow(label: string, value: string, onTap: () => void) {
    Column({ space: 6 }) {
      this.FieldLabel(label)
      Row({ space: 8 }) {
        Text(value)
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
      .onClick((): void => {
        if (!this.locked) {
          onTap();
        }
      })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  CheckRow(label: string, checked: boolean, onChanged: (v: boolean) => void) {
    Row({ space: 10 }) {
      CircleCheckbox({
        value: checked,
        boxSize: 20,
        onChanged: (v: boolean): void => {
          if (!this.locked) {
            onChanged(v);
          }
        }
      })
      Text(label)
        .fontSize(12)
        .fontColor(this.palette().subText)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 2, bottom: 2 })
    .alignItems(VerticalAlign.Top)
  }

  /** 底部操作（对齐 Flutter dialog actions：取消 + 确定，运行中/保存中禁用确定） */
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
        .enabled(!this.saving)
        .onClick((): void => {
          this.popPage();
        })
      Button(L10n.ok)
        .fontSize(15)
        .fontColor(this.palette().buttonText)
        .backgroundColor(this.palette().buttonBg)
        .borderRadius(20)
        .height(40)
        .layoutWeight(1)
        .enabled(!this.isRunning && !this.saving)
        .opacity(this.isRunning || this.saving ? 0.5 : 1)
        .onClick((): void => {
          void this.submit();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 16 })
  }
}
