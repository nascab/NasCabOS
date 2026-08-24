import 'dart:async';
import 'package:NasCabOS/modules/fileBackup/localBackup/local_backup_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../service/server_storage_service.dart';
import '../../beans/server_info_bean.dart';
import 'udp_broadcast_listener.dart';
import '../../../../core/theme/theme_manager.dart';
import 'package:NasCabOS/core/config/app_config.dart';

import 'package:NasCabOS/modules/auth/service/auth_api_service.dart';
import '../../../../core/api/api_controller.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/device_utils.dart';
import '../../../../utils/toast_util.dart';
import 'package:NasCabOS/utils/legal_document_opener.dart';
import 'package:NasCabOS/core/routes/app_routes.dart';
import '../../../home/views/components/session_wallpaper_background.dart';
import '../login/login_twofa_dialog.dart';
import '../../service/response/login_response.dart';
import '../../service/response/server_status_response.dart';
import 'pair_code_scanner.dart';
import '../../../../core/utils/same_machine_checker_stub.dart'
    if (dart.library.html) '../../../../core/utils/same_machine_checker_web.dart';

/// 服务器状态ViewModel
class ServerListController extends GetxController {
  static ServerListController get instance => Get.find<ServerListController>();
  final UdpBroadcastListener _udpListener = UdpBroadcastListener();

  static const String _prefPrivacyConsentAccepted =
      'android_privacy_consent_accepted';

  // 响应式状态变量
  final localServerRx = Rxn<ServerInfoBean>();
  final savedServersRx = <ServerInfoBean>[].obs;
  final discoveredServersRx = <ServerInfoBean>[].obs;
  final welcomeTitle = ''.obs;

  final showAddServerView = false.obs; //是否显示添加服务器页面
  final showCreateAdminView = false.obs; //是否显示创建管理员页面
  final selectedServerRx = Rxn<ServerInfoBean>(); //当前选中的服务器

  bool _serverTapLocked = false;
  BuildContext? _tapLoadingDialogContext;
  int _tapLoadingToken = 0;
  bool _tapLoadingActive = false;
  bool _exitDialogShowing = false;
  bool _initFlowStarted = false;
  bool _privacyDialogShowing = false;

  @override
  void onInit() {
    super.onInit();
    if (_initFlowStarted) return;
    _initFlowStarted = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _initFlow();
    });
  }

  // getter方法
  ServerInfoBean? get localServer => localServerRx.value;
  List<ServerInfoBean> get savedServers => savedServersRx;
  List<ServerInfoBean> get discoveredServers => discoveredServersRx;

  Future<void> _initFlow() async {
    final consented = await _ensureAndroidPrivacyConsent();
    if (!consented) {
      _exitApp();
      return;
    }
    await _initAfterPrivacyConsent();
  }

  Future<void> _initAfterPrivacyConsent() async {
    await _loadSavedServers();

    await startUdpListening();

    final themeMode = ThemeManager().getThemeMode();
    Get.changeThemeMode(themeMode);
  }

  void _openLegalFromPrivacyDialog(String url, String title) {
    final ctx = Get.overlayContext;
    if (ctx == null) return;
    LegalDocumentOpener.open(ctx, url: url, title: title);
  }

  Future<BuildContext?> _getOverlayContextWithRetry() async {
    for (var i = 0; i < 60; i++) {
      final ctx = Get.overlayContext;
      if (ctx != null) return ctx;
      await Future.delayed(const Duration(milliseconds: 16));
    }
    return null;
  }

  Future<bool> _ensureAndroidPrivacyConsent() async {
    if (!DeviceUtils.isAndroid) return true;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefPrivacyConsentAccepted) == true) return true;
    if (_privacyDialogShowing) return false;
    _privacyDialogShowing = true;
    try {
      if (await _getOverlayContextWithRetry() == null) return false;

      final privacyUrl = LegalUrls.privacyUrl();
      final agreementUrl = LegalUrls.agreementUrl();

      final result = await Get.dialog<bool>(
        DialogUtil.createAlertDialog(
          title: Text('privacy_consent_title'.tr),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('privacy_consent_message_1'.tr),
              const SizedBox(height: 8),
              Text('privacy_consent_message_2'.tr),
              const SizedBox(height: 8),
              Text('privacy_consent_message_3'.tr),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => _openLegalFromPrivacyDialog(
                      agreementUrl,
                      'auth_user_agreement'.tr,
                    ),
                    child: Text('auth_user_agreement'.tr),
                  ),
                  TextButton(
                    onPressed: () => _openLegalFromPrivacyDialog(
                      privacyUrl,
                      'auth_privacy_policy'.tr,
                    ),
                    child: Text('auth_privacy_policy'.tr),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: Text('privacy_consent_disagree'.tr),
            ),
            TextButton(
              onPressed: () => Get.back(result: true),
              child: Text('privacy_consent_agree'.tr),
            ),
          ],
        ),
        barrierDismissible: false,
      );

      if (result == true) {
        await prefs.setBool(_prefPrivacyConsentAccepted, true);
        return true;
      }
      return false;
    } finally {
      _privacyDialogShowing = false;
    }
  }

  Future<void> _loadLoginConfig() async {
    try {
      final resp = await AuthApiService.instance.getLoginConfig();
      if (!resp.success) return;
      final data = resp.data ?? const {};
      final raw = data['welcomeText'];
      final text = raw is String ? raw.trim() : '';
      if (text.isNotEmpty) {
        welcomeTitle.value = text;
        update();
      }
    } catch (_) {}
  }

  ///显示添加服务器组件
  void goToAddServerView(ServerInfoBean? server) {
    selectedServerRx.value = server;
    showCreateAdminView.value = false;
    showAddServerView.value = true;
  }

  ///显示创建管理员组件
  void goToCreateAdminView(ServerInfoBean? server) {
    selectedServerRx.value = server;
    showAddServerView.value = false;
    showCreateAdminView.value = true;
  }

  //添加“本机”标识
  void addLocalSignToServerList(RxList<ServerInfoBean> serverList) {
    //添加本地服务器标识
    for (var server in serverList) {
      if (server.serverId == localServerRx.value?.serverId) {
        server.isLocalServer = true;
      } else {
        server.isLocalServer = false;
      }
    }
    // 排序：isLocalServer为true的排在前面
    serverList.sort((a, b) {
      if (a.isLocalServer && !b.isLocalServer) return -1;
      if (!a.isLocalServer && b.isLocalServer) return 1;
      return 0;
    });
  }

  // 检测本机是否启用了nascab服务

  /// 探测 127.0.0.1:6789 的本机服务 serverId，失败返回 null。
  /// 会临时切换 baseUrl 并在完成后恢复原值。
  Future<String?> _probeLocalhostServerId() async {
    try {
      final savedBaseUrl = ApiController.instance.baseUrl;
      ApiController.instance.setBaseUrl(AppConfig.localhostBaseUrl);
      final serverStatus = await AuthApiService.instance.checkServerStatus(
        false,
        timeout: const Duration(seconds: 2),
        maxRetries: 0,
      );
      ApiController.instance.setBaseUrl(savedBaseUrl);
      if (serverStatus.isNasCabServer) {
        final id = (serverStatus.serverData?['serverId'] ?? '').toString();
        print('[SameMachine] 127.0.0.1 探测成功, serverId=$id');
        return id;
      }
      print('[SameMachine] 127.0.0.1 探测失败: isNasCabServer=false');
    } catch (e) {
      print('[SameMachine] 127.0.0.1 探测异常: $e');
    }
    return null;
  }

  /// 检测客户端与已登录的服务器是否在同一台机器上运行。
  ///
  /// 策略：
  /// 1. 优先探测 127.0.0.1:6789，通过 serverId 比对（Native / Web localhost 访问）。
  /// 2. localhost 不可达时（如 Web 端 LAN IP 访问导致 CORS），对比浏览器 hostname。
  /// 3. 均无法判定则设为 false。
  Future<void> _checkAndSetSameMachine(
    String serverId,
    String hostname,
    String? lanIpv4,
  ) async {
    print('[SameMachine] === 开始同机检测 ===');
    print(
      '[SameMachine] 入参 serverId=$serverId, hostname=$hostname, lanIpv4=$lanIpv4',
    );

    // 1. 尝试 127.0.0.1 探测
    final localId = await _probeLocalhostServerId();
    if (localId != null && localId.isNotEmpty) {
      final same = localId == serverId;
      print(
        '[SameMachine] serverId 比对: localId=$localId, loggedInId=$serverId, same=$same',
      );
      ApiController.instance.setSameMachine(same);
      return;
    }

    // 2. localhost 不可达，Web 端对比浏览器 hostname
    if (kIsWeb) {
      final browserHostname = getLocalBrowserHostname();
      print('[SameMachine] Web fallback: browserHostname=$browserHostname');
      if (browserHostname.isNotEmpty) {
        final same =
            browserHostname == hostname ||
            browserHostname == (lanIpv4 ?? '') ||
            browserHostname == 'localhost' ||
            browserHostname == '127.0.0.1';
        print(
          '[SameMachine] Web hostname 比对: browser=$browserHostname, serverHostname=$hostname, lanIpv4=${lanIpv4 ?? 'null'}, same=$same',
        );
        ApiController.instance.setSameMachine(same);
        return;
      }
    }

    // 3. 无法判定
    print('[SameMachine] 无法判定，设为 false');
    ApiController.instance.setSameMachine(false);
  }

  Future<void> checkLocalNasCabServerStatus() async {
    try {
      ApiController.instance.setBaseUrl(AppConfig.localhostBaseUrl);
      final serverStatus = await AuthApiService.instance.checkServerStatus(
        false,
      );
      if (serverStatus.isNasCabServer) {
        localServerRx.value = ServerInfoBean(
          serverId: serverStatus.serverData?['serverId'] ?? '',
          serverUrl: AppConfig.localhostBaseUrl,
          serverName: "LocalHost",
          serverHost: '127.0.0.1',
          serverPortHttp: serverStatus.serverData?['httpPort'] ?? '9000',
          serverPortHttps: serverStatus.serverData?['httpsPort'] ?? '9443',
          serverHostName: serverStatus.serverData?['hostname'] ?? 'localhost',
          serverPlatform: serverStatus.serverData?['platform'] ?? 'unknown',
          isAutoScanned: true,
        );
        addLocalSignToServerList(savedServersRx);
        addLocalSignToServerList(discoveredServersRx);
      }
    } catch (e) {
      localServerRx.value = null;
    } finally {}
  }

  /// 处理发现的服务器
  void _handleDiscoveredServer(Map<String, dynamic> serverInfo) {
    try {
      // 创建服务器对象
      final serverItem = ServerInfoBean(
        serverId: serverInfo['serverId'] ?? '',
        serverUrl: 'http://${serverInfo['host']}:${serverInfo['port']}',
        userInputUrl: '',
        serverName: "NasCabServer",
        serverHost: serverInfo['host'],
        serverPortHttp: serverInfo['port'].toString(),
        serverPortHttps: serverInfo.containsKey('httpsPort')
            ? serverInfo['httpsPort'].toString()
            : '',
        serverHostName: serverInfo['hostname'],
        serverPlatform: serverInfo['platform'],
        isAutoScanned: true,
      );
      bool exists = discoveredServersRx.any(
        (server) => ServerStorageService.isSameIdentity(server, serverItem),
      );
      bool savedExists = savedServersRx.any(
        (server) => ServerStorageService.isSameIdentity(server, serverItem),
      );
      if (!exists && !savedExists) {
        discoveredServersRx.add(serverItem);
        addLocalSignToServerList(discoveredServersRx);
        print('✅ 添加新服务器到列表: ${serverItem.serverHostName}');
      } else {
        // print('ℹ️ 服务器已存在: ${serverItem.serverHostName}');
      }
    } catch (e) {
      print('❌ 处理发现的服务器失败: $e');
    }
  }

  /// 处理服务器点击事件
  ///
  /// 通道优先级：局域网直连 > P2P（自动探测直连/中继，先连上者优先）。
  /// - WiFi 环境优先走局域网 IP/LAN IP
  /// - 蜂窝网络跳过私有 IP 直连，直接进入 P2P 流程
  /// - P2P 使用 auto 模式同时探测直连/中继，连接成功后若为中继则在后台尝试升级直连
  Future<void> handleServerTap(
    BuildContext context,
    ServerInfoBean serverItem,
  ) async {
    if (_serverTapLocked) return;
    _serverTapLocked = true;
    _showTapLoadingDialog(context);
    try {
      final hasPairCode = (serverItem.pairCode ?? '').trim().isNotEmpty;
      final hasDirectUrl =
          serverItem.serverUrl.trim().isNotEmpty &&
          serverItem.serverUrl.trim() != ApiController.p2pBaseUrl;

      // 合并网络检测，避免重复 Connectivity 查询
      final network = await _checkNetworkType();

      try {
        ServerStatusResponse? status;
        var usingP2p = false;

        // ═══════════════════════════════════════════════════
        // Phase 1: 局域网直连（WiFi/有线网络）
        // ═══════════════════════════════════════════════════
        if (network.onWifi && hasDirectUrl) {
          // 蜂窝网络 + 私有 IP → 必然不可达，跳过直连
          final isPrivateLanServerUrl = _isUrlPrivateLan(serverItem.serverUrl);
          if (!(network.isCellular && isPrivateLanServerUrl)) {
            await ApiController.instance.disconnectP2p().catchError((_) {});
            ApiController.instance.setBaseUrl(serverItem.serverUrl);
            status = await AuthApiService.instance.checkServerStatus(
              false,
              timeout: const Duration(seconds: 2),
              maxRetries: 0,
            );
          }

          // serverUrl 失败，尝试 lanIpv4（避免重复探测相同 URL）
          if ((status == null || !status.success || !status.isNasCabServer) &&
              hasPairCode) {
            final lan = (serverItem.lanIpv4 ?? '').trim();
            final port = _resolveHttpPort(serverItem);
            final lanUrl = lan.isNotEmpty ? 'http://$lan:$port' : '';
            final lanAlreadyTried =
                lanUrl.isNotEmpty &&
                _normalizeUrl(lanUrl) == _normalizeUrl(serverItem.serverUrl);
            if (lan.isNotEmpty && !lanAlreadyTried) {
              await ApiController.instance.disconnectP2p().catchError((_) {});
              ApiController.instance.setBaseUrl(lanUrl);
              final lanStatus = await AuthApiService.instance.checkServerStatus(
                false,
                timeout: const Duration(seconds: 2),
                maxRetries: 0,
              );
              if (_matchServerId(lanStatus, serverItem)) {
                status = lanStatus;
              }
            }
          }
        }

        // ═══════════════════════════════════════════════════
        // Phase 2: P2P 自动探测直连/中继，先连上者优先
        // ═══════════════════════════════════════════════════
        if ((status == null || !status.success || !status.isNasCabServer) &&
            hasPairCode) {
          usingP2p = true;
          await ApiController.instance.disconnectP2p().catchError((_) {});
          await _ensureP2pConnected(serverItem);
          status = await AuthApiService.instance.checkServerStatus(
            false,
            timeout: const Duration(seconds: 3),
            maxRetries: 0,
          );
        }

        if (status == null || !status.success || !status.isNasCabServer) {
          _showErrorDialog('server_connect_fail'.tr);
          return;
        }

        final hasSuperAdmin = status.serverData?['hasSuperAdmin'] ?? false;
        if (!hasSuperAdmin) {
          DialogUtil.showConfirmDialog(
            title: 'server_init'.tr,
            content: 'server_init_content'.tr,
            onConfirm: () => goToCreateAdminView(serverItem),
            confirmText: 'ok'.tr,
            cancelText: 'cancel'.tr,
          );
          return;
        }

        if (serverItem.isAutoScanned) {
          if (usingP2p) {
            serverItem.serverId =
                status.serverData?['serverId'] ?? serverItem.serverId;
            serverItem.serverHostName =
                status.serverData?['hostname'] ?? serverItem.serverHostName;
            serverItem.serverPlatform =
                status.serverData?['platform'] ?? serverItem.serverPlatform;
            serverItem.serverPortHttp =
                status.serverData?['httpPort']?.toString() ??
                serverItem.serverPortHttp;
            serverItem.serverPortHttps =
                status.serverData?['httpsPort']?.toString() ??
                serverItem.serverPortHttps;
          }
          goToAddServerView(serverItem);
          return;
        }

        if (serverItem.needInputPwdEveryTime) {
          _dismissTapLoadingDialog();
          final password = await DialogUtil.showPasswordInputDialogForResult(
            title: 'server_login_password_required'.tr,
            message: 'server_login_password_required_message'.tr,
            hintText: 'auth_password_hint'.tr,
          );
          if (password == null || password.trim().isEmpty) {
            return;
          }
          if (!_showTapLoadingDialogFromOverlay()) {
            return;
          }
          await loginToServer(
            serverItem,
            baseUrlOverride: usingP2p ? ApiController.p2pBaseUrl : null,
            passwordOverride: password.trim(),
            persistPasswordOverride: false,
          );
          return;
        }

        await loginToServer(
          serverItem,
          baseUrlOverride: usingP2p ? ApiController.p2pBaseUrl : null,
        );
      } finally {
        _dismissTapLoadingDialog();
      }
    } catch (e) {
      _dismissTapLoadingDialog();
      _showErrorDialog(
        ApiController.shouldFormatAsP2pConnectError(e)
            ? ApiController.formatP2pConnectError(e)
            : 'server_status_check_failed_with_error'.trParams({'error': '$e'}),
      );
    } finally {
      _serverTapLocked = false;
    }
  }

  /// 从 ServerInfoBean 解析 HTTP 端口（优先 httpPort，其次 httpsPort，默认 9000）
  String _resolveHttpPort(ServerInfoBean serverItem) {
    final httpPort = serverItem.serverPortHttp.trim();
    if (httpPort.isNotEmpty) return httpPort;
    final httpsPort = serverItem.serverPortHttps.trim();
    if (httpsPort.isNotEmpty) return httpsPort;
    return '9000';
  }

  /// 校验 checkServerStatus 返回的 serverId 是否与 serverItem 匹配
  bool _matchServerId(
    ServerStatusResponse status,
    ServerInfoBean serverItem,
  ) {
    if (!status.success || !status.isNasCabServer) return false;
    final statusServerId =
        (status.serverData?['serverId']?.toString() ?? '').trim();
    final itemServerId = serverItem.serverId.trim();
    if (statusServerId.isEmpty || itemServerId.isEmpty) return false;
    return statusServerId == itemServerId;
  }

  void _showTapLoadingDialog(BuildContext context) {
    if (_tapLoadingActive) return;
    _tapLoadingActive = true;
    final token = ++_tapLoadingToken;

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        _tapLoadingDialogContext = dialogContext;
        final theme = Theme.of(dialogContext);
        return Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Flexible(
                  child: Text(
                    'auth_login_loading'.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      if (_tapLoadingToken == token) {
        _tapLoadingActive = false;
        _tapLoadingDialogContext = null;
      }
    });
  }

  bool _showTapLoadingDialogFromOverlay() {
    final overlayContext = Get.overlayContext;
    if (overlayContext == null) return false;
    _showTapLoadingDialog(overlayContext);
    return true;
  }

  void _dismissTapLoadingDialog() {
    if (!_tapLoadingActive) return;
    _tapLoadingActive = false;
    final ctx = _tapLoadingDialogContext;
    _tapLoadingDialogContext = null;
    if (ctx == null) return;
    try {
      final navigator = Navigator.of(ctx, rootNavigator: true);
      if (navigator.canPop()) {
        navigator.pop();
      }
    } catch (_) {}
  }

  Future<void> addServerByPairCode() async {
    final context = Get.overlayContext;
    if (context == null) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => const _PairCodeConnectDialog(),
    );
  }

  Future<void> _ensureP2pConnected(ServerInfoBean serverItem) async {
    final code = (serverItem.pairCode ?? '').trim();
    if (code.isEmpty) {
      throw Exception('pair_code_empty');
    }
    // 遇到 P2P_DEVICE_OFFLINE 时重试，设备可能处于重连信令服务器的短暂窗口期
    const maxRetries = 3;
    const retryDelay = Duration(milliseconds: 1500);
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await ApiController.instance.connectP2pByPairCode(
          code,
          icePreference: P2pIcePreference.auto,
        );
        return;
      } catch (e) {
        final isOfflineError = e.toString().contains('P2P_DEVICE_OFFLINE');
        if (isOfflineError && attempt < maxRetries) {
          await Future<void>.delayed(retryDelay);
          continue;
        }
        rethrow;
      }
    }
  }

  /// 合并网络类型检测，避免重复 Connectivity 查询。
  /// 返回 ({bool onWifi, bool isCellular}) 记录。
  Future<({bool onWifi, bool isCellular})> _checkNetworkType() async {
    if (!DeviceUtils.isMobile) return (onWifi: true, isCellular: false);
    try {
      final result = await Connectivity().checkConnectivity();
      return (
        onWifi: result.any(
          (r) =>
              r == ConnectivityResult.wifi ||
              r == ConnectivityResult.ethernet ||
              r == ConnectivityResult.other ||
              r == ConnectivityResult.vpn,
        ),
        isCellular: result.contains(ConnectivityResult.mobile),
      );
    } catch (_) {
      return (onWifi: true, isCellular: false);
    }
  }

  /// 标准化 URL 用于比较（去除末尾斜杠、统一小写 scheme+host）
  String _normalizeUrl(String url) {
    try {
      final uri = Uri.tryParse(url.trim());
      if (uri == null) return url.trim().toLowerCase();
      final scheme = uri.scheme.toLowerCase();
      final host = uri.host.toLowerCase();
      final port = uri.hasPort ? ':${uri.port}' : '';
      final path = uri.path.replaceAll(RegExp(r'/+$'), '');
      return '$scheme://$host$port$path';
    } catch (_) {
      return url.trim().toLowerCase();
    }
  }

  /// 检测URL是否是私有局域网地址
  bool _isUrlPrivateLan(String url) {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) return false;
      return _isPrivateIpv4(uri.host);
    } catch (_) {
      return false;
    }
  }

  /// 检测是否是私有IPv4地址（局域网/回环地址）
  bool _isPrivateIpv4(String host) {
    if (!_isIpv4(host)) return false;
    final parts = host.split('.');
    final a = int.tryParse(parts[0]) ?? -1;
    final b = int.tryParse(parts[1]) ?? -1;
    if (a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    if (a == 127) return true;
    return false;
  }

  /// 显示错误对话框
  void _showErrorDialog(String message) {
    DialogUtil.showErrorDialog(message: message, title: 'error'.tr);
  }

  ServerInfoBean _buildLoginRequestServer(
    ServerInfoBean serverItem, {
    String? passwordOverride,
  }) {
    return ServerInfoBean(
      serverId: serverItem.serverId,
      serverUrl: serverItem.serverUrl,
      userInputUrl: serverItem.userInputUrl,
      lanIpv4: serverItem.lanIpv4,
      lanHttpPort: serverItem.lanHttpPort,
      lanHttpsPort: serverItem.lanHttpsPort,
      serverName: serverItem.serverName,
      serverHost: serverItem.serverHost,
      serverPortHttp: serverItem.serverPortHttp,
      serverPortHttps: serverItem.serverPortHttps,
      serverHostName: serverItem.serverHostName,
      customHostname: serverItem.customHostname,
      serverPlatform: serverItem.serverPlatform,
      isAutoScanned: serverItem.isAutoScanned,
      isLocalServer: serverItem.isLocalServer,
      isP2p: serverItem.isP2p,
      pairCode: serverItem.pairCode,
      username: serverItem.username,
      password: passwordOverride ?? serverItem.password,
      accessToken: serverItem.accessToken,
      refreshToken: serverItem.refreshToken,
      lastLoginTime: serverItem.lastLoginTime,
      needInputPwdEveryTime: serverItem.needInputPwdEveryTime,
    );
  }

  /// 显示密码输入对话框
  void _showPasswordInputDialog(
    ServerInfoBean serverItem, {
    String? title,
    String? message,
    bool persistPassword = true,
    String? baseUrlOverride,
  }) {
    DialogUtil.showPasswordInputDialog(
      title: title ?? 'auth_password_error'.tr,
      message: message ?? 'auth_password_error_message'.tr,
      hintText: 'auth_password_hint'.tr,
      onConfirm: (String newPassword) {
        loginToServer(
          serverItem,
          baseUrlOverride: baseUrlOverride,
          passwordOverride: newPassword,
          persistPasswordOverride: persistPassword,
        );
      },
    );
  }

  /// 登录到服务器
  Future<void> loginToServer(
    ServerInfoBean serverItem, {
    String? baseUrlOverride,
    String? passwordOverride,
    bool? persistPasswordOverride,
  }) async {
    try {
      if (baseUrlOverride != null && baseUrlOverride.trim().isNotEmpty) {
        ApiController.instance.setBaseUrl(baseUrlOverride.trim());
      } else if (!ApiController.instance.isP2pMode) {
        final url = serverItem.serverUrl.trim();
        if (url.isNotEmpty) {
          ApiController.instance.setBaseUrl(url);
        }
      }
      final requestServer = _buildLoginRequestServer(
        serverItem,
        passwordOverride: passwordOverride,
      );
      final loginResult = await AuthApiService.instance.loginToServer(
        requestServer,
        showLoading: false,
      );
      if (loginResult.success) {
        if (loginResult.twoFactorRequired == true &&
            (loginResult.tempToken ?? '').isNotEmpty) {
          _dismissTapLoadingDialog();
          _showTwofaDialog(
            requestServer,
            loginResult.tempToken!,
            persistPassword:
                persistPasswordOverride ?? !serverItem.needInputPwdEveryTime,
          );
          return;
        }
        // 登录成功，更新服务器信息
        await _handleLoginSuccess(
          serverItem,
          loginResult,
          passwordToPersist:
              (persistPasswordOverride ?? !serverItem.needInputPwdEveryTime)
              ? requestServer.password
              : '',
        );
      } else {
        if (loginResult.code == 999) {
          // 密码错误，弹出带输入框的密码输入框
          _dismissTapLoadingDialog();
          _showPasswordInputDialog(
            serverItem,
            persistPassword:
                persistPasswordOverride ?? !serverItem.needInputPwdEveryTime,
            baseUrlOverride: baseUrlOverride,
          );
        } else {
          _dismissTapLoadingDialog();
          _showErrorDialog('${loginResult.message}');
        }
      }
    } catch (e) {
      // 关闭loading对话框
      _dismissTapLoadingDialog();
      _showErrorDialog('${'auth_login_failure'.tr}: $e');
    }
  }

  void _showTwofaDialog(
    ServerInfoBean serverItem,
    String tempToken, {
    bool persistPassword = true,
  }) {
    if (Get.overlayContext == null) return;
    showDialog(
      context: Get.overlayContext!,
      barrierDismissible: false,
      builder: (_) => TwofaCodeDialog(
        onVerify: (code) {
          Get.back();
          _submitTwoFactor(
            serverItem,
            tempToken,
            code,
            persistPassword: persistPassword,
          );
        },
      ),
    );
  }

  Future<void> _submitTwoFactor(
    ServerInfoBean serverItem,
    String tempToken,
    String code, {
    bool persistPassword = true,
  }) async {
    DialogUtil.showLoadingDialog(
      message: 'auth_login_loading'.tr,
      barrierDismissible: false,
    );
    try {
      final verifyResult = await AuthApiService.instance.verifyTwoFactorLogin(
        tempToken: tempToken,
        code: code,
      );
      Get.back();
      if (!verifyResult.success) {
        _showErrorDialog(verifyResult.message ?? 'auth_login_failure'.tr);
        return;
      }
      await _handleLoginSuccess(
        serverItem,
        verifyResult,
        passwordToPersist: persistPassword ? serverItem.password : '',
      );
    } catch (e) {
      Get.back();
      _showErrorDialog('${'auth_login_failure'.tr}: $e');
    }
  }

  Future<void> _handleLoginSuccess(
    ServerInfoBean serverItem,
    LoginResponse loginResult, {
    String? passwordToPersist,
  }) async {
    _dismissTapLoadingDialog();
    serverItem.password = passwordToPersist ?? serverItem.password;
    serverItem.accessToken = loginResult.accessToken;
    serverItem.serverId = loginResult.serverId ?? 'unknown';
    serverItem.serverPlatform = loginResult.platform ?? 'unknown';
    serverItem.serverHostName = loginResult.hostname ?? 'unknown';
    final ch = loginResult.customHostname?.trim();
    serverItem.customHostname = (ch == null || ch.isEmpty) ? null : ch;
    serverItem.refreshToken = loginResult.refreshToken;
    serverItem.serverPortHttp = loginResult.httpPort?.toString() ?? '';
    serverItem.serverPortHttps = loginResult.httpsPort?.toString() ?? '';
    final pair = (loginResult.pairCode ?? '').trim();
    if (pair.isNotEmpty) {
      serverItem.pairCode = pair;
    }
    final lan = (loginResult.lanIpv4 ?? '').trim();
    if (lan.isNotEmpty) {
      serverItem.lanIpv4 = lan;
      serverItem.lanHttpPort = loginResult.httpPort?.toString() ?? '';
      serverItem.lanHttpsPort = loginResult.httpsPort?.toString() ?? '';
      final currentUrl = serverItem.serverUrl.trim();
      if (currentUrl.isEmpty) {
        serverItem.serverUrl = _buildLanServerUrl(
          lan,
          loginResult.httpPort?.toString(),
          loginResult.httpsPort?.toString(),
        );
        if ((serverItem.pairCode ?? '').trim().isEmpty &&
            (serverItem.userInputUrl ?? '').trim().isEmpty) {
          serverItem.userInputUrl = serverItem.serverUrl;
        }
      }
    }
    serverItem.isP2p =
        serverItem.serverUrl.trim().isEmpty &&
        (serverItem.pairCode ?? '').trim().isNotEmpty;
    await ServerStorageService.addServer(serverItem);
    await refreshSavedServers();

    ApiController.instance.setAuthInfo(
      serverId: serverItem.serverId,
      accessToken: loginResult.accessToken!,
      refreshToken: loginResult.refreshToken!,
      expiresIn: loginResult.expiresIn!,
      shellSupported: loginResult.shellSupported ?? false,
      httpsPort: loginResult.httpsPort?.toString(),
      serverPlatform: loginResult.platform ?? serverItem.serverPlatform,
      serverVersion: loginResult.serverVersion,
      serverHostname: loginResult.hostname ?? serverItem.serverHostName,
      customHostname: serverItem.customHostname,
    );

    // 登录成功且当前走 P2P 时，后台探测直连并尝试从中继无缝升级为直连
    if (ApiController.instance.isP2pMode) {
      ApiController.instance.scheduleP2pDirectUpgrade();
    }

    await SessionWallpaperBackground.preloadForCurrentSession();

    // 异步检测客户端与服务器是否在同一台机器（本地127.0.0.1探测 + Web hostname fallback）
    unawaited(
      _checkAndSetSameMachine(
        serverItem.serverId,
        serverItem.serverHostName,
        serverItem.lanIpv4,
      ),
    );

    print('22服务器登录成功: ${loginResult.toString()}');
    await stopUdpListening();
    Get.offAllNamed(AppRoutes.home);
    if (Get.isRegistered<LocalBackupController>()) {
      print(
        '[Login] 调用 LocalBackupController.restartRealtimeWatchersForCurrentServer',
      );
      Get.find<LocalBackupController>()
          .restartRealtimeWatchersForCurrentServer();
    } else {
      print('[Login] LocalBackupController 未注册，跳过实时备份启动');
    }
  }

  /// 当本机无服务器地址时，用登录返回的 lanIpv4 + 端口拼接为服务器地址
  String _buildLanServerUrl(
    String lanIpv4,
    String? httpPort,
    String? httpsPort,
  ) {
    final lan = lanIpv4.trim();
    if (lan.isEmpty) return '';
    final port = (httpPort ?? '').trim().isNotEmpty
        ? httpPort!.trim()
        : ((httpsPort ?? '').trim().isNotEmpty ? httpsPort!.trim() : '9000');
    return 'http://$lan:$port';
  }

  bool _isIpv4(String host) {
    final s = host.trim();
    if (s.isEmpty) return false;
    final m = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(s);
    if (!m) return false;
    final parts = s.split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      final v = int.tryParse(p);
      if (v == null || v < 0 || v > 255) return false;
    }
    return true;
  }

  /// 处理菜单选择
  void handleMenuSelection(String value, ServerInfoBean serverItem) {
    switch (value) {
      case 'edit_pair_code':
        _showEditPairCodeDialog(serverItem);
        break;
      case 'edit':
        // 显示添加服务器页面
        goToAddServerView(serverItem);
        break;
      case 'recover':
        // 显示忘记密码页面
        goToRecover(serverItem);
        break;
      case 'delete':
        print('删除服务器: ${serverItem.serverName}');
        _showDeleteConfirmDialog(serverItem);
        break;
    }
  }

  Future<void> _showEditPairCodeDialog(ServerInfoBean serverItem) async {
    if (Get.overlayContext == null) return;
    final pairCode = await DialogUtil.showInputDialog(
      title: 'server_edit_pair_code_title'.tr,
      content: 'server_edit_pair_code_content'.tr,
      initialValue: (serverItem.pairCode ?? '').trim(),
      validator: (v) {
        final s = v?.trim() ?? '';
        if (s.isEmpty) return 'server_pair_code_empty'.tr;
        if (s.length < 4) return 'server_pair_code_invalid'.tr;
        if (s.length > 32) return 'server_pair_code_invalid'.tr;
        return null;
      },
    );
    final code = (pairCode ?? '').trim();
    if (code.isEmpty) return;

    serverItem.pairCode = code;
    await ServerStorageService.addServer(serverItem);
    await refreshSavedServers();
  }

  /// 显示删除确认对话框
  void _showDeleteConfirmDialog(ServerInfoBean serverItem) {
    final serverName = serverItem.serverName.isNotEmpty
        ? serverItem.serverName
        : serverItem.serverHostName;

    DialogUtil.showConfirmDialog(
      title: 'delete'.tr,
      content: 'server_delete_confirm_message'.trParams({
        'serverName': serverName,
      }),
      confirmText: 'delete'.tr,
      cancelText: 'cancel'.tr,
      onConfirm: () => _deleteServer(serverItem),
    );
  }

  /// 删除服务器
  void _deleteServer(ServerInfoBean serverItem) {
    print('删除服务器: ${serverItem.serverName}');
    // 调用视图模型删除服务器
    deleteServer(serverItem);
    // 刷新服务器列表
    refreshSavedServers();
  }

  /// 开始UDP监听
  Future<void> startUdpListening() async {
    await stopUdpListening();
    _udpListener.setOnServerDiscovered(_handleDiscoveredServer);
    await _udpListener.startListening();
  }

  /// 停止UDP监听
  Future<void> stopUdpListening() async {
    await _udpListener.stopListening();
  }

  /// 加载已保存的服务器列表
  Future<void> _loadSavedServers() async {
    try {
      final savedServers = ServerStorageService.loadServers();
      savedServersRx.value = savedServers;
      addLocalSignToServerList(savedServersRx);
    } catch (e) {
      print('❌ 加载已保存服务器列表失败: $e');
    }
  }

  /// 刷新已保存的服务器列表（公共方法）
  Future<void> refreshSavedServers() async {
    await _loadSavedServers();
    discoveredServersRx.removeWhere(
      (server) => savedServersRx.any(
        (savedServer) =>
            ServerStorageService.isSameIdentity(savedServer, server),
      ),
    );
  }

  /// 根据id删除服务器（公共方法）
  Future<void> deleteServer(ServerInfoBean serverItem) async {
    ServerStorageService.removeServer(serverItem);
  }

  //去到忘记密码页面
  void goToRecover(ServerInfoBean serverItem) {
    ApiController.instance.setBaseUrl(serverItem.serverUrl);
    Get.toNamed('/recover');
  }

  Future<void> confirmExitApp() async {
    if (_exitDialogShowing) return;
    _exitDialogShowing = true;
    try {
      if (Get.overlayContext == null) {
        _exitApp();
        return;
      }
      final result = await DialogUtil.showConfirmDialog(
        title: 'server_list_exit_title'.tr,
        content: 'server_list_exit_content'.tr,
        confirmText: 'ok'.tr,
        cancelText: 'cancel'.tr,
        barrierDismissible: false,
      );
      if (result == true) {
        _exitApp();
      }
    } finally {
      _exitDialogShowing = false;
    }
  }

  void _exitApp() {
    if (kIsWeb) return;
    try {
      SystemNavigator.pop();
    } catch (_) {}
  }

  @override
  void onClose() {
    _udpListener.stopListeningSync();
    super.onClose();
  }
}

/// 配对码添加：在对话框内完成校验与连接，仅成功后再关闭并进入添加服务器页。
class _PairCodeConnectDialog extends StatefulWidget {
  const _PairCodeConnectDialog();

  @override
  State<_PairCodeConnectDialog> createState() => _PairCodeConnectDialogState();
}

class _PairCodeConnectDialogState extends State<_PairCodeConnectDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _fieldError;
  String? _connectError;
  bool _connecting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_connecting) return;
    final code = _controller.text.trim();
    final validation = ApiController.validatePairCodeText(code);
    if (validation != null) {
      setState(() => _fieldError = validation);
      return;
    }
    setState(() {
      _connecting = true;
      _fieldError = null;
      _connectError = null;
    });
    try {
      final status = await ApiController.instance
          .connectP2pByPairCodeAndCheckServerStatus(
            code,
            timeout: const Duration(seconds: 20),
          );
      if (!mounted) return;
      if (!status.success || !status.isNasCabServer) {
        setState(() {
          _connecting = false;
          _connectError = 'server_connect_fail'.tr;
        });
        return;
      }

      final listCtrl = Get.find<ServerListController>();
      final serverId = status.serverData?['serverId']?.toString() ?? '';
      final matches = listCtrl.savedServersRx
          .where((s) => s.serverId.trim().isNotEmpty && s.serverId == serverId)
          .toList();
      final preferred = matches.length == 1 ? matches.first : null;

      final candidate = ServerInfoBean(
        serverId: serverId,
        serverUrl: '',
        userInputUrl: '',
        serverName: preferred?.serverName ?? 'NasCabServer',
        serverHost: '',
        serverPortHttp: status.serverData?['httpPort']?.toString() ?? '',
        serverPortHttps: status.serverData?['httpsPort']?.toString() ?? '',
        serverHostName: status.serverData?['hostname']?.toString() ?? '',
        serverPlatform: status.serverData?['platform']?.toString() ?? 'unknown',
        isAutoScanned: false,
        isLocalServer: false,
        isP2p: true,
        pairCode: code,
      );

      Navigator.of(context).pop();
      listCtrl.goToAddServerView(candidate);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connectError = ApiController.formatP2pConnectError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_connecting,
      child: DialogUtil.createAlertDialog(
        title: Text('server_add_by_pair_code_title'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: Text('server_add_by_pair_code_content'.tr)),
                if (!kIsWeb && DeviceUtils.isMobile)
                  TextButton(
                    onPressed: _connecting
                        ? null
                        : () async {
                            final scanned = await scanPairCodeQr(context);
                            final v = (scanned ?? '').trim();
                            if (v.isEmpty) return;
                            final e = ApiController.validatePairCodeText(v);
                            if (e == null) {
                              _controller.text = v;
                              setState(() => _fieldError = null);
                              return;
                            }
                            ToastUtil.show('server_pair_code_scan_invalid'.tr);
                          },
                    child: Text('server_pair_code_scan_qr'.tr),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              enabled: !_connecting,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                errorText: _fieldError,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              autofocus: true,
              onChanged: (value) {
                setState(() {
                  _fieldError = ApiController.validatePairCodeText(value);
                });
              },
            ),
            if (_connecting) ...[
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'server_connecting'.tr,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ],
            if (!_connecting && _connectError != null) ...[
              const SizedBox(height: 8),
              Text(
                _connectError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 10),
            InkWell(
              onTap: _connecting
                  ? null
                  : () {
                      DialogUtil.showInfoDialog(
                        title: 'server_pair_code_how_title'.tr,
                        content: 'server_pair_code_how_content'.tr,
                      );
                    },
              child: Text(
                'server_pair_code_how_link'.tr,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _connecting
                      ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
                      : theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _connecting ? null : () => Navigator.of(context).pop(),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: _connecting ? null : _submit,
            child: Text('ok'.tr),
          ),
        ],
      ),
    );
  }
}
