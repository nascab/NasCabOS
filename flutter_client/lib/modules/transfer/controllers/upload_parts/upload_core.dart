import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart' as dio;
import 'package:flutter/foundation.dart';
import 'package:cross_file/cross_file.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../../../../core/api/api_controller.dart';
import '../../../../core/api/p2p_rtc_stub.dart'
    if (dart.library.html) '../../../../core/api/p2p_rtc_web.dart';
import 'upload_transfer_helper.dart';
import 'upload_web_file_helper.dart';

/// 上传核心逻辑处理器
/// 封装了单文件分块上传的核心逻辑
class UploadCore {
  static const int _p2pRelayChunkCeilingBytes = 256 * 1024;
  static const int _p2pDirectChunkCeilingBytes = 8 * 1024 * 1024;
  static const int _p2pRelayMinChunkBytes = 64 * 1024;

  static bool _containsTraversalSegments(String raw) {
    final s = raw.trim().replaceAll('\\', '/');
    if (s.isEmpty) return false;
    for (final seg in s.split('/')) {
      if (seg == '..') return true;
    }
    return false;
  }

  static bool _isAbsoluteWindowsPath(String raw) {
    return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(raw.trim());
  }

  static void _validateUploadPaths({
    required String remotePath,
    required String fileName,
    String? relativePath,
  }) {
    final r = remotePath.trim();
    if (r.isEmpty) throw Exception('api_code_file_invalid_params'.tr);
    if (r.contains('\u0000')) {
      throw Exception('api_code_file_invalid_params'.tr);
    }
    if (_containsTraversalSegments(r)) {
      throw Exception('api_code_file_invalid_params'.tr);
    }

    final n = fileName.trim();
    if (n.isEmpty) throw Exception('api_code_file_invalid_params'.tr);
    if (n.contains('\u0000')) {
      throw Exception('api_code_file_invalid_params'.tr);
    }
    if (n.contains('/') || n.contains('\\')) {
      throw Exception('api_code_file_invalid_params'.tr);
    }

    if (relativePath == null) return;
    final rel = relativePath.trim();
    if (rel.isEmpty) return;
    if (rel.contains('\u0000')) {
      throw Exception('api_code_file_invalid_params'.tr);
    }
    if (rel.startsWith('/') || _isAbsoluteWindowsPath(rel)) {
      throw Exception('api_code_file_invalid_params'.tr);
    }
    if (_containsTraversalSegments(rel)) {
      throw Exception('api_code_file_invalid_params'.tr);
    }
  }

  static int _normalizeP2pChunkSize({
    required int chunkSize,
    required bool isP2p,
    required bool isRelay,
  }) {
    if (!isP2p) return chunkSize;
    final maxP2pChunk = isRelay
        ? _p2pRelayChunkCeilingBytes
        : _p2pDirectChunkCeilingBytes;
    var normalized = chunkSize;
    if (normalized > maxP2pChunk) normalized = maxP2pChunk;
    if (isRelay && normalized < _p2pRelayMinChunkBytes) {
      normalized = _p2pRelayMinChunkBytes;
    }
    return normalized;
  }

  static int _nextRelayChunkSize(int chunkSize) {
    final next = chunkSize ~/ 2;
    if (next < _p2pRelayMinChunkBytes) return _p2pRelayMinChunkBytes;
    return next;
  }

  static bool _isRetryableRelayUploadError(Object error) {
    final text = UploadTransferHelper.getServerMessage(error).toLowerCase();
    return text.contains('bad_gateway') ||
        text.contains('request_body_too_large') ||
        text.contains('request_timeout') ||
        text.contains('upload_chunk_http_502') ||
        text.contains('upload_chunk_http_413') ||
        text.contains('upload_chunk_http_408');
  }

  static Uint8List _buildMultipartBody({
    required String boundary,
    required Map<String, String> fields,
    required String fileField,
    required String filename,
    required Uint8List fileBytes,
    String fileContentType = 'application/octet-stream',
  }) {
    final builder = BytesBuilder(copy: false);
    final boundaryLine = '--$boundary\r\n';

    void writeString(String s) {
      builder.add(utf8.encode(s));
    }

    fields.forEach((k, v) {
      writeString(boundaryLine);
      writeString('Content-Disposition: form-data; name="$k"\r\n\r\n');
      writeString(v);
      writeString('\r\n');
    });

    writeString(boundaryLine);
    writeString(
      'Content-Disposition: form-data; name="$fileField"; filename="$filename"\r\n',
    );
    writeString('Content-Type: $fileContentType\r\n\r\n');
    builder.add(fileBytes);
    writeString('\r\n');

    writeString('--$boundary--\r\n');
    return builder.takeBytes();
  }

  /// 上传单个文件的核心逻辑
  ///
  /// 返回已处理的字节数
  static Future<int> processFile({
    required dio.Dio dioClient,
    required String baseUrl,
    required String token,
    required dynamic fileRef,
    required String fileName,
    required int fileSize,
    required String remotePath,
    required String nameStrategy,
    String? saveType,
    required String fileHash,
    required dio.CancelToken cancelToken,
    required Function(int increment) onProgress,
    String? relativePath,
    Function(String relPath)? onCompleted,
    Function(String relPath)? onSkipped,
    int? chunkSizeOverride,
    Function()? onUiRefresh,
    int? fileMtimeMs,
    int? fileBirthtimeMs,
  }) async {
    int processedSize = 0;
    _validateUploadPaths(
      remotePath: remotePath,
      fileName: fileName,
      relativePath: relativePath,
    );
    final isP2p = baseUrl.trim() == ApiController.p2pBaseUrl;
    final isRelayP2p =
        isP2p &&
        ApiController.instance.p2pTransportKind == P2pTransportKind.relay;
    final normalizedSaveType =
        (saveType == 'year' || saveType == 'month' || saveType == 'day')
        ? saveType
        : null;
    var chunkSize = _normalizeP2pChunkSize(
      chunkSize:
          chunkSizeOverride ??
          UploadTransferHelper.calculateChunkSize(fileSize),
      isP2p: isP2p,
      isRelay: isRelayP2p,
    );
    final sessionHash = '${fileHash}_$chunkSize';
    final totalChunks = (fileSize / chunkSize).ceil();
    var reportedNewProgress = false;

    // 1. 检查分块
    List<int> uploadedChunks = [];
    try {
      if (isP2p) {
        final req = http.Request(
          'POST',
          Uri.parse('$baseUrl/api/file/upload/check'),
        );
        req.headers['authorization'] = 'Bearer $token';
        req.headers['content-type'] = 'application/json; charset=utf-8';
        req.headers['accept'] = 'application/json';
        req.body = jsonEncode({
          'hash': sessionHash,
          'targetDir': remotePath,
          'chunkSize': chunkSize,
          'fileName': fileName,
          'relativePath': relativePath,
          'nameStrategy': nameStrategy,
          if (normalizedSaveType != null) 'saveType': normalizedSaveType,
          'totalChunks': totalChunks,
          if (fileMtimeMs != null) 'mtimeMs': fileMtimeMs,
          if (fileBirthtimeMs != null) 'birthtimeMs': fileBirthtimeMs,
        });

        final streamed = await ApiController.instance.sendP2pRequestOnChannel(
          req,
          timeout: const Duration(minutes: 2),
          channel: P2pRtcChannel.upload,
          cancelFuture: cancelToken.whenCancel,
        );
        final bytes = await http.ByteStream(streamed.stream).toBytes();
        final text = utf8.decode(bytes, allowMalformed: true);
        final decoded = jsonDecode(text);
        if (decoded is! Map) {
          throw Exception('invalid_response');
        }
        if (decoded['success'] != true) {
          final code = decoded['code']?.toString() ?? '';
          if (code == 'file.FILE_EXISTS') {
            onSkipped?.call(relativePath ?? fileName);
            onCompleted?.call(relativePath ?? fileName);
            return fileSize;
          }
          throw Exception(
            decoded['message']?.toString() ?? 'upload_check_failed',
          );
        }
        final data = decoded['data'];
        if (data is Map && data['uploadedChunks'] is List) {
          uploadedChunks = List<int>.from(data['uploadedChunks'] as List);
        } else {
          uploadedChunks = [];
        }
      } else {
        final checkRes = await dioClient.post(
          '$baseUrl/api/file/upload/check',
          data: {
            'hash': sessionHash,
            'targetDir': remotePath,
            'chunkSize': chunkSize,
            'fileName': fileName,
            'relativePath': relativePath,
            'nameStrategy': nameStrategy,
            if (normalizedSaveType != null) 'saveType': normalizedSaveType,
            'totalChunks': totalChunks,
            if (fileMtimeMs != null) 'mtimeMs': fileMtimeMs,
            if (fileBirthtimeMs != null) 'birthtimeMs': fileBirthtimeMs,
          },
          options: dio.Options(headers: {'Authorization': 'Bearer $token'}),
          cancelToken: cancelToken,
        );
        final raw = checkRes.data;
        final data = raw is Map ? raw['data'] : null;
        final list = data is Map ? data['uploadedChunks'] : null;
        if (list is List) {
          uploadedChunks = List<int>.from(list);
        } else {
          uploadedChunks = [];
        }
      }
    } catch (e) {
      if (UploadTransferHelper.isFileExistsError(e)) {
        onSkipped?.call(relativePath ?? fileName);
        onCompleted?.call(relativePath ?? fileName);
        return fileSize; // 返回全部大小作为已处理
      }
      rethrow;
    }

    // 更新初始进度
    processedSize = uploadedChunks.length * chunkSize;
    if (processedSize > fileSize) processedSize = fileSize;
    // 这里我们不调用onProgress，因为调用者可能已经计算了初始processedSize
    // 但如果调用者依赖这个返回值来更新，那也没问题。
    // 为了保持接口简单，我们只在上传过程中回调增量。

    // 2. 上传分块
    for (int i = 0; i < totalChunks; i++) {
      if (cancelToken.isCancelled) {
        throw dio.DioException(
          requestOptions: dio.RequestOptions(path: ''),
          type: dio.DioExceptionType.cancel,
        );
      }

      if (uploadedChunks.contains(i)) continue;

      final start = i * chunkSize;
      final end = (start + chunkSize > fileSize) ? fileSize : start + chunkSize;
      final length = end - start;

      var chunkToken = token;
      if (ApiController.instance.isTokenExpiringSoon) {
        await ApiController.instance.refreshAuthToken();
        final refreshed = ApiController.instance.accessToken?.trim();
        if (refreshed != null && refreshed.isNotEmpty) {
          chunkToken = refreshed;
        }
      }

      int retryCount = 0;
      const maxRetries = 3;

      while (true) {
        try {
          if (cancelToken.isCancelled) {
            throw dio.DioException(
              requestOptions: dio.RequestOptions(path: ''),
              type: dio.DioExceptionType.cancel,
            );
          }
          if (isP2p && !kIsWeb) {
            if (fileRef is! XFile) {
              throw Exception('invalid_fileRef');
            }

            final chunkBytes = await fileRef
                .openRead(start, end)
                .fold<List<int>>(<int>[], (acc, data) {
                  acc.addAll(data);
                  return acc;
                });

            final req = http.MultipartRequest(
              'POST',
              Uri.parse('$baseUrl/api/file/upload/chunk'),
            );
            req.headers['authorization'] = 'Bearer $chunkToken';
            req.fields['hash'] = sessionHash;
            req.fields['targetDir'] = remotePath;
            req.fields['chunkSize'] = chunkSize.toString();
            req.fields['fileName'] = fileName;
            if (relativePath != null) req.fields['relativePath'] = relativePath;
            req.fields['totalChunks'] = totalChunks.toString();
            req.fields['nameStrategy'] = nameStrategy;
            if (normalizedSaveType != null) {
              req.fields['saveType'] = normalizedSaveType;
            }
            req.fields['index'] = i.toString();
            if (fileMtimeMs != null) {
              req.fields['mtimeMs'] = fileMtimeMs.toString();
            }
            if (fileBirthtimeMs != null) {
              req.fields['birthtimeMs'] = fileBirthtimeMs.toString();
            }
            req.files.add(
              http.MultipartFile.fromBytes(
                'file',
                chunkBytes,
                filename: 'chunk',
              ),
            );

            final streamed = await ApiController.instance
                .sendP2pRequestOnChannel(
                  req,
                  timeout: const Duration(minutes: 5),
                  channel: P2pRtcChannel.upload,
                  cancelFuture: cancelToken.whenCancel,
                );

            final respBytes = await http.ByteStream(streamed.stream).toBytes();
            if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
              final text = utf8.decode(respBytes, allowMalformed: true);
              try {
                final decoded = jsonDecode(text);
                if (decoded is Map &&
                    decoded['code']?.toString() == 'file.FILE_EXISTS') {
                  onSkipped?.call(relativePath ?? fileName);
                  onCompleted?.call(relativePath ?? fileName);
                  onProgress(length);
                  processedSize += length;
                  return fileSize;
                }
              } catch (_) {}
              final clipped = text.length > 240
                  ? '${text.substring(0, 240)}…'
                  : text;
              throw Exception(
                clipped.isEmpty
                    ? 'upload_chunk_http_${streamed.statusCode}'
                    : 'upload_chunk_http_${streamed.statusCode}_$clipped',
              );
            }
          } else if (kIsWeb && fileRef is! XFile) {
            // Web平台：使用原生XHR和Blob上传
            await UploadWebFileHelper.uploadChunk(
              fileRef,
              '$baseUrl/api/file/upload/chunk',
              chunkToken,
              sessionHash,
              remotePath,
              chunkSize,
              fileName,
              totalChunks,
              i,
              start,
              end,
              cancelToken,
              nameStrategy,
              relativePath,
              saveType: normalizedSaveType,
              fileMtimeMs: fileMtimeMs,
              fileBirthtimeMs: fileBirthtimeMs,
            );
          } else if (kIsWeb && fileRef is XFile) {
            // Web平台 XFile：需要读取数据转为Blob再上传
            await UploadWebFileHelper.uploadXFileChunk(
              fileRef,
              '$baseUrl/api/file/upload/chunk',
              chunkToken,
              sessionHash,
              remotePath,
              chunkSize,
              fileName,
              totalChunks,
              i,
              start,
              end,
              cancelToken,
              nameStrategy,
              relativePath,
              saveType: normalizedSaveType,
              fileMtimeMs: fileMtimeMs,
              fileBirthtimeMs: fileBirthtimeMs,
            );
          } else if (isP2p) {
            if (fileRef is! XFile) {
              throw Exception("未知文件类型");
            }

            Stream<List<int>> chunkStream = fileRef.openRead(start, end);
            final bb = BytesBuilder(copy: false);
            await for (final c in chunkStream) {
              if (cancelToken.isCancelled) {
                throw dio.DioException(
                  requestOptions: dio.RequestOptions(path: ''),
                  type: dio.DioExceptionType.cancel,
                );
              }
              bb.add(c);
            }
            final chunkBytes = bb.takeBytes();

            final boundary =
                '----nascab_${DateTime.now().microsecondsSinceEpoch}_${sessionHash}_$i';
            final bodyBytes = _buildMultipartBody(
              boundary: boundary,
              fields: <String, String>{
                'hash': sessionHash,
                'targetDir': remotePath,
                'chunkSize': chunkSize.toString(),
                'fileName': fileName,
                if (relativePath != null) 'relativePath': relativePath,
                'totalChunks': totalChunks.toString(),
                'nameStrategy': nameStrategy,
                if (normalizedSaveType != null) 'saveType': normalizedSaveType,
                'index': i.toString(),
                if (fileMtimeMs != null) 'mtimeMs': fileMtimeMs.toString(),
                if (fileBirthtimeMs != null)
                  'birthtimeMs': fileBirthtimeMs.toString(),
              },
              fileField: 'file',
              filename: 'chunk',
              fileBytes: chunkBytes,
            );

            final req = http.Request(
              'POST',
              Uri.parse('$baseUrl/api/file/upload/chunk'),
            );
            req.headers['authorization'] = 'Bearer $chunkToken';
            req.headers['x-name-strategy'] = nameStrategy;
            req.headers['content-type'] =
                'multipart/form-data; boundary=$boundary';
            req.headers['accept'] = 'application/json';
            req.bodyBytes = bodyBytes;

            final streamed = await ApiController.instance
                .sendP2pRequestOnChannel(
                  req,
                  timeout: const Duration(minutes: 10),
                  channel: P2pRtcChannel.upload,
                  cancelFuture: cancelToken.whenCancel,
                );
            final resBytes = await http.ByteStream(streamed.stream).toBytes();

            if (streamed.statusCode >= 200 && streamed.statusCode < 300) {
              break;
            }

            String msg = 'Upload failed with status: ${streamed.statusCode}';
            if (resBytes.isNotEmpty) {
              try {
                final decoded = jsonDecode(utf8.decode(resBytes));
                if (decoded is Map && decoded['message'] != null) {
                  msg = decoded['message'].toString();
                } else if (decoded != null) {
                  msg = decoded.toString();
                }
              } catch (_) {
                try {
                  msg = utf8.decode(resBytes);
                } catch (_) {}
              }
            }
            throw Exception(msg);
          } else {
            // 桌面平台：使用Dio流上传
            Stream<List<int>> chunkStream;
            if (fileRef is XFile) {
              chunkStream = fileRef.openRead(start, end);
            } else {
              throw Exception("未知文件类型");
            }

            final formData = dio.FormData.fromMap({
              'hash': sessionHash,
              'targetDir': remotePath,
              'chunkSize': chunkSize,
              'fileName': fileName,
              'relativePath': relativePath,
              'totalChunks': totalChunks,
              'nameStrategy': nameStrategy,
              if (normalizedSaveType != null) 'saveType': normalizedSaveType,
              'index': i,
              if (fileMtimeMs != null) 'mtimeMs': fileMtimeMs,
              if (fileBirthtimeMs != null) 'birthtimeMs': fileBirthtimeMs,
              'file': dio.MultipartFile.fromStream(
                () => chunkStream,
                length,
                filename: 'chunk',
              ),
            });

            await dioClient.post(
              '$baseUrl/api/file/upload/chunk',
              data: formData,
              options: dio.Options(
                headers: {'Authorization': 'Bearer $chunkToken'},
              ),
              cancelToken: cancelToken,
            );
          }
          break; // 成功
        } catch (e) {
          if (e is dio.DioException && e.type == dio.DioExceptionType.cancel) {
            rethrow;
          }
          if (cancelToken.isCancelled) {
            throw dio.DioException(
              requestOptions: dio.RequestOptions(path: ''),
              type: dio.DioExceptionType.cancel,
            );
          }

          if (isRelayP2p &&
              !reportedNewProgress &&
              _isRetryableRelayUploadError(e) &&
              chunkSize > _p2pRelayMinChunkBytes) {
            final nextChunkSize = _nextRelayChunkSize(chunkSize);
            if (nextChunkSize < chunkSize) {
              return processFile(
                dioClient: dioClient,
                baseUrl: baseUrl,
                token: token,
                fileRef: fileRef,
                fileName: fileName,
                fileSize: fileSize,
                remotePath: remotePath,
                nameStrategy: nameStrategy,
                saveType: saveType,
                fileHash: fileHash,
                cancelToken: cancelToken,
                onProgress: onProgress,
                relativePath: relativePath,
                onCompleted: onCompleted,
                onSkipped: onSkipped,
                chunkSizeOverride: nextChunkSize,
                onUiRefresh: onUiRefresh,
                fileMtimeMs: fileMtimeMs,
                fileBirthtimeMs: fileBirthtimeMs,
              );
            }
          }

          if (UploadTransferHelper.isFileExistsError(e)) {
            onSkipped?.call(relativePath ?? fileName);
            onCompleted?.call(relativePath ?? fileName);
            // 增加剩余未上传的大小到进度
            onProgress(length);
            processedSize += length;
            // 跳出重试，并返回
            return fileSize;
          }

          retryCount++;
          if (retryCount >= maxRetries) {
            rethrow;
          }
          await Future.delayed(Duration(seconds: 2 * retryCount));
        }
      }

      onProgress(length);
      processedSize += length;
      reportedNewProgress = true;
      onUiRefresh?.call();

      // 让出事件循环
      await Future.delayed(Duration(milliseconds: 0));
    }

    onCompleted?.call(relativePath ?? fileName);
    return processedSize;
  }
}
