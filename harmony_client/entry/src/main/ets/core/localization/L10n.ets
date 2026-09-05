import { util } from '@kit.ArkTS';
import { resourceManager } from '@kit.LocalizationKit';
import { JsonCodec } from '../../common/JsonTypes';

/**
 * 响应式语言状态（V2 观察）：
 * 切换语言时整体替换 currentMap/fallbackMap，所有在 build 中读取过
 * L10n 文案的组件（含已在页面栈中的页面）自动刷新，无需各自监听事件。
 */
@ObservedV2
export class L10nState {
  @Trace currentMap: Map<string, string> = new Map<string, string>();
  @Trace fallbackMap: Map<string, string> = new Map<string, string>();
}

/**
 * 本地化中心。
 * 语言包资源与 Flutter 端完全一致（resources/rawfile/locales/*.json，key 一一对应），
 * getter 内部通过 t(key) 查询，切换语言后立即生效；查不到时回退中文。
 */
export class L10n {
  private static locales: Map<string, Map<string, string>> = new Map();
  private static currentLocale: string = 'zh_CN';
  /** 响应式语言状态（build 中读取 t() 时建立观察依赖） */
  static readonly state: L10nState = new L10nState();
  /** 语言版本号，页面监听 localeChanged 事件后可据此刷新 */
  static localeVersion: number = 0;

  static readonly appName: string = 'NasCabOS';

  /** 启动时加载全部语言包（与 Flutter 非 Web 端策略一致） */
  static async init(rm: resourceManager.ResourceManager): Promise<void> {
    const codes: string[] = [
      'zh-cn', 'en-us', 'fr-fr', 'de-de', 'pt-br', 'ja-jp', 'ru-ru',
      'th-th', 'ko-kr', 'es-es', 'ar-ar', 'vi-vn', 'id-id'
    ];
    for (const code of codes) {
      try {
        const raw = await rm.getRawFileContent(`locales/${code}.json`);
        const text = L10n.decodeUtf8(raw);
        const map = JsonCodec.parseStr<Record<string, string>>(text);
        const inner = new Map<string, string>();
        const keys = Object.keys(map);
        for (const k of keys) {
          inner.set(k, map[k]);
        }
        L10n.locales.set(code.replace('-', '_'), inner);
      } catch (e) {
        console.error(`[L10N] load failed for ${code}: ${e}`);
      }
    }
    // 初始化响应式语言包（默认中文）
    L10n.setLocale(L10n.currentLocale);
  }

  private static decodeUtf8(raw: Uint8Array): string {
    const decoder = new util.TextDecoder('utf-8');
    return decoder.decodeToString(raw);
  }

  /** Flutter 风格 locale（zh_CN），内部统一使用下划线 */
  static setLocale(localeCode: string): void {
    if (localeCode && L10n.locales.has(localeCode.toLowerCase())) {
      L10n.currentLocale = localeCode;
    } else {
      L10n.currentLocale = 'zh_CN';
    }
    const lower = L10n.currentLocale.toLowerCase();
    // 整体替换观察字段 → 所有读取过文案的组件自动刷新
    L10n.state.currentMap = L10n.locales.get(lower) ?? new Map<string, string>();
    L10n.state.fallbackMap = L10n.locales.get('zh_cn') ?? new Map<string, string>();
    L10n.localeVersion++;
  }

  static get locale(): string {
    return L10n.currentLocale;
  }

  /** Web URL 的 language 参数，如 zh-CN（对齐 Flutter LegalUrls.languageQuery） */
  static get localeHttpTag(): string {
    const parts = L10n.currentLocale.split('_');
    return parts.length === 2 ? `${parts[0]}-${parts[1]}` : parts[0];
  }

  /** 查询翻译：当前语言 → 中文回退 → fallback → key */
  static t(key: string, fallback?: string, params?: Map<string, string>): string {
    // 通过 state 建立观察依赖（切换语言时整体替换，触发全局刷新）
    let value = L10n.state.currentMap.get(key);
    if (value === undefined && L10n.currentLocale.toLowerCase() !== 'zh_cn') {
      value = L10n.state.fallbackMap.get(key);
    }
    if (value === undefined) {
      value = fallback !== undefined ? fallback : key;
    }
    if (params) {
      params.forEach((v: string, k: string) => {
        value = value!.split(`@${k}`).join(v);
      });
    }
    return value;
  }

  // ===== 通用 =====
  static get networkFailure(): string { return L10n.t('network_failure', '网络请求失败，请检查服务器连接'); }
  static get serviceSessionExpired(): string { return L10n.t('auth_session_expired', '登录已过期，请重新登录'); }
  static get authLoginFailure(): string { return L10n.t('auth_login_failure', '登录失败'); }
  static get tip(): string { return L10n.t('tip', '提示'); }
  static get ok(): string { return L10n.t('ok', '确定'); }
  static get cancel(): string { return L10n.t('cancel', '取消'); }
  static get confirm(): string { return L10n.t('confirm', '确认'); }
  static get save(): string { return L10n.t('save', '保存'); }
  static get success(): string { return L10n.t('success', '成功'); }
  static get operationFailed(): string { return L10n.t('operation_failed', '操作失败'); }
  static get loading(): string { return L10n.t('loading', '加载中...'); }
  static get cancelled(): string { return L10n.t('cancelled', '已取消'); }
  static get setting(): string { return L10n.t('setting', '设置'); }
  static get edit(): string { return L10n.t('edit', '编辑'); }
  static get delete(): string { return L10n.t('delete', '删除'); }
  static get error(): string { return L10n.t('error', '错误'); }
  static get inputPlease(): string { return L10n.t('input_please', '请输入'); }
  static get language(): string { return L10n.t('player_subtitle_language', '语言'); }
  static get authTokenRefreshFailure(): string { return L10n.t('auth_token_refresh_failure', '令牌刷新失败'); }
  static get featureComingSoon(): string { return L10n.t('feature_coming_soon', '功能开发中'); }
  static get connecting(): string { return L10n.t('editor_status_connecting', '连接中...'); }

  // ===== 服务器列表 / 添加 =====
  static get serverListTitle(): string { return L10n.t('server_listTitle', '登录NasCabOS服务器'); }
  static get addServer(): string { return L10n.t('server_add', '添加服务器'); }
  static get discoveredServers(): string { return L10n.t('server_scanned', '发现的服务器'); }
  static get savedServers(): string { return L10n.t('server_saved', '已保存的服务器'); }
  static get password(): string { return L10n.t('password', '密码'); }
  static get username(): string { return L10n.t('username', '用户名'); }
  static get login(): string { return L10n.t('auth_login_button', '登录'); }
  static get pairCode(): string { return L10n.t('service_remote_access_pair_code_label', '配对码'); }
  static get serverUrl(): string { return L10n.t('server_url', '服务器地址'); }
  static get twofaCode(): string { return L10n.t('user_mgmt_2fa_code_label', '验证码'); }
  static get twofaTitle(): string { return L10n.t('auth_2fa_title', '两步验证'); }
  static get requirePasswordEveryLogin(): string { return L10n.t('server_need_input_password_every_time', '每次登录输入密码'); }
  static get serverNeedInputPasswordEveryTime(): string { return L10n.t('server_need_input_password_every_time', '每次登录都需要输入密码'); }
  static get serverSaved(): string { return L10n.t('server_saved', '已保存的服务器'); }
  static get serverScanned(): string { return L10n.t('server_scanned', '自动发现服务器'); }

  /** 语言 URL 参数别名（如 zh-CN），对齐旧字段 currentLanguageCode */
  static get currentLanguageCode(): string {
    return L10n.localeHttpTag;
  }

  // ===== home 模块 =====
  static get homeUnknown(): string { return L10n.t('home_unknown', '未知'); }
  static get homeServerDefault(): string { return L10n.t('home_server_default', '服务器'); }
  static get homeNoMessage(): string { return L10n.t('home_no_message', '暂无最新消息'); }
  static get homeStatusLogout(): string { return L10n.t('service_nascab_logout', '退出登录'); }
  static get homeChangeWallpaper(): string { return L10n.t('home_desktop_change_wallpaper', '更换壁纸'); }
  static get homeQuickUpload(): string { return L10n.t('home_quick_upload', '快速上传'); }
  static get homeDownloadCenter(): string { return L10n.t('home_download_center', '下载中心'); }
  static get homePhotoBackup(): string { return L10n.t('home_photo_backup', '相册备份'); }
  static get searchApps(): string { return L10n.t('home_search_apps_hint', '搜索应用'); }
  static get serverNameLabel(): string { return L10n.t('server_name', '服务器名称'); }
  static get serverPlatformLabel(): string { return L10n.t('server_platform', '服务器平台'); }
  static get serverConnectChannel(): string { return L10n.t('server_connect_channel', '连接通道'); }
  static get serverIdLabel(): string { return L10n.t('server_id', '服务器ID'); }
  static get homeWallpaperTitle(): string { return L10n.t('home_wallpaper_title', '选择壁纸'); }
  static get homeWallpaperRandom(): string { return L10n.t('home_wallpaper_random', '随机'); }
  static get homeWallpaperFixed(): string { return L10n.t('home_wallpaper_fixed', '固定'); }
  static get homeWallpaperApply(): string { return L10n.t('home_wallpaper_apply', '应用'); }
  static get homeWallpaperCancel(): string { return L10n.t('cancel', '取消'); }
  static get homeWallpaperSaveSuccess(): string { return L10n.t('home_wallpaper_save_success', '壁纸已更新'); }
  static get homeWallpaperSaveFailed(): string { return L10n.t('home_wallpaper_save_failed', '壁纸更新失败'); }
  static get homeWallpaperUpload(): string { return L10n.t('home_wallpaper_upload', '上传壁纸'); }
  static get homeWallpaperUploading(): string { return L10n.t('home_wallpaper_uploading', '正在上传壁纸'); }
  static get homeWallpaperUploadSuccess(): string { return L10n.t('home_wallpaper_upload_success', '壁纸上传成功'); }
  static get homeWallpaperUploadFailed(): string { return L10n.t('home_wallpaper_upload_failed', '壁纸上传失败'); }
  static get homeWallpaperDeleteTitle(): string { return L10n.t('home_wallpaper_delete_confirm_title', '删除壁纸'); }
  static get homeWallpaperDeleteFailed(): string { return L10n.t('delete_failed', '删除失败'); }
  static get homeWallpaperDeleteSuccess(): string { return L10n.t('delete_success', '删除成功'); }

  static homeWallpaperDeleteConfirm(name: string): string {
    return L10n.t('home_wallpaper_delete_confirm_content', '确定删除壁纸“@name”吗？', L10n.paramsOf('name', name));
  }

  /** 应用显示名，对应 Flutter 'app_$app'.tr */
  static appDisplayName(appId: string): string {
    if (appId === 'transmission') {
      return 'Transmission';
    }
    return L10n.t(`app_${appId}`, appId);
  }

  // ===== auth / 服务器管理 =====
  static get serverLocalServer(): string { return L10n.t('server_localServer', '本机'); }
  static get serverAddByPairCodeTitle(): string { return L10n.t('server_add_by_pair_code_title', '使用配对码添加服务器'); }
  static get serverAddByPairCodeContent(): string { return L10n.t('server_add_by_pair_code_content', '请输入配对码'); }
  static get serverPairCodeScanQr(): string { return L10n.t('server_pair_code_scan_qr', '扫描二维码'); }
  static get serverPairCodeScanInvalid(): string { return L10n.t('server_pair_code_scan_invalid', '匹配码无效'); }
  static get serverPairCodeHowTitle(): string { return L10n.t('server_pair_code_how_link', '如何获取配对码?'); }
  static get serverPairCodeHowLink(): string { return L10n.t('server_pair_code_how_link', '如何获取配对码?'); }
  static get serverPairCodeHowContent(): string {
    return L10n.t('server_pair_code_how_content', '登录后，服务->远程访问 中开启，即可获得配对码，使用配对码可以随时随地找到您的主机');
  }
  static get serverPairCodeEmpty(): string { return L10n.t('server_pair_code_empty', '配对码不能为空'); }
  static get serverPairCodeInvalid(): string { return L10n.t('server_pair_code_invalid', '验证码不正确或服务端不在线'); }
  static get serverPairCodeLabel(): string { return L10n.t('service_remote_access_pair_code_label', '配对码'); }
  static get serverConnecting(): string { return L10n.t('server_connecting', '正在连接...'); }
  static get serverLoginPasswordRequired(): string { return L10n.t('server_login_password_required', '需要输入密码'); }
  static get serverLoginPasswordRequiredMessage(): string {
    return L10n.t('server_login_password_required_message', '该服务器已设置为每次登录都需要输入密码，请先输入密码再登录');
  }
  static get serverEditPairCodeTitle(): string { return L10n.t('server_menu_edit_pair_code', '修改配对码'); }
  static get serverEditPairCodeContent(): string { return L10n.t('server_edit_pair_code_content', '请输入新的配对码'); }
  static get serverListExitTitle(): string { return L10n.t('server_add_exit_title', '退出确认'); }
  static get serverListExitContent(): string { return L10n.t('server_list_exit_content', '确定要退出应用吗？'); }
  static get serverConnectFail(): string { return L10n.t('server_connect_fail', '无法连接到服务器，请检查网络连接或服务器地址'); }
  static get serverInit(): string { return L10n.t('server_init', '服务器初始化'); }
  static get serverInitContent(): string {
    return L10n.t('server_init_content', '此服务器尚未初始化，点击【确定】创建管理员，管理员账号保存在您的服务器磁盘上，非网络账号。');
  }
  static get serverAddNameLabel(): string { return L10n.t('server_name', '服务器名称'); }
  static get serverAdd(): string { return L10n.t('server_add', '添加服务器'); }
  static get serverAddNameRequired(): string { return L10n.t('server_add_name_required', '请输入服务器名称'); }
  static get serverAddProtocol(): string { return L10n.t('server_add_protocol', '协议:'); }
  static get serverAddAddressLabel(): string { return L10n.t('server_add_address_label', '服务器地址 (含端口)'); }
  static get serverAddAddressHint(): string { return L10n.t('server_add_address_hint', '例如: 192.168.1.100:9000'); }
  static get serverAddAddressRequired(): string { return L10n.t('server_add_address_required', '请输入服务器地址'); }
  static get serverAddAddressInvalid(): string { return L10n.t('server_add_address_invalid', '请输入有效的服务器地址'); }
  static get serverAddUsernameRequired(): string { return L10n.t('server_add_username_required', '请输入用户名'); }
  static get serverAddPasswordRequired(): string { return L10n.t('server_add_password_required', '请输入密码'); }
  static get serverAddButton(): string { return L10n.t('server_add', '添加服务器'); }
  static get serverAddInvalidServer(): string { return L10n.t('server_add_invalid_server', '该服务器不是有效的NasCab服务器，请检查服务器地址是否正确'); }
  static get serverAddFailure(): string { return L10n.t('auth_login_failure', '登录失败'); }
  static get serverAddSuccess(): string { return L10n.t('service_nascab_logged_in', '登录成功'); }
  static get serverAddSuccessMessage(): string { return L10n.t('server_add_success_message', '服务器已成功添加'); }
  static get serverAddExitTitle(): string { return L10n.t('server_add_exit_title', '退出确认'); }
  static get serverAddExitContent(): string { return L10n.t('server_add_exit_content', '确定要退出添加服务器吗？'); }
  static get serverAddSaveFailure(): string { return L10n.t('server_add_save_failure', '保存服务器信息失败，请重试'); }

  static get authLoginLoading(): string { return L10n.t('auth_login_loading', '正在登录'); }
  static get authLoginButton(): string { return L10n.t('auth_login_button', '登录'); }
  static get authPasswordError(): string { return L10n.t('auth_password_error', '密码错误'); }
  static get authPasswordErrorMessage(): string { return L10n.t('auth_password_error_message', '密码错误，请重新输入密码'); }
  static get authPasswordHint(): string { return L10n.t('server_add_password_required', '请输入密码'); }
  static get authPasswordTooShort(): string { return L10n.t('auth_password_too_short', '密码长度不能小于6位'); }
  static get authWelcomeTitle(): string { return L10n.t('auth_welcome_title', '欢迎使用NasCab OS'); }
  static get authPairCodeLabel(): string { return L10n.t('service_remote_access_pair_code_label', '配对码'); }
  static get authPairCodeConnect(): string { return L10n.t('auth_pair_code_connect', '连接'); }
  static get authForgotPassword(): string { return L10n.t('auth_forgot_password', '找回密码'); }
  static get authPrivacyPolicy(): string { return L10n.t('auth_privacy_policy', '隐私政策'); }
  static get authUserAgreement(): string { return L10n.t('auth_user_agreement', '用户协议'); }
  static get authHelp(): string { return L10n.t('help', '帮助'); }
  static get auth2faTitle(): string { return L10n.t('auth_2fa_title', '双重验证'); }
  static get auth2faCodeLabel(): string { return L10n.t('auth_2fa_code_label', '输入验证器中显示的验证码'); }
  static get auth2faCodeHint(): string { return L10n.t('auth_2fa_code_hint', '请输入6位验证码'); }
  static get auth2faCannotVerify(): string { return L10n.t('auth_2fa_cannot_verify', '无法验证?'); }
  static get auth2faCannotVerifyHint(): string {
    return L10n.t('auth_2fa_cannot_verify_hint', '当您的2FA无法验证，管理员账号可以通过服务端界面进行重置，普通用户联系管理员进行重置');
  }
  static get auth2faVerifyButton(): string { return L10n.t('auth_2fa_verify_button', '验证并登录'); }
  static get auth2faCodeRequired(): string { return L10n.t('auth_2fa_code_required', '请输入2FA验证码'); }
  static get authRecoverInfoFailure(): string { return L10n.t('auth_recover_info_failure', '获取找回密码信息失败'); }
  static get authRecoverTip(): string {
    return L10n.t('auth_recover_tip', '管理员无法通过密保问题找回时，可以在服务端界面修改，普通用户无法找回时，可以联系管理员修改。');
  }
  static get authRecoverSecurityQuestionLabel(): string { return L10n.t('auth_recover_security_question_label', '密保问题'); }

  static get adminCreateTitle(): string { return L10n.t('admin_create_title', '创建管理员'); }
  static get adminCreateButton(): string { return L10n.t('admin_create_title', '创建管理员'); }
  static get adminCreateFailure(): string { return L10n.t('admin_create_failure', '创建失败'); }
  static get adminCreateSuccess(): string { return L10n.t('admin_create_success', '管理员账户已成功创建'); }
  static get adminCreateSuccessMessage(): string {
    return L10n.t('admin_create_success_message', '创建成功，此账号保存在您的NasCab服务器磁盘上，非联网账号，请您牢记。');
  }
  static get adminCreateSecurityQuestionLabel(): string { return L10n.t('admin_create_security_question_label', '选择密保问题'); }
  static get adminCreateSecurityQuestionOption1(): string { return L10n.t('admin_create_security_question_option1', '我的手机号码是什么?'); }
  static get adminCreateSecurityQuestionOption2(): string { return L10n.t('admin_create_security_question_option2', '我的真实姓名是什么?'); }
  static get adminCreateSecurityQuestionOption3(): string { return L10n.t('admin_create_security_question_option3', '我的身份证号码是什么?'); }
  static get adminCreateSecurityQuestionCustom(): string { return L10n.t('admin_create_security_question_custom', '自定义问题'); }
  static get adminCreateSecurityQuestionRequired(): string { return L10n.t('admin_create_security_question_required', '请选择或输入密保问题'); }
  static get adminCreateSecurityAnswerLabel(): string { return L10n.t('admin_create_security_answer_label', '密保答案'); }
  static get adminCreateSecurityAnswerRequired(): string { return L10n.t('admin_create_security_answer_required', '请输入密保答案'); }

  static get recoverTitle(): string { return L10n.t('auth_forgot_password', '找回密码'); }
  static get recoverButton(): string { return L10n.t('auth_forgot_password', '找回密码'); }
  static get recoverFailure(): string { return L10n.t('recover_failure', '找回失败'); }
  static get recoverSuccess(): string { return L10n.t('recover_success', '找回成功'); }
  static get recoverSuccessMessage(): string { return L10n.t('recover_success_message', '管理员密码已更新，请使用新密码登录'); }
  static get recoverAnswerLabel(): string { return L10n.t('admin_create_security_answer_label', '密保答案'); }
  static get recoverAnswerRequired(): string { return L10n.t('admin_create_security_answer_required', '请输入密保答案'); }
  static get recoverNewPasswordLabel(): string { return L10n.t('recover_new_password_label', '新密码'); }

  static get privacyConsentTitle(): string { return L10n.t('privacy_consent_title', '隐私政策提示'); }
  static get privacyConsentMessage1(): string { return L10n.t('privacy_consent_message_1', '为保障您的权益，请在使用前阅读《用户协议》和《隐私政策》。'); }
  static get privacyConsentMessage2(): string { return L10n.t('privacy_consent_message_2', '我们将依法收集、使用必要信息以提供服务。'); }
  static get privacyConsentMessage3(): string { return L10n.t('privacy_consent_message_3', '点击“同意”即表示您已阅读并同意相关条款；不同意请退出应用。'); }
  static get privacyConsentAgree(): string { return L10n.t('privacy_consent_agree', '同意'); }
  static get privacyConsentDisagree(): string { return L10n.t('privacy_consent_disagree', '不同意'); }

  // ===== settings 模块（与 Flutter settings_view.dart 一致） =====
  static get settingsTheme(): string { return L10n.t('settings_theme', '主题设置'); }
  static get settingsThemeCustomizeAppearance(): string { return L10n.t('settings_theme_customize_appearance', '自定义应用外观'); }
  static get settingsThemeTitle(): string { return L10n.t('settings_theme_title', '主题模式'); }
  static get settingsThemeLightMode(): string { return L10n.t('settings_theme_light_mode', '浅色模式'); }
  static get settingsThemeDarkMode(): string { return L10n.t('settings_theme_dark_mode', '深色模式(推荐)'); }
  static get settingsThemeSystemMode(): string { return L10n.t('settings_theme_system_mode', '跟随系统'); }
  static get settingsLanguage(): string { return L10n.t('settings_language', '语言设置'); }
  static get settingsLanguageSwitchAppLanguage(): string { return L10n.t('settings_language_switch_app_language', '切换应用语言'); }
  static get settingsLanguageDialogTitle(): string { return L10n.t('settings_language_dialog_title', '选择语言'); }
  static get settingsLegalDocumentSubtitle(): string { return L10n.t('settings_legal_document_subtitle', '查看完整法律文档'); }
  static get settingsClearCache(): string { return L10n.t('settings_clear_cache', '清理缓存'); }
  static get settingsClearCacheDescription(): string { return L10n.t('settings_clear_cache_description', '清理应用图片缓存'); }
  static get settingsClearCacheDialogTitle(): string { return L10n.t('settings_clear_cache_dialog_title', '清理缓存'); }
  static get settingsClearCacheDialogContent(): string { return L10n.t('settings_clear_cache_dialog_content', '确定要清理缓存吗？'); }
  static get settingsClearCacheSuccess(): string { return L10n.t('settings_clear_cache_success', '缓存清理成功'); }
  static get settingsRestartService(): string { return L10n.t('settings_restart_service', '重启服务'); }
  static get settingsRestartServiceDescription(): string { return L10n.t('settings_restart_service_description', '重启NasCab后端服务'); }
  static get settingsRestartServiceDialogTitle(): string { return L10n.t('settings_restart_service_dialog_title', '重启服务'); }
  static get settingsRestartServiceDialogContent(): string { return L10n.t('settings_restart_service_dialog_content', '确定要重启服务吗？'); }
  static get settingsRestartServiceRequested(): string { return L10n.t('settings_restart_service_requested', '重启请求已发送'); }
  static get settingsAppVersion(): string { return L10n.t('settings_app_version', '应用版本'); }
  static get settingsUpdateAvailable(): string { return L10n.t('settings_update_available', '有可用更新'); }
  static get settingsServerConfigTitle(): string { return L10n.t('settings_server_config_title', '服务端配置'); }
  static get settingsServerHttpPort(): string { return L10n.t('settings_server_http_port', 'HTTP端口'); }
  static get settingsServerHttpsPort(): string { return L10n.t('settings_server_https_port', 'HTTPS端口'); }
  static get settingsServerApiCount(): string { return L10n.t('settings_server_api_count', 'API进程数量'); }
  static get settingsServerRestartRequired(): string { return L10n.t('settings_server_restart_required', '需要重启服务端后生效'); }
  static get settingsServerHttpPortInvalid(): string { return L10n.t('settings_server_http_port_invalid', 'HTTP端口无效'); }
  static get settingsServerHttpsPortInvalid(): string { return L10n.t('settings_server_https_port_invalid', 'HTTPS端口无效'); }
  static get settingsServerApiCountInvalid(): string { return L10n.t('settings_server_api_count_invalid', 'API进程数量无效'); }
  static get settingsServerApiCountTooLow(): string { return L10n.t('settings_server_api_count_too_low', 'API进程数量不能低于2'); }
  static get settingsCustomHostnameTitle(): string { return L10n.t('settings_custom_hostname_title', '自定义主机名'); }
  static get settingsCustomHostnameFieldLabel(): string { return L10n.t('settings_custom_hostname_field_label', '自定义主机名'); }
  static get settingsCustomHostnameInvalid(): string { return L10n.t('settings_custom_hostname_invalid', '自定义主机名不能超过10个字符'); }
  static get settingsPersonalizationTitle(): string { return L10n.t('settings_personalization_title', '个性化设置'); }
  static get settingsPersonalizationWelcomeLabel(): string { return L10n.t('settings_personalization_welcome_label', '欢迎语'); }
  static get settingsPersonalizationWelcomeInvalid(): string { return L10n.t('settings_personalization_welcome_invalid', '欢迎语不能为空'); }
  static get monitorCores(): string { return L10n.t('monitor_cores', '核心'); }

  static settingsServerApiCountTooHigh(cores: string): string {
    return L10n.t('settings_server_api_count_too_high', 'API进程数量不能超过CPU核心数(@cores)', L10n.paramsOf('cores', cores));
  }

  static paramsOf(k1: string, v1: string): Map<string, string> {
    const map = new Map<string, string>();
    map.set(k1, v1);
    return map;
  }

  static serverPairCodeDisplay(code: string): string {
    return `${L10n.pairCode}：${code}`;
  }

  static authConnectedHost(host: string): string {
    return `已连接主机：${host}`;
  }

  static serverDeleteConfirmMessage(serverName: string): string {
    return `确定要删除服务器 ${serverName} 吗？`;
  }

  static serverStatusCheckFailedWithError(error: string): string {
    return `服务器状态检查失败: ${error}`;
  }
}
