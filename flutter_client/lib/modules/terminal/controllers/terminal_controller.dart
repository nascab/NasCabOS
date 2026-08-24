import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart'; 
import 'package:get/get.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xterm/xterm.dart';

import '../../../core/api/api_controller.dart';
import '../../../core/web/local_kv_store_stub.dart'
    if (dart.library.html) '../../../core/web/local_kv_store_web.dart';
import '../../files/service/file_ws_channel_factory_stub.dart'
    if (dart.library.io) '../../files/service/file_ws_channel_factory_io.dart';
import '../../../utils/toast_util.dart';
import '../../../utils/user_agent_util.dart';

class TerminalUiConfig {
  final String foreground;
  final String background;
  final String cursor;
  final int fontSize;
  final double lineHeight;
  final String fontFamily;
  final String cursorStyle;
  final bool cursorBlink;

  const TerminalUiConfig({
    required this.foreground,
    required this.background,
    required this.cursor,
    required this.fontSize,
    required this.lineHeight,
    required this.fontFamily,
    required this.cursorStyle,
    required this.cursorBlink,
  });

  static TerminalUiConfig defaults() {
    return TerminalUiConfig(
      foreground: '#e6e6e6',
      background: '#0b0b0b',
      cursor: '#e6e6e6',
      fontSize: 14,
      lineHeight: 1.0,
      fontFamily: 'RobotoMono',
      cursorStyle: 'block',
      cursorBlink: true,
    );
  }

  TerminalUiConfig copyWith({
    String? foreground,
    String? background,
    String? cursor,
    int? fontSize,
    double? lineHeight,
    String? fontFamily,
    String? cursorStyle,
    bool? cursorBlink,
  }) {
    return TerminalUiConfig(
      foreground: foreground ?? this.foreground,
      background: background ?? this.background,
      cursor: cursor ?? this.cursor,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      fontFamily: fontFamily ?? this.fontFamily,
      cursorStyle: cursorStyle ?? this.cursorStyle,
      cursorBlink: cursorBlink ?? this.cursorBlink,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'foreground': foreground,
      'background': background,
      'cursor': cursor,
      'fontSize': fontSize,
      'lineHeight': lineHeight,
      'fontFamily': fontFamily,
      'cursorStyle': cursorStyle,
      'cursorBlink': cursorBlink,
    };
  }

  static TerminalUiConfig? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    String s(Object? v) => v?.toString() ?? '';
    int i(Object? v) => int.tryParse(s(v)) ?? -1;
    double d(Object? v) => double.tryParse(s(v)) ?? -1;
    bool b(Object? v) => v == true || s(v).toLowerCase() == 'true';

    final fontSize = i(raw['fontSize']);
    final lineHeight = d(raw['lineHeight']);
    final fg = s(raw['foreground']).trim();
    final bg = s(raw['background']).trim();
    final cursor = s(raw['cursor']).trim();
    final fontFamily = s(raw['fontFamily']).trim();
    final cursorStyle = s(raw['cursorStyle']).trim();

    if (fg.isEmpty || bg.isEmpty || cursor.isEmpty) return null;
    if (fontSize < 8 || fontSize > 24) return null;
    if (lineHeight <= 0) return null;

    return TerminalUiConfig(
      foreground: fg,
      background: bg,
      cursor: cursor,
      fontSize: fontSize,
      lineHeight: lineHeight,
      fontFamily: fontFamily.isEmpty ? 'RobotoMono' : fontFamily,
      cursorStyle: cursorStyle.isEmpty ? 'block' : cursorStyle,
      cursorBlink: b(raw['cursorBlink']),
    );
  }

  static Color parseColor(String raw, {required Color fallback}) {
    final s = raw.trim();
    if (s.isEmpty) return fallback;
    final hex = s.startsWith('#') ? s.substring(1) : s;
    final normalized = switch (hex.length) {
      6 => 'ff$hex',
      8 => hex,
      _ => '',
    };
    if (normalized.isEmpty) return fallback;
    final v = int.tryParse(normalized, radix: 16);
    if (v == null) return fallback;
    return Color(v);
  }
}

class TerminalController extends GetxController {
  final String instanceId;
  final Terminal terminal = Terminal(maxLines: 10000);

  final Rx<TerminalUiConfig> uiConfig = TerminalUiConfig.defaults().obs;
  final RxBool connecting = false.obs;
  final RxBool connected = false.obs;
  final RxString statusText = ''.obs;

  /// win32 下当前 shell：'powershell' | 'cmd'，默认 powershell，仅用于切换 WS URL 参数，不持久化
  final RxString currentShell = 'powershell'.obs;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _manualClose = false;
  bool _autoReconnectDisabled = false;
  int _reconnectAttempt = 0;
  String? _nextConnectUrlOverride;
  bool _triedWsSchemeFallback = false;
  String _clientDeviceId = '';
  final String _terminalConnId =
      'conn_${DateTime.now().microsecondsSinceEpoch}_${(DateTime.now().millisecondsSinceEpoch % 100000).toString()}';
  String _sessionId = '';
  bool _hasRenderedSessionContent = false;

  TerminalController({required this.instanceId});

  @override
  void onInit() {
    super.onInit();
    terminal.onOutput = _handleTerminalOutput;
    terminal.onResize = (cols, rows, pixelWidth, pixelHeight) {
      resize(cols, rows);
    };
    terminal.setCursorBlinkMode(uiConfig.value.cursorBlink);
    Future.microtask(() async {
      await _loadUiConfig();
      await connect();
    });
  }

  @override
  void onClose() {
    _manualClose = true;
    _disposeChannel();
    terminal.onOutput = null;
    terminal.onResize = null;
    super.onClose();
  }

  static const _kConnectTimeout = Duration(seconds: 20);
  Timer? _connectTimeoutTimer;

  Future<void> connect({bool manual = false, bool forceNew = false}) async {
    if (connecting.value) {
      debugPrint('[Terminal] connect() 被忽略: 已在连接中');
      return;
    }
    if (connected.value) {
      debugPrint('[Terminal] connect() 被忽略: 已连接');
      return;
    }

    if (manual) {
      _autoReconnectDisabled = false;
      _triedWsSchemeFallback = false;
    }
    _manualClose = false;
    connecting.value = true;
    statusText.value = 'terminal_connecting'.tr;
    if (_clientDeviceId.isEmpty) {
      try {
        _clientDeviceId = await UserAgentUtil.getOrCreatePersistentDeviceId();
      } catch (_) {
        _clientDeviceId = instanceId.trim().isEmpty
            ? 'terminal'
            : instanceId.trim();
      }
    }

    final isWin32 =
        (ApiController.instance.serverPlatform ?? '').toLowerCase() == 'win32';
    final shellParam = isWin32 ? currentShell.value : null;
    final url =
        _nextConnectUrlOverride ??
        ApiController.instance.getTerminalConnectUrl(
          shell: shellParam,
          clientDeviceId: _clientDeviceId,
          terminalConnId: _terminalConnId,
          forceNew: forceNew,
        );
    _nextConnectUrlOverride = null;
    debugPrint('[Terminal] 步骤1: 获取连接 URL $url');

    if (url.isEmpty) {
      debugPrint('[Terminal] 步骤1 失败: URL 为空 (baseUrl 或 token 可能未设置)');
      connecting.value = false;
      connected.value = false;
      statusText.value = 'terminal_connection_failed'.tr;
      ToastUtil.show('terminal_connection_failed'.tr);
      return;
    }
    final isP2p = ApiController.instance.baseUrl.trim().startsWith(
      ApiController.p2pBaseUrl,
    );
    debugPrint(
      '[Terminal] 步骤1 完成: URL 已获取, 是否 P2P: $isP2p, path: /api/terminal/connect',
    );

    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = Timer(_kConnectTimeout, () {
      if (connecting.value && !connected.value) {
        debugPrint(
          '[Terminal] 连接超时: ${_kConnectTimeout.inSeconds}s 内未收到服务端首条消息，请检查网络或服务端是否下发 ready/output',
        );
      }
    });

    try {
      debugPrint('[Terminal] 步骤2: 创建 WebSocket Channel');
      _disposeChannel();
      _channel = connectFileWebSocketChannel(Uri.parse(url));
      debugPrint('[Terminal] 步骤2 完成: Channel 已创建，开始 listen stream');
      _sub = _channel!.stream.listen(
        _handleServerMessage,
        onError: _handleSocketError,
        onDone: _handleSocketDone,
        cancelOnError: true,
      );
      _startPing();
      debugPrint(
        '[Terminal] 步骤3: stream.listen 已注册，等待服务端首条消息 (ready/output/raw)',
      );
    } catch (e, st) {
      debugPrint('[Terminal] 步骤2 异常: $e');
      debugPrint('[Terminal] $st');
      _connectTimeoutTimer?.cancel();
      _connectTimeoutTimer = null;
      connecting.value = false;
      connected.value = false;
      statusText.value = 'terminal_connection_failed'.tr;
      ToastUtil.show('terminal_connection_failed'.tr);
      _scheduleReconnect();
    }
  }

  void disconnect() {
    _manualClose = true;
    try {
      _sendJson({'type': 'close'});
    } catch (_) {}
    _disposeChannel();
    connected.value = false;
    connecting.value = false;
    statusText.value = 'terminal_disconnected'.tr;
  }

  Future<void> terminateSession() async {
    _manualClose = true;
    _autoReconnectDisabled = true;
    try {
      _sendJson({'type': 'terminate'});
    } catch (_) {}
    try {
      _sendJson({'type': 'close', 'reason': 'terminate'});
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 260));
    _disposeChannel();
    connected.value = false;
    connecting.value = false;
    statusText.value = 'terminal_disconnected'.tr;
  }

  void reconnectNow() {
    disconnect();
    _reconnectAttempt = 0;
    connect(manual: true);
  }

  void interruptRunningCommand() {
    if (!connected.value) return;
    _sendJson({'type': 'input', 'data': '\u0003'});
  }

  /// 仅当服务器为 win32 时有效，切换后会断开并重连（新 URL 带 shell 参数）
  void switchShell(String shell) {
    final s = (shell == 'cmd') ? 'cmd' : 'powershell';
    if (currentShell.value == s) return;
    currentShell.value = s;
    disconnect();
    _reconnectAttempt = 0;
    connect(manual: true, forceNew: true);
  }

  TerminalTheme get terminalTheme {
    final cfg = uiConfig.value;
    final fg = TerminalUiConfig.parseColor(
      cfg.foreground,
      fallback: const Color(0xffe6e6e6),
    );
    final bg = TerminalUiConfig.parseColor(
      cfg.background,
      fallback: const Color(0xff0b0b0b),
    );
    final cursor = TerminalUiConfig.parseColor(
      cfg.cursor,
      fallback: const Color(0xffe6e6e6),
    );
    return TerminalTheme(
      foreground: fg,
      background: bg,
      cursor: cursor,
      selection: fg.withValues(alpha: 0.35),
      black: const Color(0xff000000),
      red: const Color(0xffcd3131),
      green: const Color(0xff0dbc79),
      yellow: const Color(0xffe5e510),
      blue: const Color(0xff2472c8),
      magenta: const Color(0xffbc3fbc),
      cyan: const Color(0xff11a8cd),
      white: const Color(0xffe5e5e5),
      brightBlack: const Color(0xff666666),
      brightRed: const Color(0xffff0000),
      brightGreen: const Color(0xff14ce14),
      brightYellow: const Color(0xffffff00),
      brightBlue: const Color(0xff3b8eea),
      brightMagenta: const Color(0xffd670d6),
      brightCyan: const Color(0xff29b8db),
      brightWhite: const Color(0xffffffff),
      searchHitBackground: const Color(0xffe5e510),
      searchHitBackgroundCurrent: const Color(0xffffff00),
      searchHitForeground: const Color(0xff000000),
    );
  }

  TerminalStyle get terminalTextStyle {
    final cfg = uiConfig.value;
    final fontFamily = cfg.fontFamily.trim();
    final normalized = fontFamily.isEmpty ? '' : fontFamily.toLowerCase();
    // 未设置或为 monospace 时使用思源黑体，各平台显示一致
    final effectiveFamily = (normalized.isEmpty || normalized == 'monospace')
        ? 'RobotoMono'
        : fontFamily;
    return TerminalStyle(
      fontFamily: effectiveFamily,
      fontSize: cfg.fontSize.toDouble(),
      height: cfg.lineHeight,
    );
  }

  Future<void> saveUiConfig() async {
    final key = _uiConfigStorageKey();
    await kvSet(key, jsonEncode(uiConfig.value.toJson()));
  }

  void setUiConfig(TerminalUiConfig next) {
    uiConfig.value = next;
    terminal.setCursorBlinkMode(next.cursorBlink);
  }

  String _uiConfigStorageKey() {
    final id = instanceId.trim().isEmpty ? 'terminal' : instanceId.trim();
    return 'terminal_config_$id';
  }

  Future<void> _loadUiConfig() async {
    try {
      final raw = await kvGet(_uiConfigStorageKey());
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      final parsed = TerminalUiConfig.tryFromJson(decoded);
      if (parsed == null) return;
      uiConfig.value = parsed;
      terminal.setCursorBlinkMode(parsed.cursorBlink);
    } catch (_) {}
  }

  bool _isNoPermissionError({required String code, required String message}) {
    final c = code.trim().toUpperCase();
    if (c == 'TERMINAL_ACCESS_DENIED' ||
        c == 'TERMINAL_ADMIN_ONLY' ||
        c == 'TERMINAL_API_NOT_ALLOWED') {
      return true;
    }

    final m = message.trim().toLowerCase();
    if (m.isEmpty) return false;

    if (m.contains('access denied') ||
        m.contains('permission denied') ||
        m.contains('no permission') ||
        m.contains('forbidden') ||
        m.contains('unauthorized') ||
        message.contains('无权限') ||
        message.contains('权限不足')) {
      return true;
    }

    return false;
  }

  bool _isNonRetryableErrorCode(String code) {
    final c = code.trim().toUpperCase();
    return c == 'TERMINAL_SESSION_LIMIT_REACHED' ||
        c == 'TERMINAL_TAKEN_OVER' ||
        c == 'TERMINAL_DISABLED' ||
        c == 'TERMINAL_AUTH_REQUIRED' ||
        c == 'TERMINAL_INVALID_TOKEN' ||
        c == 'TOKEN_EXPIRED';
  }

  void resize(int cols, int rows) {
    if (!connected.value) return;
    _sendJson({'type': 'resize', 'cols': cols, 'rows': rows});
  }

  void _handleTerminalOutput(String data) {
    if (!connected.value) return;
    _sendJson({'type': 'input', 'data': data});
  }

  void _handleServerMessage(dynamic msg) {
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = null;
    final decoded = _tryParseJson(msg);
    final type = decoded?['type']?.toString() ?? '';
    if (connecting.value) {
      debugPrint(
        '[Terminal] 步骤3 完成: 收到服务端首条消息, type=${type.isEmpty ? "(raw)" : type}',
      );
    }
    connecting.value = false;
    if (decoded == null) {
      connected.value = true;
      statusText.value = '';
      _autoReconnectDisabled = false;
      _reconnectAttempt = 0;
      terminal.write(_asText(msg));
      return;
    }

    if (type == 'ready') {
      final nextSessionId = decoded['sessionId']?.toString() ?? '';
      if (_sessionId.isNotEmpty && _sessionId != nextSessionId) {
        _hasRenderedSessionContent = false;
      }
      _sessionId = nextSessionId;
      connected.value = true;
      statusText.value = '';
      _autoReconnectDisabled = false;
      _reconnectAttempt = 0;
      _triedWsSchemeFallback = false;
      return;
    }
    if (type == 'output') {
      _hasRenderedSessionContent = true;
      connected.value = true;
      statusText.value = '';
      _autoReconnectDisabled = false;
      _reconnectAttempt = 0;
      _triedWsSchemeFallback = false;
      terminal.write(decoded['data']?.toString() ?? '');
      return;
    }
    if (type == 'restore') {
      final restoredSessionId = decoded['sessionId']?.toString() ?? '';
      final restoreData = decoded['data']?.toString() ?? '';
      if (restoreData.isEmpty) return;
      if (_hasRenderedSessionContent &&
          _sessionId.isNotEmpty &&
          _sessionId == restoredSessionId) {
        return;
      }
      _sessionId = restoredSessionId.isEmpty ? _sessionId : restoredSessionId;
      _hasRenderedSessionContent = true;
      terminal.write(restoreData);
      return;
    }
    if (type == 'ping') {
      _sendJson({'type': 'ping'});
      return;
    }
    if (type == 'pong') {
      return;
    }
    if (type == 'exit') {
      connected.value = false;
      statusText.value = 'terminal_disconnected'.tr;
      _scheduleReconnect();
      return;
    }
    if (type == 'error') {
      final code = decoded['code']?.toString() ?? '';
      final message = decoded['message']?.toString() ?? '';
      debugPrint('[Terminal] 服务端返回 error: code=$code, message=$message');
      final noPermission = _isNoPermissionError(code: code, message: message);
      final nonRetryable = _isNonRetryableErrorCode(code);
      if (code.trim().toUpperCase() == 'TERMINAL_DISABLED') {
        _manualClose = true;
        _autoReconnectDisabled = true;
        if (message.isNotEmpty) {
          statusText.value = message;
          ToastUtil.show(message);
        }
      } else if (noPermission) {
        _manualClose = true;
        _autoReconnectDisabled = true;
        statusText.value = 'terminal_access_denied'.tr;
        ToastUtil.show('terminal_access_denied'.tr);
      } else if (code.trim().toUpperCase() == 'TERMINAL_TAKEN_OVER') {
        _manualClose = true;
        _autoReconnectDisabled = true;
        statusText.value = 'terminal_taken_over'.tr;
        ToastUtil.show('terminal_taken_over'.tr);
      } else if (nonRetryable) {
        _autoReconnectDisabled = true;
        if (message.isNotEmpty) {
          statusText.value = message;
        }
      } else if (message.isNotEmpty) {
        ToastUtil.show(message);
      }
      if (message.isNotEmpty) {
        terminal.write('\r\n$message\r\n');
      }
      connected.value = false;
      connecting.value = false;
      if (noPermission || nonRetryable) {
        _disposeChannel();
      }
      return;
    }
  }

  void _handleSocketDone() {
    debugPrint('[Terminal] WebSocket onDone: 连接已关闭');
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = null;
    _disposeChannel();
    connecting.value = false;
    connected.value = false;
    statusText.value = 'terminal_disconnected'.tr;
    _scheduleReconnect();
  }

  void _handleSocketError(Object error) {
    debugPrint('[Terminal] WebSocket onError: $error');
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = null;
    final raw = error.toString();
    if (!_triedWsSchemeFallback &&
        (raw.contains('WRONG_VERSION_NUMBER') ||
            raw.contains('HandshakeException'))) {
      final fallback = _buildWsSchemeFallbackUrl();
      if (fallback.isNotEmpty) {
        _triedWsSchemeFallback = true;
        _nextConnectUrlOverride = fallback;
        _disposeChannel();
        connecting.value = false;
        connected.value = false;
        _reconnectAttempt = 0;
        Timer(const Duration(milliseconds: 120), () {
          connect(manual: false);
        });
        return;
      }
    }
    final noPermission = _isNoPermissionError(code: '', message: raw);
    if (noPermission) {
      _manualClose = true;
      _autoReconnectDisabled = true;
      statusText.value = 'terminal_access_denied'.tr;
      ToastUtil.show('terminal_access_denied'.tr);
    }
    _disposeChannel();
    connecting.value = false;
    connected.value = false;
    if (!noPermission) {
      statusText.value = 'terminal_connection_failed'.tr;
      ToastUtil.show('terminal_connection_failed'.tr);
    }
    _scheduleReconnect();
  }

  String _buildWsSchemeFallbackUrl() {
    final baseRaw = ApiController.instance.baseUrl.trim();
    if (baseRaw.isEmpty) return '';
    final currentToken = (ApiController.instance.state.accessToken ?? '')
        .trim();
    Uri baseUri;
    try {
      baseUri = Uri.parse(baseRaw);
    } catch (_) {
      return '';
    }
    final wsScheme = baseUri.scheme == 'https' ? 'wss' : 'ws';
    final port = baseUri.hasPort
        ? baseUri.port
        : (wsScheme == 'wss' ? 443 : 80);
    final wsBase = Uri(
      scheme: wsScheme,
      host: baseUri.host,
      port: port,
      path: '',
    );
    final uri = wsBase.replace(
      path: '/api/terminal/connect',
      queryParameters: {
        'cols': '100',
        'rows': '30',
        if (currentToken.isNotEmpty) 'accessToken': currentToken,
        if (_clientDeviceId.isNotEmpty) 'clientDeviceId': _clientDeviceId,
        if (_terminalConnId.isNotEmpty) 'terminalConnId': _terminalConnId,
      },
    );
    return uri.toString();
  }

  void _scheduleReconnect() {
    if (_manualClose) return;
    if (_autoReconnectDisabled) return;
    if (_reconnectTimer != null) return;

    _reconnectAttempt += 1;
    final delayMs = _computeBackoffMs(_reconnectAttempt);
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      _reconnectTimer = null;
      connect(manual: false);
    });
  }

  int _computeBackoffMs(int attempt) {
    final exp = attempt > 8 ? 8 : attempt;
    final base = 500 * (1 << exp);
    final capped = base > 15000 ? 15000 : base;
    return capped;
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!connected.value) return;
      _sendJson({'type': 'ping'});
    });
  }

  void _disposeChannel() {
    try {
      _connectTimeoutTimer?.cancel();
      _connectTimeoutTimer = null;
    } catch (_) {}
    try {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
    } catch (_) {}
    try {
      _pingTimer?.cancel();
      _pingTimer = null;
    } catch (_) {}
    try {
      _sub?.cancel();
      _sub = null;
    } catch (_) {}
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  Map<String, dynamic>? _tryParseJson(dynamic msg) {
    try {
      final text = _asText(msg);
      final obj = jsonDecode(text);
      if (obj is Map) {
        return obj.map((k, v) => MapEntry(k.toString(), v));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String _asText(dynamic msg) {
    if (msg is String) return msg;
    if (msg is List<int>) return utf8.decode(msg);
    return msg?.toString() ?? '';
  }

  void _sendJson(Map<String, dynamic> obj) {
    try {
      _channel?.sink.add(jsonEncode(obj));
    } catch (_) {}
  }
}
