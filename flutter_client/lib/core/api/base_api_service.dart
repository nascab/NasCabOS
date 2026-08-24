import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import '../../utils/dialog_util.dart';
import '../../utils/toast_util.dart';
import '../../utils/user_agent_util.dart';
import '../languages/language_service.dart';
import '../routes/app_routes.dart';
import 'api_controller.dart';
import 'api_error_localizer.dart';
import 'http_client_factory.dart'
    if (dart.library.html) 'http_client_factory_web.dart'
    if (dart.library.io) 'http_client_factory_io.dart';

/// 基础API服务类，基于http库实现统一的网络请求管理
abstract class BaseApiService {
  ApiController get apiController => ApiController.instance;

  /// 避免 refreshJwt 并行 401 等原因导致同一提示多次入队堆叠。
  static bool _sessionExpiredDialogGate = false;

  // 默认配置
  static const Duration defaultTimeout = Duration(seconds: 10);
  static const int defaultMaxRetries = 1;
  static const Duration defaultRetryDelay = Duration(milliseconds: 500);

  // ── 网络异常弹窗（全局去重） ──
  /// 连续请求失败计数
  static int _consecutiveFailCount = 0;
  /// 失败计数达此阈值时弹出提示
  static const int _failCountDialogThreshold = 2;
  /// 网络异常对话框是否正在显示
  static bool _networkIssueDialogShowing = false;
  /// 用于取消已显示的对话框（当请求恢复时）
  static Completer<void>? _networkIssueDialogDismissCompleter;

  /// 创建HTTP客户端，区分平台处理
  /// Web端使用标准http.Client，其他平台使用支持自签名证书的客户端
  http.Client _createClient() {
    return createHttpClient();
  }

  bool _shouldUseP2pProxy() {
    return apiController.baseUrl.trim() == ApiController.p2pBaseUrl;
  }

  Future<http.Response> _sendInterceptedRequest(
    http.BaseRequest request, {
    Duration? timeout,
    Future<void>? cancelFuture,
  }) async {
    if (_shouldUseP2pProxy()) {
      final streamed = await apiController.sendP2pRequest(
        request,
        timeout: timeout,
        cancelFuture: cancelFuture,
      );
      return http.Response.fromStream(streamed);
    }

    final client = _createClient();
    try {
      final streamed = await client
          .send(request)
          .timeout(timeout ?? defaultTimeout);
      return await http.Response.fromStream(streamed);
    } finally {
      client.close();
    }
  }

  /// 请求拦截器，用于在发送请求前添加认证信息等
  Future<http.BaseRequest> _requestInterceptor(http.BaseRequest request) async {
    final accessToken = apiController.accessToken;
    if (accessToken != null) {
      request.headers['Authorization'] = 'Bearer $accessToken';
    }

    // 添加User-Agent
    try {
      final userAgent = await UserAgentUtil.getUserAgent();
      request.headers['User-Agent'] = userAgent;
    } catch (e) {
      print('获取User-Agent失败: $e');
    }
    // 添加语言设置 (Accept-Language)
    try {
      // 获取当前语言代码，并将下划线转换为中划线 (例如 zh_CN -> zh-CN)
      // 这样符合标准HTTP头格式，也符合服务端解析逻辑
      final currentLocale = LanguageService.to.currentLocale;
      final acceptLanguage = currentLocale.replaceAll('_', '-');
      request.headers['Accept-Language'] = acceptLanguage;
    } catch (e) {
      print('获取语言设置失败: $e');
    }

    print('请求URL: ${request.url}');
    return request;
  }

  /// 刷新 token 接口返回 401 时：弹窗提示登录已过期，确认后（非 web）跳转服务器列表
  void _showTokenExpiredDialogAndNavigate() {
    if (_sessionExpiredDialogGate) return;
    _sessionExpiredDialogGate = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final ctx = Get.overlayContext;
      if (ctx == null || !ctx.mounted) {
        _sessionExpiredDialogGate = false;
        return;
      }
      final contentWidget = ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 400),
        child: SingleChildScrollView(
          child: Text('service_nascab_session_expired'.tr),
        ),
      );
      showDialog<void>(
        context: ctx,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return DialogUtil.createAlertDialog(
            title: Text('tip'.tr),
            content: contentWidget,
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  if (!kIsWeb) {
                    AppRoutes.toServerList();
                  }
                },
                child: Text('ok'.tr),
              ),
            ],
          );
        },
      ).whenComplete(() => _sessionExpiredDialogGate = false);
    });
  }

  /// 响应拦截器，处理token过期等场景
  Future<http.Response> _responseInterceptor(
    http.BaseRequest request,
    http.Response response, {
    Duration? timeout,
    Future<void>? cancelFuture,
  }) async {
    if (response.statusCode == 401) {
      try {
        final bodyText = utf8.decode(response.bodyBytes);
        final jsonBody = jsonDecode(bodyText);
        if (jsonBody is Map<String, dynamic>) {
          final code = jsonBody['code']?.toString();
          if (code == 'twofa.TWO_FACTOR_REQUIRED') {
            return response;
          }
        }
      } catch (_) {}

      // 检查当前请求的URL是否是刷新token的接口，避免无限循环
      final requestUrl = request.url.toString();
      if (requestUrl.contains('/api/auth/refreshJwt')) {
        // 如果是刷新token接口本身返回401，说明 token 已过期，弹窗提示并（非 web）跳转服务器列表
        print('刷新token接口返回401，不再尝试刷新');
        _showTokenExpiredDialogAndNavigate();
        return response;
      }

      // Token过期，尝试刷新
      final refreshed = await apiController.refreshAuthToken();
      if (refreshed) {
        final cloned = _cloneRequest(request);
        final newRequest = await _requestInterceptor(cloned);
        return await _sendInterceptedRequest(
          newRequest,
          timeout: timeout,
          cancelFuture: cancelFuture,
        );
      } else {
        // 刷新jwt失败，跳转到登录页
        // Get.offAllNamed('/server_list');
        print('刷新token失败，跳转到登录页');
      }
      return response;
    }
    return response;
  }

  http.BaseRequest _cloneRequest(http.BaseRequest request) {
    if (request is http.Request) {
      final cloned = http.Request(request.method, request.url);
      cloned.headers.addAll(request.headers);
      cloned.bodyBytes = request.bodyBytes;
      cloned.encoding = request.encoding;
      return cloned;
    }
    final cloned = http.Request(request.method, request.url);
    cloned.headers.addAll(request.headers);
    return cloned;
  }

  /// 获取完整的API URL
  String getApiUrl(String endpoint) {
    return '${apiController.baseUrl}$endpoint';
  }

  /// 检查网络连接状态
  Future<bool> checkConnection() async {
    try {
      final response = await apiGet<dynamic>('/health');
      return response.success;
    } catch (e) {
      return false;
    }
  }

  /// 处理API错误
  String handleApiError(dynamic error) {
    return '网络请求异常: ${error.message}';
  }

  /// 带重试机制的API请求封装
  /// [cancelFuture] 若在请求完成前 complete，会取消 P2P 请求并通知后端（仅 P2P 模式生效）
  Future<ApiResponse<T>> apiRequest<T>(
    String method,
    String endpoint, {
    dynamic body,
    Map<String, String>? headers,
    Map<String, String>? queryParams,
    T Function(Map<String, dynamic>, int)? dataParser,
    Duration? timeout,
    int? maxRetries,
    Duration? retryDelay,
    bool showLoading = true,
    String loadingMsg = "Loading...",
    Future<void>? cancelFuture,
    bool showNetworkIssueOnFailure = true,
  }) async {
    if (showLoading) {
      DialogUtil.showLoading(message: loadingMsg);
    }
    int attempt = 0;
    bool twofaRetried = false;
    final maxAttempts = (maxRetries ?? defaultMaxRetries) + 1;
    Exception? lastError;
    while (attempt < maxAttempts) {
      try {
        // 发送HTTP请求
        final response = await _sendRequest(
          method,
          endpoint,
          body: body,
          headers: headers,
          queryParams: queryParams,
          timeout: timeout,
          cancelFuture: cancelFuture,
        );
        if (!twofaRetried && method.toUpperCase() == 'POST') {
          final jsonBody = _tryParseJsonMap(response.body);
          if (jsonBody != null &&
              jsonBody['code']?.toString() == 'twofa.TWO_FACTOR_REQUIRED') {
            if (showLoading) {
              DialogUtil.dismissLoading();
            }
            final twofaCode = await _promptTwofaCode();
            if (twofaCode == null) {
              return ApiResponse.failure(
                'cancel'.tr,
                code: response.statusCode,
                rawResponse: jsonBody,
              );
            }
            final nextBody = await _attachTwofaCode(body, twofaCode);
            twofaRetried = true;
            final retryResponse = await _sendRequest(
              method,
              endpoint,
              body: nextBody,
              headers: headers,
              queryParams: queryParams,
              timeout: timeout,
              cancelFuture: cancelFuture,
            );
            final retryResult = _handleHttpResponse<T>(
              retryResponse,
              dataParser: dataParser,
            );
            _onRequestSucceeded();
            return retryResult;
          }
        }
        // 处理HTTP响应
        final result = _handleHttpResponse<T>(
          response,
          dataParser: dataParser,
        );
        _onRequestSucceeded();
        return result;
      } catch (error) {
        print('请求失败，尝试次数: $attempt, 错误: $error');
        lastError = error is Exception ? error : Exception(error.toString());
        attempt++;

        // 如果是最后一次尝试，返回错误并累计失败计数
        if (attempt >= maxAttempts) {
          if (showNetworkIssueOnFailure) {
            _onRequestFailed();
          }
          return ApiResponse.failure(handleApiError(lastError), code: -1);
        }

        // 等待一段时间后重试
        await Future.delayed(retryDelay ?? defaultRetryDelay);
      } finally {
        if (showLoading) {
          DialogUtil.dismissLoading();
        }
      }
    }
    return ApiResponse.failure(
      '请求失败: ${lastError?.toString() ?? "未知错误"}',
      code: -1,
    );
  }

  /// 发送HTTP请求
  /// [cancelFuture] 若在请求完成前 complete，会取消 P2P 请求并通知后端
  Future<http.Response> _sendRequest(
    String method,
    String endpoint, {
    dynamic body,
    Map<String, String>? headers,
    Map<String, String>? queryParams,
    Duration? timeout,
    Future<void>? cancelFuture,
  }) async {
    final requestHeaders = {...?headers};

    // 设置请求体
    dynamic requestBody = body;
    if (_shouldAttachDeviceFingerprint(method, endpoint) && body is Map) {
      final m = Map<String, dynamic>.from(body);
      if (!m.containsKey('device_fingerprint')) {
        try {
          m['device_fingerprint'] =
              await UserAgentUtil.getDeviceFingerprintPayload();
        } catch (e) {
          print('获取device_fingerprint失败: $e');
        }
      }
      requestBody = m;
    }
    if (requestBody != null && requestBody is! String) {
      requestBody = jsonEncode(requestBody);
      // 明确设置Content-Type为application/json
      requestHeaders['Content-Type'] = 'application/json';
    }

    // 构建完整的API URL
    final fullUrl = getApiUrl(endpoint);

    Uri uri = Uri.parse(fullUrl);
    if (queryParams != null) {
      uri = uri.replace(queryParameters: queryParams);
    }

    // 创建基础请求
    http.BaseRequest baseRequest;
    switch (method.toUpperCase()) {
      case 'GET':
        baseRequest = http.Request('GET', uri);
        break;
      case 'POST':
        baseRequest = http.Request('POST', uri);
        if (requestBody != null) {
          (baseRequest as http.Request).body = requestBody;
        }
        break;
      default:
        throw Exception('不支持的HTTP方法: $method');
    }

    // 设置请求头
    baseRequest.headers.addAll(requestHeaders);

    // 应用请求拦截器
    final interceptedRequest = await _requestInterceptor(baseRequest);

    final response = await _sendInterceptedRequest(
      interceptedRequest,
      timeout: timeout,
      cancelFuture: cancelFuture,
    );
    return await _responseInterceptor(
      interceptedRequest,
      response,
      timeout: timeout,
      cancelFuture: cancelFuture,
    );
  }

  bool _shouldAttachDeviceFingerprint(String method, String endpoint) {
    if (method.toUpperCase() != 'POST') return false;
    if (endpoint.startsWith('/api/user/2fa/enable')) return true;
    if (endpoint.startsWith('/api/user/update')) return true;
    if (endpoint.startsWith('/api/user/create')) return true;
    if (endpoint.startsWith('/api/user/delete')) return true;
    if (endpoint.startsWith('/api/auth/recoverPassword')) return true;
    if (endpoint == '/api/user/2fa/reset') return true;
    return false;
  }

  Map<String, dynamic>? _tryParseJsonMap(String text) {
    final raw = text.trim();
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  Future<String?> _promptTwofaCode() async {
    if (Get.overlayContext == null) return null;
    return DialogUtil.showInputDialog(
      title: 'auth_2fa_title'.tr,
      content: 'auth_2fa_code_label'.tr,
      validator: (v) {
        final s = v?.trim() ?? '';
        if (s.isEmpty) return 'auth_2fa_code_required'.tr;
        return null;
      },
    );
  }

  Future<dynamic> _attachTwofaCode(dynamic originalBody, String code) async {
    if (originalBody == null) {
      return {
        'code': code,
        'device_fingerprint': await UserAgentUtil.getDeviceFingerprintPayload(),
      };
    }
    if (originalBody is Map) {
      final next = Map<String, dynamic>.from(originalBody);
      next['code'] = code;
      if (!next.containsKey('device_fingerprint')) {
        try {
          next['device_fingerprint'] =
              await UserAgentUtil.getDeviceFingerprintPayload();
        } catch (_) {}
      }
      return next;
    }
    if (originalBody is String) {
      try {
        final decoded = jsonDecode(originalBody);
        if (decoded is Map) {
          final next = Map<String, dynamic>.from(decoded);
          next['code'] = code;
          if (!next.containsKey('device_fingerprint')) {
            try {
              next['device_fingerprint'] =
                  await UserAgentUtil.getDeviceFingerprintPayload();
            } catch (_) {}
          }
          return next;
        }
      } catch (_) {}
    }
    return originalBody;
  }

  /// 处理HTTP响应
  ApiResponse<T> _handleHttpResponse<T>(
    http.Response response, {
    T Function(Map<String, dynamic>, int)? dataParser,
  }) {
    // 解析响应体
    try {
      String responseBody;
      try {
        responseBody = response.body;
      } catch (e) {
        final bytes = response.bodyBytes;
        final ct = response.headers['content-type'] ?? '';
        final ce = response.headers['content-encoding'] ?? '';
        final url = response.request?.url.toString() ?? '';
        final n = bytes.length < 24 ? bytes.length : 24;
        final sb = StringBuffer();
        for (var i = 0; i < n; i++) {
          final h = bytes[i].toRadixString(16).padLeft(2, '0');
          if (i > 0) sb.write(' ');
          sb.write(h);
        }
        print('响应body解码失败: $e');
        print(
          'status=${response.statusCode} len=${bytes.length} ct=$ct ce=$ce url=$url head=${sb.toString()}',
        );
        rethrow;
      }
      if (responseBody.isEmpty) {
        print("responseBody为空");
        return ApiResponse.failure('network_failure'.tr);
      }

      // 解析JSON响应体
      Map<String, dynamic> jsonBody;
      try {
        jsonBody = jsonDecode(responseBody) as Map<String, dynamic>;
      } catch (e) {
        print("JSON解析失败: $e");
        print("原始响应体: $responseBody");
        return ApiResponse.failure('network_failure'.tr);
      }

      // 使用ApiResponse.fromJson创建标准化响应
      return ApiResponse.fromJson(
        response.statusCode,
        jsonBody,
        dataParser: dataParser,
      );
    } catch (e) {
      print('响应解析失败: $e');
      return ApiResponse.failure('network_failure'.tr);
    }
  }

  /// GET API请求
  /// [cancelFuture] 若在请求完成前 complete，会取消 P2P 请求并通知后端
  Future<ApiResponse<T>> apiGet<T>(
    String endpoint, {
    Map<String, String>? headers,
    Map<String, String>? queryParams,
    T Function(Map<String, dynamic>, int)? dataParser,
    Duration? timeout,
    int? maxRetries,
    bool showLoading = true,
    String loadingMsg = "",
    Future<void>? cancelFuture,
    bool showNetworkIssueOnFailure = true,
  }) {
    if (loadingMsg == "") {
      loadingMsg = "loading".tr;
    }
    return apiRequest<T>(
      'GET',
      endpoint,
      headers: headers,
      queryParams: queryParams,
      dataParser: dataParser,
      timeout: timeout,
      maxRetries: maxRetries,
      showLoading: showLoading,
      loadingMsg: loadingMsg,
      cancelFuture: cancelFuture,
      showNetworkIssueOnFailure: showNetworkIssueOnFailure,
    );
  }

  /// POST API请求
  /// [cancelFuture] 若在请求完成前 complete，会取消 P2P 请求并通知后端
  Future<ApiResponse<T>> apiPost<T>(
    String endpoint, {
    dynamic body,
    Map<String, String>? headers,
    Map<String, String>? queryParams,
    T Function(Map<String, dynamic>, int)? dataParser,
    Duration? timeout,
    int? maxRetries,
    bool showLoading = true,
    String loadingMsg = "",
    Future<void>? cancelFuture,
    bool showNetworkIssueOnFailure = true,
  }) {
    if (loadingMsg == "") {
      loadingMsg = "loading".tr;
    }
    return apiRequest<T>(
      'POST',
      endpoint,
      body: body,
      headers: headers,
      queryParams: queryParams,
      dataParser: dataParser,
      timeout: timeout,
      maxRetries: maxRetries,
      showLoading: showLoading,
      loadingMsg: loadingMsg,
      cancelFuture: cancelFuture,
      showNetworkIssueOnFailure: showNetworkIssueOnFailure,
    );
  }

  Future<http.Response> rawRequest(
    String method,
    String endpoint, {
    dynamic body,
    Map<String, String>? headers,
    Map<String, String>? queryParams,
    Duration? timeout,
  }) {
    return _sendRequest(
      method,
      endpoint,
      body: body,
      headers: headers,
      queryParams: queryParams,
      timeout: timeout,
    );
  }

  // ── 网络异常弹窗逻辑 ──

  /// 请求最终失败时调用，累计失败计数并尝试弹出切换通道提示。
  static void _onRequestFailed() {
    _consecutiveFailCount++;
    if (_consecutiveFailCount >= _failCountDialogThreshold &&
        !_networkIssueDialogShowing) {
      _showNetworkIssueDialog();
    }
  }

  /// 请求成功时调用，重置失败计数；若对话框正在显示则自动关闭并 toast 提示恢复。
  static void _onRequestSucceeded() {
    _consecutiveFailCount = 0;
    if (_networkIssueDialogShowing) {
      _networkIssueDialogShowing = false;
      final completer = _networkIssueDialogDismissCompleter;
      _networkIssueDialogDismissCompleter = null;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
      ToastUtil.show('network_recovered'.tr);
    }
  }

  /// 显示「网络似乎出现问题」对话框（全局去重，仅允许一个实例）。
  static void _showNetworkIssueDialog() {
    _networkIssueDialogShowing = true;
    _networkIssueDialogDismissCompleter = Completer<void>();

    final dismissFuture = _networkIssueDialogDismissCompleter!.future;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      // 在 postFrameCallback 之前对话框可能已被关闭
      if (!_networkIssueDialogShowing) return;
      final ctx = Get.overlayContext;
      if (ctx == null || !ctx.mounted) {
        _networkIssueDialogShowing = false;
        _networkIssueDialogDismissCompleter = null;
        return;
      }

      showDialog<bool>(
        context: ctx,
        barrierDismissible: true,
        builder: (BuildContext dialogContext) {
          return DialogUtil.createAlertDialog(
            title: Text('network_issue_title'.tr),
            content: Text('network_issue_content'.tr),
            actions: [
              TextButton(
                onPressed: () {
                  _networkIssueDialogShowing = false;
                  _networkIssueDialogDismissCompleter = null;
                  Navigator.of(dialogContext).pop();
                },
                child: Text('cancel'.tr),
              ),
              TextButton(
                onPressed: () {
                  _networkIssueDialogShowing = false;
                  _networkIssueDialogDismissCompleter = null;
                  Navigator.of(dialogContext).pop();
                  // 主动触发通道切换
                  ApiController.instance.refreshConnectChannel();
                },
                child: Text('dev_switch'.tr),
              ),
            ],
          );
        },
      ).then((_) {
        // 点击背景或系统返回键关闭时清理状态
        _networkIssueDialogShowing = false;
        _networkIssueDialogDismissCompleter = null;
      });

      // 监听外部关闭信号（请求恢复时自动关闭）
      dismissFuture.then((_) {
        if (ctx.mounted) {
          Navigator.of(ctx).popUntil((route) => route is! PopupRoute);
        }
      });
    });
  }
}

/// API响应封装类，用于统一处理业务API响应
class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? message;
  /// HTTP 状态码（来自 [http.Response.statusCode]）。
  final int? code;
  /// 响应体中的业务错误键（[ResponseUtil.error] 的 `code` 字段），成功时一般为 null。
  final String? apiErrorKey;
  final dynamic rawResponse;

  ApiResponse({
    required this.success,
    this.data,
    this.message,
    this.code,
    this.apiErrorKey,
    this.rawResponse,
  });

  /// 创建成功的API响应
  factory ApiResponse.success(
    T data, {
    String? message,
    int? code,
    dynamic rawResponse,
  }) {
    return ApiResponse<T>(
      success: true,
      data: data,
      message: message,
      code: code,
      rawResponse: rawResponse,
    );
  }

  /// 创建失败的API响应
  factory ApiResponse.failure(
    String message, {
    int? code,
    String? apiErrorKey,
    dynamic rawResponse,
  }) {
    return ApiResponse<T>(
      success: false,
      message: message,
      code: code,
      apiErrorKey: apiErrorKey,
      rawResponse: rawResponse,
    );
  }

  /// 从JSON创建API响应
  factory ApiResponse.fromJson(
    int httpStatus,
    Map<String, dynamic> json, {
    T Function(Map<String, dynamic>, int)? dataParser,
  }) {
    // 兼容 success 为 bool 或字符串 "true"，以及 code == 0 表示成功
    final rawSuccess = json['success'];
    final success =
        rawSuccess == true || rawSuccess == 'true' || json['code'] == 0;

    String? apiErrorKey;
    final rawBizCode = json['code'];
    if (rawBizCode is String && rawBizCode.isNotEmpty) {
      apiErrorKey = rawBizCode;
    }

    String? message = json['message']?.toString();
    if (apiErrorKey == 'service.NASCAB_SESSION_EXPIRED') {
      message = 'service_nascab_session_expired'.tr;
    } else if (!success) {
      message = ApiErrorLocalizer.localize(
        apiErrorKey: apiErrorKey,
        serverMessage: message,
      );
    }
    T? data;
    if (success && dataParser != null) {
      try {
        data = dataParser(json['data'] ?? {}, httpStatus);
      } catch (e) {
        return ApiResponse.failure(
          '数据解析失败: $e',
          code: httpStatus,
          rawResponse: json,
          apiErrorKey: apiErrorKey,
        );
      }
    } else {
      data = json['data'] as T?;
    }

    return ApiResponse<T>(
      success: success,
      data: data,
      message: message,
      rawResponse: json,
      code: httpStatus,
      apiErrorKey: apiErrorKey,
    );
  }
}
