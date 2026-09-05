import { bundleManager, common } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { L10n } from '../core/localization/L10n';
import { UpdateCheckHelper, UpdateInfo } from './UpdateCheckHelper';
import { LanguageOption, LanguageService } from '../core/localization/LanguageService';
import { ThemeManager, ThemeMode } from '../core/theme/ThemeManager';
import { AppTheme } from '../core/theme/AppTheme';
import { CurrentUserStore } from '../core/user/CurrentUserStore';
import { SettingsApiService } from './SettingsApiService';
import { ServerStorageService } from '../core/storage/ServerStorageService';
import { APIClient } from '../core/network/APIClient';
import { AppRouter } from '../router/AppRouter';
import { LegalPageParam } from '../pages/LegalPage';
import { PageScaffold } from '../common/PageScaffold';
import { DialogUtil, SelectItem } from '../common/DialogUtil';
import { AppEventBus } from '../common/AppEventBus';

@ComponentV2
export struct SettingsPage {
  @Param onBack: () => void = () => {
  };
  @Param pushLegal: (param: LegalPageParam) => void = (_param: LegalPageParam) => {
  };
  @Local localeTick: number = 0;
  @Local themeTick: number = 0;
  @Local httpPort: string = '6789';
  @Local httpsPort: string = '6799';
  @Local apiCount: string = '2';
  @Local welcomeText: string = '';
  @Local hostname: string = '';
  @Local cpuCores: number | undefined = undefined;
  @Local loadingConfig: boolean = false;
  @Local saving: boolean = false;
  @Local savingWelcome: boolean = false;
  @Local savingHostname: boolean = false;
  @Local restartingService: boolean = false;
  @Local loadingCacheSize: boolean = false;
  @Local cacheSizeBytes: number = -1;
  @Local appVersion: string = '--';
  @Local hasUpdate: boolean = false;
  private updateOpenUrl: string = '';
  private api: SettingsApiService = SettingsApiService.getInstance();
  private userStore: CurrentUserStore = CurrentUserStore.getInstance();
  private localeListener: (data: string) => void = (_data: string) => {
    this.localeTick++;
  };
  private themeListener: (data: string) => void = (_data: string) => {
    this.themeTick++;
  };

  aboutToAppear(): void {
    AppEventBus.on(LanguageService.EVENT_LOCALE_CHANGED, this.localeListener);
    AppEventBus.on(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    this.loadAppVersion();
    if (this.userStore.isAdmin) {
      this.loadConfig();
      this.loadCacheSize();
    }
  }

  aboutToDisappear(): void {
    AppEventBus.off(LanguageService.EVENT_LOCALE_CHANGED, this.localeListener);
    AppEventBus.off(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
  }

  // ===== 主题/语言选择 =====
  private showThemeSelectDialog(): void {
    const mode = ThemeManager.getInstance().getThemeMode();
    void DialogUtil.showSelectDialog(
      L10n.settingsThemeTitle,
      [
        new SelectItem(L10n.settingsThemeLightMode, $r('sys.symbol.sun_max')),
        new SelectItem(L10n.settingsThemeDarkMode, $r('sys.symbol.moon')),
        new SelectItem(L10n.settingsThemeSystemMode, $r('sys.symbol.phone'))
      ],
      mode === 'light' ? 0 : (mode === 'dark' ? 1 : 2),
      (index: number) => {
        const target: ThemeMode = index === 0 ? 'light' : (index === 1 ? 'dark' : 'system');
        void ThemeManager.getInstance().saveThemeMode(target);
      }
    );
  }

  private showLanguageSelectDialog(): void {
    const options = LanguageService.getFullLanguageOptions();
    const current = LanguageService.getInstance().currentLocale;
    void DialogUtil.showSelectDialog(
      L10n.settingsLanguageDialogTitle,
      options.map((o: LanguageOption) => new SelectItem(o.label)),
      options.findIndex((o: LanguageOption) => o.value === current),
      (index: number) => {
        if (index >= 0 && index < options.length) {
          // 全局语言服务广播 localeChanged，本页与其他在栈页面即时刷新
          void LanguageService.getInstance().changeLanguage(options[index].value);
        }
      }
    );
  }

  private loadAppVersion(): void {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.appVersion = info.versionName;
      // 先根据缓存显示是否有更新，再在后台执行检测（24h 内可能不请求，对应 Flutter _initUpdateCheck）
      this.initUpdateCheck();
    } catch (e) {
      this.appVersion = '--';
    }
  }

  /** 先根据缓存显示是否有更新，再在后台执行检测 */
  private async initUpdateCheck(): Promise<void> {
    try {
      const info: UpdateInfo | undefined = UpdateCheckHelper.getUpdateInfoIfNewer(this.appVersion);
      this.hasUpdate = info !== undefined;
      this.updateOpenUrl = info?.openUrl ?? '';
      void this.checkUpdateInBackground();
    } catch (_e) {
      // 更新检测失败不影响页面
    }
  }

  private async checkUpdateInBackground(): Promise<void> {
    try {
      const hasUpdate = await UpdateCheckHelper.checkForUpdate(this.appVersion);
      const info = UpdateCheckHelper.getUpdateInfoIfNewer(this.appVersion);
      this.hasUpdate = hasUpdate && info !== undefined;
      this.updateOpenUrl = info?.openUrl ?? '';
    } catch (_e) {
      // 忽略后台检测异常
    }
  }

  private openUpdateUrl(): void {
    const url = this.updateOpenUrl.trim();
    if (url.length === 0) {
      return;
    }
    try {
      (getContext(this) as common.UIAbilityContext).openLink(url);
    } catch (_e) {
      // 打开失败时静默处理
    }
  }

  // ===== 服务端配置加载/保存 =====
  private async loadConfig(): Promise<void> {
    if (this.loadingConfig) {
      return;
    }
    this.loadingConfig = true;
    try {
      const resp = await this.api.getConfig();
      if (!resp.success) {
        this.getUIContext().getPromptAction().showToast({ message: resp.message ?? L10n.operationFailed });
        return;
      }
      const data = resp.data;
      if (data) {
        this.cpuCores = data.cpuCores;
        this.httpPort = `${data.httpPort}`;
        this.httpsPort = `${data.httpsPort}`;
        this.apiCount = `${data.expressApiCount}`;
        this.welcomeText = data.welcomeText.length > 0 ? data.welcomeText : L10n.authWelcomeTitle;
        this.hostname = data.customHostname;
      }
    } finally {
      this.loadingConfig = false;
    }
  }

  private apiCountPlaceholder(): string {
    return this.cpuCores !== undefined
      ? `${L10n.settingsServerApiCount} / ${L10n.monitorCores}: ${this.cpuCores}`
      : L10n.settingsServerApiCount;
  }

  private parsePort(raw: string): number | undefined {
    const s = raw.trim();
    if (s.length === 0) {
      return undefined;
    }
    const n = parseInt(s, 10);
    if (isNaN(n) || n <= 0 || n > 65535) {
      return undefined;
    }
    return n;
  }

  private busySaving(): boolean {
    return this.saving || this.savingWelcome || this.savingHostname;
  }

  private async saveConfig(): Promise<void> {
    if (this.busySaving()) {
      return;
    }
    const httpPort = this.parsePort(this.httpPort);
    if (httpPort === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: L10n.settingsServerHttpPortInvalid });
      return;
    }
    const httpsPort = this.parsePort(this.httpsPort);
    if (httpsPort === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: L10n.settingsServerHttpsPortInvalid });
      return;
    }
    const countRaw = this.apiCount.trim();
    const apiCount = countRaw.length === 0 ? undefined : parseInt(countRaw, 10);
    if (apiCount === undefined || isNaN(apiCount)) {
      this.getUIContext().getPromptAction().showToast({ message: L10n.settingsServerApiCountInvalid });
      return;
    }
    if (apiCount < 2) {
      this.getUIContext().getPromptAction().showToast({ message: L10n.settingsServerApiCountTooLow });
      return;
    }
    if (this.cpuCores !== undefined && apiCount > this.cpuCores) {
      this.getUIContext().getPromptAction().showToast({
        message: L10n.settingsServerApiCountTooHigh(`${this.cpuCores}`)
      });
      return;
    }
    this.saving = true;
    try {
      const resp = await this.api.saveConfig(httpPort, httpsPort, apiCount);
      if (!resp.success) {
        this.getUIContext().getPromptAction().showToast({ message: resp.message ?? L10n.operationFailed });
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: L10n.settingsServerRestartRequired });
      await this.loadConfig();
    } finally {
      this.saving = false;
    }
  }

  private async saveWelcome(): Promise<void> {
    if (this.busySaving()) {
      return;
    }
    const text = this.welcomeText.trim();
    if (text.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: L10n.settingsPersonalizationWelcomeInvalid });
      return;
    }
    this.savingWelcome = true;
    try {
      const resp = await this.api.saveWelcome(text);
      if (!resp.success) {
        this.getUIContext().getPromptAction().showToast({ message: resp.message ?? L10n.operationFailed });
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: resp.message ?? L10n.success });
      await this.loadConfig();
    } finally {
      this.savingWelcome = false;
    }
  }

  private async saveHostname(): Promise<void> {
    if (this.busySaving()) {
      return;
    }
    const text = this.hostname.trim();
    if (text.length > 10) {
      this.getUIContext().getPromptAction().showToast({ message: L10n.settingsCustomHostnameInvalid });
      return;
    }
    this.savingHostname = true;
    try {
      const resp = await this.api.setCustomHostname(text);
      if (!resp.success) {
        this.getUIContext().getPromptAction().showToast({ message: resp.message ?? L10n.operationFailed });
        return;
      }
      const stored = text.length === 0 ? undefined : text;
      // 同步到服务器本地存储（对齐 Flutter updateServerCustomHostnameForSession）
      await this.updateServerCustomHostname(stored);
      this.getUIContext().getPromptAction().showToast({ message: resp.message ?? L10n.success });
      await this.loadConfig();
    } finally {
      this.savingHostname = false;
    }
  }

  private async updateServerCustomHostname(customHostname: string | undefined): Promise<void> {
    try {
      const storage = ServerStorageService.getInstance();
      const servers = storage.loadServers();
      const serverId = APIClient.getInstance().state.serverId;
      const username = (this.userStore.current?.username ?? '').trim();
      const target = servers.find(s => s.serverId === serverId &&
        (s.username ?? '').trim() === username);
      if (target) {
        target.customHostname = customHostname;
        await storage.updateServer(target);
      }
    } catch (e) {
      // 存储更新失败不阻塞保存流程
    }
  }

  // ===== 缓存清理 =====
  private async loadCacheSize(): Promise<void> {
    if (this.loadingCacheSize) {
      return;
    }
    this.loadingCacheSize = true;
    try {
      const dir = getContext(this).cacheDir;
      this.cacheSizeBytes = await SettingsPage.dirSize(dir);
    } catch (e) {
      this.cacheSizeBytes = -1;
    } finally {
      this.loadingCacheSize = false;
    }
  }

  private static async dirSize(path: string): Promise<number> {
    let total = 0;
    try {
      const names = await fs.listFile(path);
      for (const name of names) {
        const child = `${path}/${name}`;
        const stat = await fs.stat(child);
        if (stat.isDirectory()) {
          total += await SettingsPage.dirSize(child);
        } else {
          total += stat.size;
        }
      }
    } catch (e) {
      // 忽略无权限路径
    }
    return total;
  }

  private formatBytes(bytes: number): string {
    if (bytes <= 0) {
      return '0 B';
    }
    const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
    let v = bytes;
    let i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    const s = i <= 1 ? `${Math.round(v)}` : `${v.toFixed(1)}`;
    return `${s} ${units[i]}`;
  }

  private async clearCacheInBackground(): Promise<void> {
    try {
      const dir = getContext(this).cacheDir;
      await SettingsPage.clearDir(dir);
      await this.loadCacheSize();
      this.getUIContext().getPromptAction().showToast({ message: L10n.settingsClearCacheSuccess });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: L10n.operationFailed });
    }
  }

  private static async clearDir(path: string): Promise<void> {
    const names = await fs.listFile(path);
    for (const name of names) {
      const child = `${path}/${name}`;
      const stat = await fs.stat(child);
      if (stat.isDirectory()) {
        await SettingsPage.clearDir(child);
        await fs.rmdir(child);
      } else {
        await fs.unlink(child);
      }
    }
  }

  // ===== 重启服务 =====
  private async restartService(): Promise<void> {
    if (this.restartingService) {
      return;
    }
    this.restartingService = true;
    try {
      const resp = await this.api.restartService();
      if (!resp.success) {
        this.getUIContext().getPromptAction().showToast({ message: resp.message ?? L10n.operationFailed });
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: L10n.settingsRestartServiceRequested });
    } finally {
      this.restartingService = false;
    }
  }

  build() {
    // PageScaffold 根节点即 NavDestination，直接作为 navDestination 分支内容
    PageScaffold({
      title: L10n.setting,
      showBack: true,
      onBack: () => {
        this.onBack();
      },
      content: () => {
        this.PageContent()
      }
    })
  }

  @Builder
  PageContent() {
    Scroll() {
      Column() {
        if (this.userStore.isAdmin) {
          this.ServerConfigCard()
          this.CustomHostnameCard()
          this.PersonalizationCard()
        }
        this.GeneralListCard()
        // 版本号居中展示，有更新时右侧显示更新入口
        Row({ space: 12 }) {
          Text(`${L10n.settingsAppVersion}: V${this.appVersion}`)
            .fontSize(12)
            .fontColor(AppTheme.current().subText)
          if (this.hasUpdate && this.updateOpenUrl.length > 0) {
            Text(L10n.settingsUpdateAvailable)
              .fontSize(12)
              .fontColor(AppTheme.current().primary)
              .onClick(() => {
                this.openUpdateUrl();
              })
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 24, bottom: 16 })
      }
      .width('100%')
      .padding(16)
      .alignItems(HorizontalAlign.Start)
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    // 依赖 localeTick/themeTick：语言或主题切换后触发整页刷新
    .opacity((this.localeTick + this.themeTick) >= 0 ? 1 : 1)
  }

  // ===== 卡片：服务端配置 =====
  @Builder
  ServerConfigCard() {
    Column() {
      Text(L10n.settingsServerConfigTitle)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
      Row({ space: 12 }) {
        this.PortField('settings_server_http_port', this.httpPort, (v: string) => {
          this.httpPort = v;
        })
      }
      .margin({ top: 12 })
      Row({ space: 12 }) {
        this.PortField('settings_server_https_port', this.httpsPort, (v: string) => {
          this.httpsPort = v;
        })
      }
      .margin({ top: 12 })
      Row({ space: 12 }) {
        this.ApiCountField()
      }
      .margin({ top: 12 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor(AppTheme.current().cardBg)
    .borderRadius(12)
    .margin({ bottom: 16 })
  }

  @Builder
  PortField(labelKey: string, value: string, onChange: (v: string) => void) {
    Row({ space: 8 }) {
      // 绑定内解析语言key：切换语言后自动刷新（@Builder 按值传参不会随状态更新）
      TextInput({ text: value, placeholder: L10n.t(labelKey) })
        .type(InputType.Number)
        .layoutWeight(1)
        .height(42)
        .fontSize(14)
        .fontColor(AppTheme.current().onSurface)
        .placeholderColor(AppTheme.current().hint)
        .backgroundColor(AppTheme.current().inputFill)
        .border({ width: 1, color: AppTheme.current().inputBorder })
        .borderRadius(8)
        .onChange((v: string) => onChange(v))
      Button(L10n.save)
        .height(32)
        .fontSize(13)
        .fontColor(AppTheme.current().buttonText)
        .backgroundColor(AppTheme.current().buttonBg)
        .enabled(!this.saving && !this.loadingConfig)
        .onClick(() => {
          this.saveConfig();
        })
    }
    .width('100%')
  }

  @Builder
  ApiCountField() {
    Row({ space: 8 }) {
      TextInput({ text: this.apiCount, placeholder: this.apiCountPlaceholder() })
        .type(InputType.Number)
        .layoutWeight(1)
        .height(42)
        .fontSize(14)
        .fontColor(AppTheme.current().onSurface)
        .placeholderColor(AppTheme.current().hint)
        .backgroundColor(AppTheme.current().inputFill)
        .border({ width: 1, color: AppTheme.current().inputBorder })
        .borderRadius(8)
        .onChange((v: string) => {
          this.apiCount = v;
        })
      Button(L10n.save)
        .height(32)
        .fontSize(13)
        .fontColor(AppTheme.current().buttonText)
        .backgroundColor(AppTheme.current().buttonBg)
        .enabled(!this.saving && !this.loadingConfig)
        .onClick(() => {
          this.saveConfig();
        })
    }
    .width('100%')
  }

  // ===== 卡片：自定义主机名 =====
  @Builder
  CustomHostnameCard() {
    Column() {
      Text(L10n.settingsCustomHostnameTitle)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
      Row({ space: 8 }) {
        TextInput({ text: this.hostname, placeholder: L10n.settingsCustomHostnameFieldLabel })
          .type(InputType.Normal)
          .maxLength(10)
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
          .placeholderColor(AppTheme.current().hint)
          .backgroundColor(AppTheme.current().inputFill)
          .border({ width: 1, color: AppTheme.current().inputBorder })
          .borderRadius(8)
          .onChange((v: string) => {
            this.hostname = v;
          })
        Button(L10n.save)
          .height(32)
          .fontSize(13)
          .fontColor(AppTheme.current().buttonText)
          .backgroundColor(AppTheme.current().buttonBg)
          .enabled(!this.savingHostname && !this.loadingConfig)
          .onClick(() => {
            this.saveHostname();
          })
      }
      .margin({ top: 12 })
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor(AppTheme.current().cardBg)
    .borderRadius(12)
    .margin({ bottom: 16 })
  }

  // ===== 卡片：个性化 =====
  @Builder
  PersonalizationCard() {
    Column() {
      Text(L10n.settingsPersonalizationTitle)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
      Row({ space: 8 }) {
        TextInput({ text: this.welcomeText, placeholder: L10n.settingsPersonalizationWelcomeLabel })
          .type(InputType.Normal)
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
          .placeholderColor(AppTheme.current().hint)
          .backgroundColor(AppTheme.current().inputFill)
          .border({ width: 1, color: AppTheme.current().inputBorder })
          .borderRadius(8)
          .onChange((v: string) => {
            this.welcomeText = v;
          })
        Button(L10n.save)
          .height(32)
          .fontSize(13)
          .fontColor(AppTheme.current().buttonText)
          .backgroundColor(AppTheme.current().buttonBg)
          .enabled(!this.savingWelcome && !this.loadingConfig)
          .onClick(() => {
            this.saveWelcome();
          })
      }
      .margin({ top: 12 })
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor(AppTheme.current().cardBg)
    .borderRadius(12)
    .margin({ bottom: 16 })
  }

  // ===== 卡片：通用设置列表 =====
  @Builder
  GeneralListCard() {
    Column() {
      this.SettingsItem(
        'settings_theme',
        'settings_theme_customize_appearance',
        $r('sys.symbol.paintpalette'),
        () => {
          this.showThemeSelectDialog();
        },
        false
      )
      Divider().color(AppTheme.current().divider).margin({ left: 52 })
      this.SettingsItem(
        'settings_language',
        'settings_language_switch_app_language',
        $r('sys.symbol.translate'),
        () => {
          this.showLanguageSelectDialog();
        },
        false
      )
      Divider().color(AppTheme.current().divider).margin({ left: 52 })
      this.SettingsItem(
        'auth_user_agreement',
        'settings_legal_document_subtitle',
        $r('sys.symbol.doc_plaintext'),
        () => {
          this.openLegal(L10n.authUserAgreement, true);
        },
        false
      )
      Divider().color(AppTheme.current().divider).margin({ left: 52 })
      this.SettingsItem(
        'auth_privacy_policy',
        'settings_legal_document_subtitle',
        $r('sys.symbol.checkmark_shield'),
        () => {
          this.openLegal(L10n.authPrivacyPolicy, false);
        },
        false
      )
      if (this.userStore.isAdmin) {
        Divider().color(AppTheme.current().divider).margin({ left: 52 })
        this.SettingsItem(
          'settings_clear_cache',
          'settings_clear_cache_description',
          $r('sys.symbol.clean'),
          () => {
            void DialogUtil.showConfirmDialog(
              L10n.settingsClearCacheDialogTitle,
              L10n.settingsClearCacheDialogContent,
              () => {
                this.clearCacheInBackground();
              }
            );
          },
          this.loadingCacheSize
        )
        Divider().color(AppTheme.current().divider).margin({ left: 52 })
        this.SettingsItem(
          'settings_restart_service',
          'settings_restart_service_description',
          $r('sys.symbol.arrow_counterclockwise'),
          () => {
            void DialogUtil.showConfirmDialog(
              L10n.settingsRestartServiceDialogTitle,
              L10n.settingsRestartServiceDialogContent,
              () => {
                this.restartService();
              }
            );
          },
          this.restartingService
        )
      }
    }
    .width('100%')
    .backgroundColor(AppTheme.current().cardBg)
    .borderRadius(12)
  }

  /** 缓存大小后缀（动态部分单独拼接，语言文案部分仍走 key 解析） */
  private cacheSizeSuffix(): string {
    return this.cacheSizeBytes >= 0 ? ` (${this.formatBytes(this.cacheSizeBytes)})` : '';
  }

  @Builder
  SettingsItem(titleKey: string, subtitleKey: string, icon: Resource, onTap: () => void, showLoading: boolean) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([AppTheme.current().onSurface])
      Column() {
        // 绑定内解析语言key：切换语言后自动刷新（@Builder 按值传参不会随状态更新）
        Text(L10n.t(titleKey))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
        Text(L10n.t(subtitleKey) + this.cacheSizeSuffix())
          .fontSize(12)
          .fontColor(AppTheme.current().subText)
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (showLoading) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(AppTheme.current().hint)
      } else {
        SymbolGlyph($r('sys.symbol.arrow_right'))
          .fontSize(14)
          .fontColor([AppTheme.current().hint])
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(() => onTap())
  }

  private openLegal(title: string, isAgreement: boolean): void {
    // 对齐 Flutter LegalUrls：websiteBaseUrl = https://nas.cab
    const website = 'https://nas.cab';
    const base = isAgreement
      ? `${website}/others/agreement.html`
      : `${website}/others/privacy.html`;
    const param = new LegalPageParam();
    param.title = title;
    param.url = `${base}?language=${L10n.localeHttpTag}`;
    this.pushLegal(param);
  }
}
