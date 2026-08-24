import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/languages/language_service.dart';
import '../../../core/theme/theme_manager.dart';
import '../../../core/api/base_api_service.dart';
import '../../../core/api/api_controller.dart';
import '../../../core/user/current_user_controller.dart';
import '../../base/components/custom_container.dart';
import '../../base/components/custom_divider.dart';
import '../../base/components/custom_extended_image.dart';
import '../../base/views/app_base_page.dart';
import '../../../utils/toast_util.dart';
import '../../../utils/device_utils.dart';
import '../../../utils/update_check_helper.dart';
import '../../../utils/legal_document_opener.dart';
import '../../home/service/appearance_api_service.dart';
import '../../auth/service/server_storage_service.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _api = _ApiSettingApiService();
  final _httpPortCtrl = TextEditingController();
  final _httpsPortCtrl = TextEditingController();
  final _apiCountCtrl = TextEditingController();
  final _welcomeCtrl = TextEditingController();
  final _hostnameCtrl = TextEditingController();
  static const int _kDefaultHttpPort = 6789;
  static const int _kDefaultHttpsPort = 6799;
  static const int _kDefaultApiCount = 2;
  static const double _kTopSafeSpacing = 40;
  int? _cpuCores;
  bool _loadingConfig = false;
  bool _saving = false;
  bool _savingWelcome = false;
  bool _savingHostname = false;
  bool _restartingService = false;
  bool _loadingCacheSize = false;
  int? _cacheSizeBytes;
  String? _appVersion;
  bool _hasUpdate = false;
  String? _updateOpenUrl;

  @override
  void initState() {
    super.initState();
    _httpPortCtrl.text = _kDefaultHttpPort.toString();
    _httpsPortCtrl.text = _kDefaultHttpsPort.toString();
    _apiCountCtrl.text = _kDefaultApiCount.toString();
    _welcomeCtrl.text = 'auth_welcome_title'.tr;
    if (CurrentUserController.instance.isAdmin) {
      _loadConfig();
      _loadCacheSize();
    }
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _appVersion = info.version);
        _initUpdateCheck();
      }
    } catch (_) {}
  }

  /// 先根据缓存显示是否有更新，再在后台执行检测（24h 内可能不请求）
  Future<void> _initUpdateCheck() async {
    try {
      final info = await UpdateCheckHelper.getUpdateInfoIfNewer(_appVersion);
      if (!mounted) return;
      setState(() {
        _hasUpdate = info != null;
        _updateOpenUrl = info?.openUrl;
      });
      _checkUpdateInBackground();
    } catch (_) {}
  }

  Future<void> _checkUpdateInBackground() async {
    try {
      final hasUpdate = await UpdateCheckHelper.checkForUpdate(_appVersion);
      if (!mounted) return;
      final info = await UpdateCheckHelper.getUpdateInfoIfNewer(_appVersion);
      setState(() {
        _hasUpdate = hasUpdate && info != null;
        _updateOpenUrl = info?.openUrl;
      });
    } catch (_) {}
  }

  Future<void> _openUpdateUrl() async {
    final url = _updateOpenUrl?.trim();
    if (url == null || url.isEmpty) return;
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _httpPortCtrl.dispose();
    _httpsPortCtrl.dispose();
    _apiCountCtrl.dispose();
    _welcomeCtrl.dispose();
    _hostnameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCacheSize() async {
    if (DeviceUtils.isWeb) return;
    if (_loadingCacheSize) return;
    setState(() => _loadingCacheSize = true);
    try {
      final bytes = await CustomExtendedImage.getCacheSizeBytes();
      if (!mounted) return;
      setState(() => _cacheSizeBytes = bytes);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingCacheSize = false);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double v = bytes.toDouble();
    int i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    final s = i <= 1 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '$s ${units[i]}';
  }

  Future<void> _loadConfig() async {
    if (_loadingConfig) return;
    setState(() => _loadingConfig = true);
    try {
      final resp = await _api.getConfig();
      if (!resp.success) {
        ToastUtil.show(resp.message ?? 'operation_failed'.tr);
        return;
      }
      final data = (resp.data ?? const {}).cast<String, dynamic>();
      final httpPort = data['httpPort'];
      final httpsPort = data['httpsPort'];
      final apiCount = data['expressApiCount'];
      final welcomeText = data['welcomeText'];
      final customHostname = data['customHostname'];
      final cpuCores = data['cpuCores'];
      setState(() {
        _cpuCores = cpuCores is int ? cpuCores : int.tryParse('$cpuCores');
      });
      _httpPortCtrl.text = '${httpPort ?? _kDefaultHttpPort}';
      _httpsPortCtrl.text = '${httpsPort ?? _kDefaultHttpsPort}';
      _apiCountCtrl.text = '${apiCount ?? _kDefaultApiCount}';
      if (welcomeText is String && welcomeText.trim().isNotEmpty) {
        _welcomeCtrl.text = welcomeText.trim();
      } else {
        _welcomeCtrl.text = 'auth_welcome_title'.tr;
      }
      if (customHostname is String && customHostname.trim().isNotEmpty) {
        _hostnameCtrl.text = customHostname.trim();
      } else {
        _hostnameCtrl.text = '';
      }
    } finally {
      if (mounted) setState(() => _loadingConfig = false);
    }
  }

  int? _parseInt(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    return int.tryParse(s);
  }

  Future<void> _saveConfig() async {
    if (_saving || _savingWelcome || _savingHostname) return;
    final httpPort = _parseInt(_httpPortCtrl.text);
    final httpsPort = _parseInt(_httpsPortCtrl.text);
    final apiCount = _parseInt(_apiCountCtrl.text);

    if (httpPort == null || httpPort <= 0 || httpPort > 65535) {
      ToastUtil.show('settings_server_http_port_invalid'.tr);
      return;
    }
    if (httpsPort == null || httpsPort <= 0 || httpsPort > 65535) {
      ToastUtil.show('settings_server_https_port_invalid'.tr);
      return;
    }
    if (apiCount == null) {
      ToastUtil.show('settings_server_api_count_invalid'.tr);
      return;
    }
    if (apiCount < 2) {
      ToastUtil.show('settings_server_api_count_too_low'.tr);
      return;
    }
    final cores = _cpuCores;
    if (cores != null && apiCount > cores) {
      ToastUtil.show(
        'settings_server_api_count_too_high'.trParams({
          'cores': cores.toString(),
        }),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final resp = await _api.saveConfig(
        httpPort: httpPort,
        httpsPort: httpsPort,
        expressApiCount: apiCount,
      );
      if (!resp.success) {
        ToastUtil.show(resp.message ?? 'operation_failed'.tr);
        return;
      }
      ToastUtil.show('settings_server_restart_required'.tr);
      await _loadConfig();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveWelcome() async {
    if (_saving || _savingWelcome || _savingHostname) return;
    final text = _welcomeCtrl.text.trim();
    if (text.isEmpty) {
      ToastUtil.show('settings_personalization_welcome_invalid'.tr);
      return;
    }
    setState(() => _savingWelcome = true);
    try {
      final resp = await _api.saveWelcome(welcomeText: text);
      if (!resp.success) {
        ToastUtil.show(resp.message ?? 'operation_failed'.tr);
        return;
      }
      ToastUtil.show(resp.message ?? 'success'.tr);
      await _loadConfig();
    } finally {
      if (mounted) setState(() => _savingWelcome = false);
    }
  }

  Future<void> _saveHostname() async {
    if (_saving || _savingWelcome || _savingHostname) return;
    final text = _hostnameCtrl.text.trim();
    if (text.isNotEmpty && text.length > 10) {
      ToastUtil.show('settings_custom_hostname_invalid'.tr);
      return;
    }
    setState(() => _savingHostname = true);
    try {
      final resp = await AppearanceApiService.instance.setCustomHostname(
        customHostname: text,
      );
      if (!resp.success) {
        ToastUtil.show(resp.message ?? 'operation_failed'.tr);
        return;
      }
      final stored = text.isEmpty ? null : text;
      ApiController.instance.setSessionCustomHostname(stored);
      if (!DeviceUtils.isWeb) {
        final user = CurrentUserController.instance.current;
        await ServerStorageService.updateServerCustomHostnameForSession(
          serverId: ApiController.instance.state.serverId,
          username: (user?.username ?? '').trim(),
          customHostname: stored,
        );
      }
      ToastUtil.show(resp.message ?? 'success'.tr);
      await _loadConfig();
    } finally {
      if (mounted) setState(() => _savingHostname = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageService = LanguageService.to;
    final isAdmin = CurrentUserController.instance.isAdmin;
    final isMobile = DeviceUtils.isMobile || DeviceUtils.isPhone(context);

    final content = SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isAdmin) _buildServerConfigCard(context),
            if (isAdmin) const SizedBox(height: 16),
            if (isAdmin) _buildCustomHostnameCard(context),
            if (isAdmin) const SizedBox(height: 16),
            if (isAdmin) _buildPersonalizationCard(context),
            if (isAdmin) const SizedBox(height: 16),
            CustomContainer(
              child: Column(
                children: [
                  _buildSettingsItem(
                    context,
                    'settings_theme'.tr,
                    'settings_theme_customize_appearance'.tr,
                    Icons.palette_outlined,
                    () => _showThemeDialog(context),
                  ),
                  const CustomDivider(),
                  _buildSettingsItem(
                    context,
                    'settings_language'.tr,
                    'settings_language_switch_app_language'.tr,
                    Icons.language_outlined,
                    () => _showLanguageDialog(context, languageService),
                  ),
                  const CustomDivider(),
                  _buildSettingsItem(
                    context,
                    'auth_user_agreement'.tr,
                    'settings_legal_document_subtitle'.tr,
                    Icons.article_outlined,
                    () => LegalDocumentOpener.open(
                      context,
                      url: LegalUrls.agreementUrl(),
                      title: 'auth_user_agreement'.tr,
                    ),
                  ),
                  const CustomDivider(),
                  _buildSettingsItem(
                    context,
                    'auth_privacy_policy'.tr,
                    'settings_legal_document_subtitle'.tr,
                    Icons.privacy_tip_outlined,
                    () => LegalDocumentOpener.open(
                      context,
                      url: LegalUrls.privacyUrl(),
                      title: 'auth_privacy_policy'.tr,
                    ),
                  ),
                  if (isAdmin && !DeviceUtils.isWeb) ...[
                    const CustomDivider(),
                    _buildSettingsItem(
                      context,
                      'settings_clear_cache'.tr,
                      '${'settings_clear_cache_description'.tr}${_cacheSizeBytes == null ? '' : ' (${_formatBytes(_cacheSizeBytes!)})'}',
                      Icons.cleaning_services_outlined,
                      () => _clearCache(context),
                      trailing: _loadingCacheSize
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                    ),
                  ],
                  if (isAdmin) ...[
                    const CustomDivider(),
                    _buildSettingsItem(
                      context,
                      'settings_restart_service'.tr,
                      'settings_restart_service_description'.tr,
                      Icons.restart_alt_outlined,
                      () => _restartService(context),
                      trailing: _restartingService
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${'settings_app_version'.tr}: V${_appVersion ?? '--'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  if (_hasUpdate && _updateOpenUrl != null) ...[
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: _openUpdateUrl,
                      child: Text('settings_update_available'.tr),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (isMobile) {
      return AppBasePage(title: 'setting'.tr, body: content);
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: _kTopSafeSpacing),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  Widget _buildServerConfigCard(BuildContext context) {
    final theme = Theme.of(context);
    final disabled =
        _loadingConfig || _saving || _savingWelcome || _savingHostname;
    final cores = _cpuCores;
    final coreSuffix = cores == null ? '' : ' / ${'monitor_cores'.tr}: $cores';

    return CustomContainer(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'settings_server_config_title'.tr,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 520;
                final httpField = TextField(
                  controller: _httpPortCtrl,
                  enabled: !disabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: false,
                    decimal: false,
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'settings_server_http_port'.tr,
                    border: const OutlineInputBorder(),
                    suffixIcon: TextButton(
                      onPressed: disabled ? null : _saveConfig,
                      child: Text('save'.tr),
                    ),
                  ),
                );
                final httpsField = TextField(
                  controller: _httpsPortCtrl,
                  enabled: !disabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: false,
                    decimal: false,
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'settings_server_https_port'.tr,
                    border: const OutlineInputBorder(),
                    suffixIcon: TextButton(
                      onPressed: disabled ? null : _saveConfig,
                      child: Text('save'.tr),
                    ),
                  ),
                );

                if (isNarrow) {
                  return Column(
                    children: [
                      httpField,
                      const SizedBox(height: 12),
                      httpsField,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: httpField),
                    const SizedBox(width: 12),
                    Expanded(child: httpsField),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiCountCtrl,
              enabled: !disabled,
              keyboardType: const TextInputType.numberWithOptions(
                signed: false,
                decimal: false,
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: '${'settings_server_api_count'.tr}$coreSuffix',
                border: const OutlineInputBorder(),
                suffixIcon: TextButton(
                  onPressed: disabled ? null : _saveConfig,
                  child: Text('save'.tr),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomHostnameCard(BuildContext context) {
    final theme = Theme.of(context);
    final disabled =
        _loadingConfig || _saving || _savingWelcome || _savingHostname;
    return CustomContainer(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'settings_custom_hostname_title'.tr,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hostnameCtrl,
              enabled: !disabled,
              maxLength: 10,
              decoration: InputDecoration(
                labelText: 'settings_custom_hostname_field_label'.tr,
                border: const OutlineInputBorder(),
                counterText: '',
                suffixIcon: TextButton(
                  onPressed: disabled ? null : _saveHostname,
                  child: Text('save'.tr),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalizationCard(BuildContext context) {
    final theme = Theme.of(context);
    final disabled =
        _loadingConfig || _saving || _savingWelcome || _savingHostname;
    return CustomContainer(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'settings_personalization_title'.tr,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _welcomeCtrl,
              enabled: !disabled,
              decoration: InputDecoration(
                labelText: 'settings_personalization_welcome_label'.tr,
                border: const OutlineInputBorder(),
                suffixIcon: TextButton(
                  onPressed: disabled ? null : _saveWelcome,
                  child: Text('save'.tr),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsItem(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap, {
    Widget? trailing,
  }) {
    final theme = Theme.of(context);

    return ListTile(
      leading: Icon(icon),
      title: Text(
        title,
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
      trailing:
          trailing ??
          Icon(
            Icons.arrow_forward_ios_outlined,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            size: 16,
          ),
      onTap: onTap,
    );
  }

  void _showThemeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        final currentThemeMode = ThemeManager().getThemeMode();
        return AlertDialog(
          title: Text('settings_theme_title'.tr),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.light_mode_outlined),
                title: Text('settings_theme_light_mode'.tr),
                trailing: currentThemeMode == ThemeMode.light
                    ? const Icon(Icons.check_outlined)
                    : null,
                onTap: () async {
                  Get.changeThemeMode(ThemeMode.light);
                  await ThemeManager().saveThemeMode(ThemeMode.light);
                  Get.back();
                },
              ),
              ListTile(
                leading: const Icon(Icons.dark_mode_outlined),
                title: Text('settings_theme_dark_mode'.tr),
                trailing: currentThemeMode == ThemeMode.dark
                    ? const Icon(Icons.check_outlined)
                    : null,
                onTap: () async {
                  Get.changeThemeMode(ThemeMode.dark);
                  await ThemeManager().saveThemeMode(ThemeMode.dark);
                  Get.back();
                },
              ),
              ListTile(
                leading: const Icon(Icons.phone_android_outlined),
                title: Text('settings_theme_system_mode'.tr),
                trailing: currentThemeMode == ThemeMode.system
                    ? const Icon(Icons.check_outlined)
                    : null,
                onTap: () async {
                  Get.changeThemeMode(ThemeMode.system);
                  await ThemeManager().saveThemeMode(ThemeMode.system);
                  Get.back();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showLanguageDialog(
    BuildContext context,
    LanguageService languageService,
  ) {
    final languages = LanguageService.getFullLanguageOptions();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('settings_language_dialog_title'.tr),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: languages.map((option) {
              return ListTile(
                title: Text(option.label),
                trailing: languageService.currentLocale == option.value
                    ? const Icon(Icons.check_outlined)
                    : null,
                onTap: () {
                  languageService.changeLanguage(option.value);
                  Get.back();
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _clearCache(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('settings_clear_cache_dialog_title'.tr),
        content: Text('settings_clear_cache_dialog_content'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ToastUtil.show('settings_clear_cache_success'.tr);
              // 后台执行清理，避免阻塞界面
              _clearCacheInBackground();
            },
            child: Text('confirm'.tr),
          ),
        ],
      ),
    );
  }

  /// 在后台执行缓存清理，不阻塞 UI
  Future<void> _clearCacheInBackground() async {
    try {
      await CustomExtendedImage.clearCache();
      if (mounted) await _loadCacheSize();
      if (mounted) ToastUtil.show('settings_clear_cache_success'.tr);
    } catch (_) {
      if (mounted) ToastUtil.show('operation_failed'.tr);
    }
  }

  void _restartService(BuildContext context) {
    if (_restartingService) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('settings_restart_service_dialog_title'.tr),
        content: Text('settings_restart_service_dialog_content'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _restartingService = true);
              try {
                final resp = await _api.restartService();
                if (!resp.success) {
                  ToastUtil.show(resp.message ?? 'operation_failed'.tr);
                  return;
                }
                ToastUtil.show('settings_restart_service_requested'.tr);
              } finally {
                if (mounted) setState(() => _restartingService = false);
              }
            },
            child: Text('confirm'.tr),
          ),
        ],
      ),
    );
  }
}

class _ApiSettingApiService extends BaseApiService {
  Future<ApiResponse<Map<String, dynamic>>> getConfig() {
    return apiGet<Map<String, dynamic>>(
      '/api/apiSetting/get',
      showLoading: false,
      dataParser: (json, code) => json,
    );
  }

  Future<ApiResponse<dynamic>> saveConfig({
    required int httpPort,
    required int httpsPort,
    required int expressApiCount,
  }) {
    return apiPost<dynamic>(
      '/api/apiSetting/save',
      body: {
        'httpPort': httpPort,
        'httpsPort': httpsPort,
        'expressApiCount': expressApiCount,
      },
    );
  }

  Future<ApiResponse<dynamic>> saveWelcome({required String welcomeText}) {
    return apiPost<dynamic>(
      '/api/apiSetting/saveWelcome',
      body: {'welcomeText': welcomeText},
      showLoading: false,
    );
  }

  Future<ApiResponse<dynamic>> restartService() {
    return apiPost<dynamic>('/api/apiSetting/restart', showLoading: false);
  }
}
