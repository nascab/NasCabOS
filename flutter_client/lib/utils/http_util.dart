import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/api/api_controller.dart';
import '../core/api/http_client_factory.dart'
    if (dart.library.html) '../core/api/http_client_factory_web.dart'
    if (dart.library.io) '../core/api/http_client_factory_io.dart';

/// API响应封装类，用于统一处理业务API响应
class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? message;
  final int? code;
  final dynamic rawResponse;

  ApiResponse({
    required this.success,
    this.data,
    this.message,
    this.code,
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
    dynamic rawResponse,
  }) {
    return ApiResponse<T>(
      success: false,
      message: message,
      code: code,
      rawResponse: rawResponse,
    );
  }

  /// 从JSON创建API响应
  factory ApiResponse.fromJson(
    Map<String, dynamic> json, {
    T Function(Map<String, dynamic>)? dataParser,
  }) {
    final success = json['success'] == true;
    final message = json['message']?.toString();
    final code = json['code'] as int?;

    T? data;
    if (success && dataParser != null) {
      try {
        // 如果提供了dataParser，总是尝试解析data字段
        // 即使data字段为null，也允许dataParser处理
        data = dataParser(json['data'] ?? {});
      } catch (e) {
        return ApiResponse.failure('数据解析失败: $e', code: code, rawResponse: json);
      }
    } else {
      data = json['data'] as T?;
    }

    return ApiResponse<T>(
      success: success,
      data: data,
      message: message,
      code: code,
      rawResponse: json,
    );
  }
}

/// 网络请求工具类
/// 提供统一的HTTP请求封装，包含错误处理、超时配置、重试机制等
class HttpUtil {
  static const Duration _defaultTimeout = Duration(seconds: 10);
  static const int _defaultMaxRetries = 2;
  static const Duration _defaultRetryDelay = Duration(milliseconds: 500);

  /// HTTP客户端实例（与 [BaseApiService] 一致，IO 端允许自签名 HTTPS）
  static final http.Client _client = createHttpClient();

  static bool _shouldUseP2p(Uri uri) {
    final origin = uri.origin.trim();
    if (origin.isEmpty) return false;
    if (origin != ApiController.p2pBaseUrl) return false;
    try {
      final api = ApiController.instance;
      return api.isP2pMode;
    } catch (_) {
      return false;
    }
  }

  static Future<http.Response> _sendRaw(
    String method,
    Uri uri, {
    Object? body,
    Map<String, String>? headers,
    Encoding? encoding,
    Duration? p2pTimeout,
  }) async {
    final upper = method.toUpperCase();
    if (_shouldUseP2p(uri)) {
      final req = http.Request(upper, uri);
      final mergedHeaders = <String, String>{};
      if (headers != null && headers.isNotEmpty) {
        mergedHeaders.addAll(headers);
      }
      if (body != null) {
        if (body is List<int>) {
          req.bodyBytes = body;
        } else if (body is String) {
          req.body = body;
        } else {
          final hasContentType = mergedHeaders.keys.any(
            (k) => k.toLowerCase() == 'content-type',
          );
          if (!hasContentType) {
            mergedHeaders['Content-Type'] = 'application/json; charset=utf-8';
          }
          req.body = jsonEncode(body);
        }
      }
      if (mergedHeaders.isNotEmpty) {
        req.headers.addAll(mergedHeaders);
      }
      final streamed = await ApiController.instance.sendP2pRequest(
        req,
        timeout: p2pTimeout,
      );
      final bytes = <int>[];
      await for (final chunk in streamed.stream) {
        bytes.addAll(chunk);
      }
      return http.Response.bytes(
        bytes,
        streamed.statusCode,
        headers: streamed.headers,
        request: req,
      );
    }

    switch (upper) {
      case 'GET':
        return _client.get(uri, headers: headers);
      case 'POST':
        return _client.post(
          uri,
          body: body,
          headers: headers,
          encoding: encoding,
        );
      case 'PUT':
        return _client.put(
          uri,
          body: body,
          headers: headers,
          encoding: encoding,
        );
      case 'DELETE':
        return _client.delete(uri, headers: headers);
      default:
        throw Exception('不支持的HTTP方法: $method');
    }
  }

  /// 发送GET请求
  /// [url] 请求URL
  /// [headers] 请求头
  /// [timeout] 超时时间，默认10秒
  /// [maxRetries] 最大重试次数，默认2次
  /// [retryDelay] 重试延迟，默认500毫秒
  static Future<HttpResponse> get(
    String url, {
    Map<String, String>? headers,
    Duration? timeout,
    int? maxRetries,
    Duration? retryDelay,
  }) async {
    final t = timeout ?? _defaultTimeout;
    return _requestWithRetry(
      () => _sendRaw('GET', Uri.parse(url), headers: headers, p2pTimeout: t),
      timeout: t,
      maxRetries: maxRetries ?? _defaultMaxRetries,
      retryDelay: retryDelay ?? _defaultRetryDelay,
    );
  }

  /// 发送POST请求
  /// [url] 请求URL
  /// [body] 请求体
  /// [headers] 请求头
  /// [encoding] 编码方式
  /// [timeout] 超时时间，默认10秒
  /// [maxRetries] 最大重试次数，默认2次
  /// [retryDelay] 重试延迟，默认500毫秒
  static Future<HttpResponse> post(
    String url, {
    Object? body,
    Map<String, String>? headers,
    Encoding? encoding,
    Duration? timeout,
    int? maxRetries,
    Duration? retryDelay,
  }) async {
    final t = timeout ?? _defaultTimeout;
    return _requestWithRetry(
      () => _sendRaw(
        'POST',
        Uri.parse(url),
        body: body,
        headers: headers,
        encoding: encoding,
        p2pTimeout: t,
      ),
      timeout: t,
      maxRetries: maxRetries ?? _defaultMaxRetries,
      retryDelay: retryDelay ?? _defaultRetryDelay,
    );
  }

  /// 带重试机制的请求封装
  static Future<HttpResponse> _requestWithRetry(
    Future<http.Response> Function() requestFn, {
    required Duration timeout,
    required int maxRetries,
    required Duration retryDelay,
  }) async {
    int attempt = 0;
    Exception? lastError;

    while (attempt <= maxRetries) {
      try {
        final response = await requestFn().timeout(timeout);
        return HttpResponse.success(response);
      } catch (error) {
        lastError = error is Exception ? error : Exception(error.toString());

        // 如果是最后一次尝试，直接抛出错误
        if (attempt >= maxRetries) {
          return HttpResponse.failure(lastError.toString());
        }

        // 等待一段时间后重试
        await Future.delayed(retryDelay);
        attempt++;
      }
    }

    return HttpResponse.failure(lastError.toString());
  }

  /// 关闭HTTP客户端
  static void close() {
    _client.close();
  }

  /// 高级API请求封装 - 发送API请求并返回标准化的ApiResponse
  /// [url] 请求URL
  /// [method] HTTP方法 (GET, POST, PUT, DELETE)
  /// [body] 请求体
  /// [headers] 请求头
  /// [dataParser] 数据解析器，用于将响应数据转换为特定类型
  /// [timeout] 超时时间
  /// [maxRetries] 最大重试次数
  static Future<ApiResponse<T>> apiRequest<T>(
    String url,
    String method, {
    Object? body,
    Map<String, String>? headers,
    T Function(Map<String, dynamic>)? dataParser,
    Duration? timeout,
    int? maxRetries,
  }) async {
    try {
      final t = timeout ?? _defaultTimeout;
      // 发送HTTP请求
      final httpResponse = await _requestWithRetry(
        () {
          final uri = Uri.parse(url);
          return _sendRaw(
            method,
            uri,
            body: body,
            headers: headers,
            encoding: utf8,
            p2pTimeout: t,
          );
        },
        timeout: t,
        maxRetries: maxRetries ?? _defaultMaxRetries,
        retryDelay: _defaultRetryDelay,
      );

      // 检查HTTP响应状态
      if (!httpResponse.isOk) {
        return ApiResponse.failure(
          'HTTP请求失败: ${httpResponse.statusCode} - ${httpResponse.errorMessage}',
          code: httpResponse.statusCode,
          rawResponse: httpResponse.body,
        );
      }

      // 解析JSON响应
      if (httpResponse.body == null || httpResponse.body!.isEmpty) {
        return ApiResponse.failure('响应体为空');
      }

      final jsonData = jsonDecode(httpResponse.body!);
      if (jsonData is! Map<String, dynamic>) {
        return ApiResponse.failure('响应格式无效');
      }
      // 使用ApiResponse.fromJson创建标准化响应
      return ApiResponse.fromJson(jsonData, dataParser: dataParser);
    } catch (e) {
      return ApiResponse.failure('请求异常: $e');
    }
  }

  /// 简化的GET API请求
  static Future<ApiResponse<T>> apiGet<T>(
    String url, {
    Map<String, String>? headers,
    T Function(Map<String, dynamic>)? dataParser,
    Duration? timeout,
    int? maxRetries,
  }) {
    return apiRequest(
      url,
      'GET',
      headers: headers,
      dataParser: dataParser,
      timeout: timeout,
      maxRetries: maxRetries,
    );
  }

  /// 简化的POST API请求
  static Future<ApiResponse<T>> apiPost<T>(
    String url, {
    Object? body,
    Map<String, String>? headers,
    T Function(Map<String, dynamic>)? dataParser,
    Duration? timeout,
    int? maxRetries,
  }) {
    return apiRequest(
      url,
      'POST',
      body: body,
      headers: headers,
      dataParser: dataParser,
      timeout: timeout,
      maxRetries: maxRetries,
    );
  }

  /// 简化的PUT API请求
  static Future<ApiResponse<T>> apiPut<T>(
    String url, {
    Object? body,
    Map<String, String>? headers,
    T Function(Map<String, dynamic>)? dataParser,
    Duration? timeout,
    int? maxRetries,
  }) {
    return apiRequest(
      url,
      'PUT',
      body: body,
      headers: headers,
      dataParser: dataParser,
      timeout: timeout,
      maxRetries: maxRetries,
    );
  }

  /// 简化的DELETE API请求
  static Future<ApiResponse<T>> apiDelete<T>(
    String url, {
    Map<String, String>? headers,
    T Function(Map<String, dynamic>)? dataParser,
    Duration? timeout,
    int? maxRetries,
  }) {
    return apiRequest(
      url,
      'DELETE',
      headers: headers,
      dataParser: dataParser,
      timeout: timeout,
      maxRetries: maxRetries,
    );
  }
}

/// HTTP响应封装类
class HttpResponse {
  final http.Response? response;
  final String? error;
  final bool isSuccess;

  HttpResponse._({this.response, this.error, required this.isSuccess});

  /// 创建成功的响应
  factory HttpResponse.success(http.Response response) {
    // print('请求成功: ${response.statusCode} ${response.body}');

    // 检查响应体中的success字段
    try {
      final responseBody = response.body;
      if (responseBody.isNotEmpty) {
        final jsonData = jsonDecode(responseBody);
        if (jsonData is Map && jsonData.containsKey('success')) {
          if (jsonData['success'] == false) {
            // 服务器返回了错误信息
            final errorMessage =
                jsonData['message']?.toString() ?? 'Unknown error';
            print('服务器返回错误: $errorMessage');
            return HttpResponse._(
              response: response,
              error: errorMessage,
              isSuccess: false,
            );
          }
        }
      }
    } catch (e) {
      // JSON解析失败，继续使用原始逻辑
      print('JSON解析失败: $e');
    }

    return HttpResponse._(response: response, error: null, isSuccess: true);
  }

  /// 创建失败的响应
  factory HttpResponse.failure(String error) {
    print('请求失败: $error');
    return HttpResponse._(response: null, error: error, isSuccess: false);
  }

  /// 获取响应状态码
  int? get statusCode => response?.statusCode;

  /// 获取响应体
  String? get body => response?.body;

  /// 获取JSON格式的响应体
  Map<String, dynamic>? get json {
    try {
      return response != null ? jsonDecode(response!.body) : null;
    } catch (e) {
      return null;
    }
  }

  /// 获取响应头
  Map<String, String>? get headers => response?.headers;

  /// 检查响应是否成功（状态码200-299）
  bool get isOk =>
      isSuccess &&
      statusCode != null &&
      statusCode! >= 200 &&
      statusCode! < 300;

  /// 获取错误信息
  String get errorMessage => error?.toString() ?? 'Unknown error';
}
