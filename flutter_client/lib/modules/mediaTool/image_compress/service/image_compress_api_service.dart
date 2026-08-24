import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart' as dio;
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import '../../../../core/api/api_controller.dart';
import '../../../../core/api/p2p_rtc_stub.dart'
    if (dart.library.html) '../../../../core/api/p2p_rtc_web.dart';
import '../../../../core/api/base_api_service.dart';
import '../../../../core/api/dio_bad_certificate_compat.dart';

class ImageCompressApiService {
  final dio.Dio _dio = createDioWithBadCertificateCompat(
    dio.BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );

  bool _shouldUseP2p(ApiController api) {
    return api.isP2pMode;
  }

  Future<Uint8List> _readMultipartFileBytes(dio.MultipartFile file) async {
    final builder = BytesBuilder(copy: false);
    final stream = file.finalize();
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Uint8List _buildMultipartBody({
    required String boundary,
    required String fieldName,
    required String filename,
    required Uint8List fileBytes,
    String fileContentType = 'application/octet-stream',
  }) {
    final builder = BytesBuilder(copy: false);
    final boundaryLine = '--$boundary\r\n';

    void writeString(String s) {
      builder.add(utf8.encode(s));
    }

    writeString(boundaryLine);
    writeString(
      'Content-Disposition: form-data; name="$fieldName"; filename="$filename"\r\n',
    );
    writeString('Content-Type: $fileContentType\r\n\r\n');
    builder.add(fileBytes);
    writeString('\r\n');
    writeString('--$boundary--\r\n');

    return builder.takeBytes();
  }

  Future<ApiResponse<Map<String, dynamic>>> uploadAndCompress({
    required dio.MultipartFile file,
    required Map<String, dynamic> query,
  }) async {
    final api = ApiController.instance;
    final token = api.accessToken;
    final url = '${api.baseUrl}/api/mediaTool/imageCompress/upload';

    try {
      if (_shouldUseP2p(api)) {
        final queryStrings = <String, String>{};
        query.forEach((k, v) {
          if (v == null) return;
          queryStrings[k.toString()] = v.toString();
        });

        final boundary =
            '----nascab_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 30)}';
        final fileBytes = await _readMultipartFileBytes(file);
        final filename = (file.filename ?? '').trim().isEmpty
            ? (queryStrings['fileName'] ?? 'file')
            : file.filename!;
        final contentType =
            file.contentType?.toString() ??
            (filename.toLowerCase().endsWith('.png')
                ? 'image/png'
                : filename.toLowerCase().endsWith('.webp')
                ? 'image/webp'
                : filename.toLowerCase().endsWith('.jpg') ||
                      filename.toLowerCase().endsWith('.jpeg')
                ? 'image/jpeg'
                : 'application/octet-stream');

        final bodyBytes = _buildMultipartBody(
          boundary: boundary,
          fieldName: 'file',
          filename: filename,
          fileBytes: fileBytes,
          fileContentType: contentType,
        );

        final uri = Uri.parse(url).replace(queryParameters: queryStrings);
        final req = http.Request('POST', uri);
        if (token != null && token.trim().isNotEmpty) {
          req.headers['authorization'] = 'Bearer $token';
        }
        req.headers['accept'] = 'application/json';
        req.headers['content-type'] = 'multipart/form-data; boundary=$boundary';
        req.bodyBytes = bodyBytes;

        final streamed = await api.sendP2pRequestOnChannel(
          req,
          timeout: const Duration(minutes: 5),
          channel: P2pRtcChannel.upload,
        );
        final bytes = await http.ByteStream(streamed.stream).toBytes();
        final code = streamed.statusCode;
        final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
        if (decoded is Map) {
          return ApiResponse<Map<String, dynamic>>.fromJson(
            code,
            Map<String, dynamic>.from(decoded),
            dataParser: (json, _) => json,
          );
        }
        return ApiResponse.failure('server_error'.tr, code: code);
      }

      final res = await _dio.post(
        url,
        data: dio.FormData.fromMap({'file': file}),
        queryParameters: query,
        options: dio.Options(
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        ),
      );

      final code = res.statusCode ?? 200;
      final data = res.data;
      if (data is Map) {
        return ApiResponse<Map<String, dynamic>>.fromJson(
          code,
          Map<String, dynamic>.from(data),
          dataParser: (json, _) => json,
        );
      }
      return ApiResponse.failure('server_error'.tr, code: code);
    } catch (e) {
      return ApiResponse.failure(e.toString(), code: -1);
    }
  }

  Future<Uint8List?> downloadFileBytes({
    required String serverPath,
    String? fileName,
  }) async {
    final api = ApiController.instance;
    final token = api.accessToken;
    final url = '${api.baseUrl}/api/mediaTool/imageCompress/file';

    if (_shouldUseP2p(api)) {
      final uri = Uri.parse(url).replace(
        queryParameters: {
          'path': serverPath,
          if (fileName != null) 'fileName': fileName,
        },
      );
      final req = http.Request('GET', uri);
      if (token != null && token.trim().isNotEmpty) {
        req.headers['authorization'] = 'Bearer $token';
      }
      final streamed = await api.sendP2pStreamRequest(
        req,
        timeout: const Duration(minutes: 5),
        channel: P2pRtcChannel.file,
      );
      final builder = BytesBuilder(copy: false);
      await for (final chunk in streamed.stream) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (streamed.status < 200 || streamed.status >= 300) {
        return null;
      }
      return Uint8List.fromList(bytes);
    }

    final res = await _dio.get<List<int>>(
      url,
      queryParameters: {
        'path': serverPath,
        if (fileName != null) 'fileName': fileName,
      },
      options: dio.Options(
        responseType: dio.ResponseType.bytes,
        headers: {if (token != null) 'Authorization': 'Bearer $token'},
      ),
    );

    final bytes = res.data;
    if (bytes == null) return null;
    return Uint8List.fromList(bytes);
  }

  Future<Uint8List?> downloadZipBytes({
    required int minTimeStamp,
    String? fileName,
  }) async {
    final api = ApiController.instance;
    final token = api.accessToken;
    final url = '${api.baseUrl}/api/mediaTool/imageCompress/zip';

    if (_shouldUseP2p(api)) {
      final uri = Uri.parse(url).replace(
        queryParameters: {
          'minTimeStamp': minTimeStamp.toString(),
          if (fileName != null) 'fileName': fileName,
        },
      );
      final req = http.Request('GET', uri);
      if (token != null && token.trim().isNotEmpty) {
        req.headers['authorization'] = 'Bearer $token';
      }
      final streamed = await api.sendP2pStreamRequest(
        req,
        timeout: const Duration(minutes: 10),
        channel: P2pRtcChannel.file,
      );
      final builder = BytesBuilder(copy: false);
      await for (final chunk in streamed.stream) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (streamed.status < 200 || streamed.status >= 300) {
        return null;
      }
      return Uint8List.fromList(bytes);
    }

    final res = await _dio.get<List<int>>(
      url,
      queryParameters: {
        'minTimeStamp': minTimeStamp,
        if (fileName != null) 'fileName': fileName,
      },
      options: dio.Options(
        responseType: dio.ResponseType.bytes,
        headers: {if (token != null) 'Authorization': 'Bearer $token'},
      ),
    );

    final bytes = res.data;
    if (bytes == null) return null;
    return Uint8List.fromList(bytes);
  }
}
