import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'package:dio/dio.dart' as dio;
import 'package:cross_file/cross_file.dart';
import 'package:http/http.dart' as http;

import '../../../../core/api/api_controller.dart';
import '../../../../core/api/p2p_rtc_stub.dart'
    if (dart.library.html) '../../../../core/api/p2p_rtc_web.dart';

// JS interop for vendor property on File when directory is selected
extension type WebFileProps(web.File _) implements web.File {
  external String get webkitRelativePath;
  external int get lastModified;
}

class UploadWebFileHelper {
  static bool _shouldUseP2p(String url) {
    final raw = url.trim();
    if (raw.isEmpty) return false;
    final api = ApiController.instance;
    if (!api.isP2pMode) return false;
    try {
      final uri = Uri.parse(raw);
      return uri.origin.trim() == ApiController.p2pBaseUrl;
    } catch (_) {
      return false;
    }
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

  static Future<Uint8List> _readBlobBytes(web.Blob blob) async {
    final reader = web.FileReader();
    final completer = Completer<void>();

    reader.onload = (web.Event e) {
      completer.complete();
    }.toJS;

    reader.onerror = (web.Event e) {
      completer.completeError(
        reader.error ?? Exception('Unknown FileReader error'),
      );
    }.toJS;

    reader.readAsArrayBuffer(blob);
    await completer.future;

    final buffer = reader.result as JSArrayBuffer;
    return buffer.toDart.asUint8List();
  }

  static Future<void> _uploadChunkViaP2p({
    required String url,
    required String token,
    required String hash,
    required String targetDir,
    required int chunkSize,
    required String fileName,
    required int totalChunks,
    required int index,
    required String nameStrategy,
    required Uint8List chunkBytes,
    String? saveType,
    dio.CancelToken? cancelToken,
    String? relativePath,
    int? fileMtimeMs,
    int? fileBirthtimeMs,
  }) async {
    if (cancelToken != null && cancelToken.isCancelled) {
      return Future.error(cancelToken.cancelError!);
    }

    final boundary =
        '----nascab_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 30)}';
    final bodyBytes = _buildMultipartBody(
      boundary: boundary,
      fields: <String, String>{
        'hash': hash,
        'targetDir': targetDir,
        'chunkSize': chunkSize.toString(),
        'fileName': fileName,
        if (relativePath != null) 'relativePath': relativePath,
        'totalChunks': totalChunks.toString(),
        'nameStrategy': nameStrategy,
        if (saveType != null) 'saveType': saveType,
        'index': index.toString(),
        if (fileMtimeMs != null) 'mtimeMs': fileMtimeMs.toString(),
        if (fileBirthtimeMs != null) 'birthtimeMs': fileBirthtimeMs.toString(),
      },
      fileField: 'file',
      filename: 'chunk',
      fileBytes: chunkBytes,
    );

    final req = http.Request('POST', Uri.parse(url));
    req.headers['authorization'] = 'Bearer $token';
    req.headers['x-name-strategy'] = nameStrategy;
    req.headers['content-type'] = 'multipart/form-data; boundary=$boundary';
    req.headers['accept'] = 'application/json';
    req.bodyBytes = bodyBytes;

    final streamed = await ApiController.instance.sendP2pRequestOnChannel(
      req,
      timeout: const Duration(minutes: 5),
      channel: P2pRtcChannel.upload,
      cancelFuture: cancelToken?.whenCancel,
    );
    final resBytes = await http.ByteStream(streamed.stream).toBytes();

    if (streamed.statusCode >= 200 && streamed.statusCode < 300) {
      return;
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
    return Future.error(msg);
  }

  /// 在 drop 事件里必须同步读取 dataTransfer，否则 await 之后浏览器会清空内容。
  /// 仅使用 transfer.files（扁平列表，不支持目录结构），供事件回调内立即调用。
  static List<Map<String, dynamic>> getFilesFromDataTransferSync(
    web.DataTransfer transfer,
  ) {
    final results = <Map<String, dynamic>>[];
    final fileList = transfer.files;
    for (int i = 0; i < fileList.length; i++) {
      final file = fileList.item(i);
      if (file != null) {
        results.add({'file': file, 'path': file.name});
      }
    }
    return results;
  }

  static Future<List<Map<String, dynamic>>> getFilesFromDataTransfer(
    web.DataTransfer transfer,
  ) async {
    final items = transfer.items;
    final results = <Map<String, dynamic>>[];

    // 使用 Future.wait 等待所有顶层项目的处理完成
    final futures = <Future<void>>[];
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.kind == 'file') {
        final entry = item.webkitGetAsEntry();
        if (entry != null) {
          // 顶层文件的路径应该是空的，因为文件名本身包含在 file 对象中
          // 或者我们可以认为顶层就是根
          // _traverseFileTree 将递归添加文件
          // 如果是文件，path 为 "" + entry.name
          // 如果是文件夹，path 为 "" + entry.name + "/"
          futures.add(_traverseFileTree(entry, '', results));
        } else {
          // 某些浏览器/拖放场景下 webkitGetAsEntry() 会返回 null。
          // 这时至少尝试直接拿到普通文件（不支持目录递归，但可以上传文件）。
          final file = item.getAsFile();
          if (file != null) {
            results.add({'file': file, 'path': file.name});
          }
        }
      }
    }
    await Future.wait(futures);

    // 若 items 未解析出任何文件（如 Chrome 拖入时 items 可能不可用），
    // 使用 transfer.files 兜底（标准 FileList，拖入文件时通常有值）
    if (results.isEmpty) {
      final fileList = transfer.files;
      if (fileList.length > 0) {
        for (int i = 0; i < fileList.length; i++) {
          final file = fileList.item(i);
          if (file != null) {
            results.add({'file': file, 'path': file.name});
          }
        }
      }
    }
    return results;
  }

  static Future<void> _traverseFileTree(
    web.FileSystemEntry entry,
    String path,
    List<Map<String, dynamic>> results,
  ) async {
    if (entry.isFile) {
      final fileEntry = entry as web.FileSystemFileEntry;
      final completer = Completer<web.File>();
      fileEntry.file(
        (web.File file) {
          completer.complete(file);
        }.toJS,
        (web.DOMException e) {
          completer.completeError(e);
        }.toJS,
      );
      try {
        final file = await completer.future;
        results.add({'file': file, 'path': '$path${entry.name}'});
      } catch (_) {}
    } else if (entry.isDirectory) {
      final dirEntry = entry as web.FileSystemDirectoryEntry;
      final dirReader = dirEntry.createReader();
      final newPath = '$path${entry.name}/';

      await _readEntries(dirReader, newPath, results);
    }
  }

  static Future<void> _readEntries(
    web.FileSystemDirectoryReader reader,
    String path,
    List<Map<String, dynamic>> results,
  ) async {
    final completer = Completer<void>();

    void read() {
      reader.readEntries(
        (JSArray entries) {
          final dartEntries = entries.toDart;
          if (dartEntries.isNotEmpty) {
            Future.wait(
              dartEntries.map(
                (e) =>
                    _traverseFileTree(e as web.FileSystemEntry, path, results),
              ),
            ).then((_) {
              read(); // Read next batch
            });
          } else {
            completer.complete();
          }
        }.toJS,
        (web.DOMException e) {
          completer.completeError(e);
        }.toJS,
      );
    }

    read();
    return completer.future;
  }

  static Future<List<dynamic>> pickDirectoryFiles() async {
    final completer = Completer<List<dynamic>>();
    final input = web.document.createElement('input') as web.HTMLInputElement;
    input.type = 'file';
    input.multiple = true;
    input.setAttribute('webkitdirectory', '');
    // Safari: 目录选择器要求 input 在 DOM 中，否则 click() 可能不弹窗
    input.style.position = 'fixed';
    input.style.left = '-9999px';
    input.style.opacity = '0';
    input.style.pointerEvents = 'none';
    web.document.body?.appendChild(input);

    void removeInput() {
      try {
        input.remove();
      } catch (_) {}
    }

    input.onchange = (web.Event e) {
      if (input.files != null && input.files!.length > 0) {
        final files = <web.File>[];
        for (var i = 0; i < input.files!.length; i++) {
          files.add(input.files!.item(i)!);
        }
        // Safari: 在微任务中完成并移除 input，确保 Dart 延续能稳定执行（先 complete 再 remove 避免 File 引用失效）
        scheduleMicrotask(() {
          completer.complete(files);
          removeInput();
        });
      } else {
        scheduleMicrotask(() {
          completer.complete([]);
          removeInput();
        });
      }
    }.toJS;

    input.onerror = (web.Event e) {
      scheduleMicrotask(() {
        completer.completeError(e);
        removeInput();
      });
    }.toJS;

    input.click();
    return completer.future;
  }

  static Future<List<dynamic>> pickFiles() async {
    final completer = Completer<List<dynamic>>();
    final input = web.document.createElement('input') as web.HTMLInputElement;
    input.type = 'file';
    input.multiple = true;
    // Safari: 与目录选择器一致，将 input 放入 DOM 再 click，避免偶发不弹窗
    input.style.position = 'fixed';
    input.style.left = '-9999px';
    input.style.opacity = '0';
    input.style.pointerEvents = 'none';
    web.document.body?.appendChild(input);

    void removeInput() {
      try {
        input.remove();
      } catch (_) {}
    }

    input.onchange = (web.Event e) {
      if (input.files != null && input.files!.length > 0) {
        final files = <web.File>[];
        for (var i = 0; i < input.files!.length; i++) {
          files.add(input.files!.item(i)!);
        }
        // Safari: 在微任务中完成并移除 input（先 complete 再 remove 避免 File 引用失效）
        scheduleMicrotask(() {
          completer.complete(files);
          removeInput();
        });
      } else {
        scheduleMicrotask(() {
          completer.complete([]);
          removeInput();
        });
      }
    }.toJS;

    input.onerror = (web.Event e) {
      scheduleMicrotask(() {
        completer.completeError(e);
        removeInput();
      });
    }.toJS;

    input.click();
    return completer.future;
  }

  static String getFileName(dynamic file) {
    return (file as web.File).name;
  }

  static int getFileSize(dynamic file) {
    return (file as web.File).size;
  }

  static String getRelativePath(dynamic file) {
    // webkitRelativePath is available when using directory selection
    final f = file as web.File;
    String rp = '';
    try {
      rp = WebFileProps(f).webkitRelativePath;
    } catch (_) {}
    return (rp.isNotEmpty) ? rp : f.name;
  }

  static int getLastModified(dynamic file) {
    final f = file as web.File;
    try {
      return WebFileProps(f).lastModified;
    } catch (_) {
      return DateTime.now().millisecondsSinceEpoch;
    }
  }

  static Stream<List<int>> readFileChunk(
    dynamic file,
    int start,
    int end,
  ) async* {
    final webFile = file as web.File;
    int retryCount = 0;
    const maxRetries = 3;

    while (true) {
      try {
        final blob = webFile.slice(start, end);
        final reader = web.FileReader();
        final completer = Completer<void>();

        reader.onload = (web.Event e) {
          completer.complete();
        }.toJS;

        reader.onerror = (web.Event e) {
          // reader.error is a DOMException
          completer.completeError(
            reader.error ?? Exception('Unknown FileReader error'),
          );
        }.toJS;

        reader.readAsArrayBuffer(blob);
        await completer.future;

        final buffer = reader.result as JSArrayBuffer;
        final bytes = buffer.toDart.asUint8List();

        // Explicitly clear references to help GC
        reader.onload = null;
        reader.onerror = null;

        yield bytes;
        return; // Success, exit loop
      } catch (e) {
        retryCount++;
        if (retryCount >= maxRetries) {
          throw Exception(
            "Failed to read file chunk after $maxRetries retries: $e",
          );
        }
        await Future.delayed(Duration(seconds: 1 * retryCount));
      }
    }
  }

  static Future<List<int>> readFileBytes(dynamic file) async {
    final webFile = file as web.File;
    final reader = web.FileReader();
    final completer = Completer<void>();

    reader.onload = (web.Event e) {
      completer.complete();
    }.toJS;

    reader.onerror = (web.Event e) {
      completer.completeError(reader.error!);
    }.toJS;

    reader.readAsArrayBuffer(webFile);
    await completer.future;

    final buffer = reader.result as JSArrayBuffer;
    return buffer.toDart.asUint8List();
  }

  static Future<void> uploadFormFile(
    dynamic file,
    String url,
    String token, {
    dio.CancelToken? cancelToken,
    void Function(int sent, int total)? onProgress,
  }) async {
    final webFile = file as web.File;

    final formData = web.FormData();
    formData.append('file', webFile, webFile.name);

    final xhr = web.XMLHttpRequest();
    xhr.open('POST', url);
    xhr.setRequestHeader('Authorization', 'Bearer $token');
    xhr.responseType = 'json';

    final completer = Completer<void>();

    if (onProgress != null) {
      xhr.upload.onprogress = (web.ProgressEvent e) {
        final total = e.total.toInt();
        final loaded = e.loaded.toInt();
        onProgress(loaded, total);
      }.toJS;
    }

    xhr.onload = (web.Event e) {
      if (xhr.status >= 200 && xhr.status < 300) {
        completer.complete();
      } else {
        final resp = xhr.response;
        final requestOptions = dio.RequestOptions(path: url);
        completer.completeError(
          dio.DioException(
            requestOptions: requestOptions,
            response: dio.Response(
              requestOptions: requestOptions,
              statusCode: xhr.status,
              data: resp,
            ),
            type: dio.DioExceptionType.badResponse,
          ),
        );
      }
    }.toJS;

    xhr.onerror = (web.Event e) {
      completer.completeError('Network error during upload');
    }.toJS;

    xhr.onabort = (web.Event e) {
      if (!completer.isCompleted) {
        completer.completeError(
          dio.DioException(
            requestOptions: dio.RequestOptions(path: url),
            type: dio.DioExceptionType.cancel,
          ),
        );
      }
    }.toJS;

    if (cancelToken != null) {
      if (cancelToken.isCancelled) {
        return Future.error(cancelToken.cancelError!);
      }
      cancelToken.whenCancel.then((_) {
        xhr.abort();
        if (!completer.isCompleted) {
          completer.completeError(cancelToken.cancelError!);
        }
      });
    }

    xhr.send(formData);
    return completer.future;
  }

  static Future<void> uploadChunk(
    dynamic file,
    String url,
    String token,
    String hash,
    String targetDir,
    int chunkSize,
    String fileName,
    int totalChunks,
    int index,
    int start,
    int end,
    dio.CancelToken? cancelToken,
    String nameStrategy,
    String? relativePath, {
    String? saveType,
    int? fileMtimeMs,
    int? fileBirthtimeMs,
    void Function(int sent, int total)? onProgress,
  }) async {
    final webFile = file as web.File;
    if (_shouldUseP2p(url)) {
      if (cancelToken != null && cancelToken.isCancelled) {
        return Future.error(cancelToken.cancelError!);
      }
      final bytes = await readFileChunk(file, start, end).first;
      await _uploadChunkViaP2p(
        url: url,
        token: token,
        hash: hash,
        targetDir: targetDir,
        chunkSize: chunkSize,
        fileName: fileName,
        totalChunks: totalChunks,
        index: index,
        nameStrategy: nameStrategy,
        chunkBytes: Uint8List.fromList(bytes),
        saveType: saveType,
        cancelToken: cancelToken,
        relativePath: relativePath,
        fileMtimeMs: fileMtimeMs,
        fileBirthtimeMs: fileBirthtimeMs,
      );
      if (onProgress != null) {
        final total = end > start ? (end - start) : 0;
        onProgress(total, total);
      }
      return;
    }

    final blob = webFile.slice(start, end);

    final formData = web.FormData();
    formData.append('hash', hash.toJS);
    formData.append('targetDir', targetDir.toJS);
    formData.append('chunkSize', chunkSize.toString().toJS);
    formData.append('fileName', fileName.toJS);
    if (relativePath != null) {
      formData.append('relativePath', relativePath.toJS);
    }
    formData.append('totalChunks', totalChunks.toString().toJS);
    formData.append('nameStrategy', nameStrategy.toJS);
    if (saveType != null) {
      formData.append('saveType', saveType.toJS);
    }
    formData.append('index', index.toString().toJS);
    if (fileMtimeMs != null) {
      formData.append('mtimeMs', fileMtimeMs.toString().toJS);
    }
    if (fileBirthtimeMs != null) {
      formData.append('birthtimeMs', fileBirthtimeMs.toString().toJS);
    }
    formData.append('file', blob, 'chunk');

    final xhr = web.XMLHttpRequest();
    xhr.open('POST', url);
    xhr.setRequestHeader('Authorization', 'Bearer $token');
    xhr.responseType = 'json';

    final completer = Completer<void>();

    if (onProgress != null) {
      final chunkTotal = end > start ? (end - start) : 0;
      xhr.upload.onprogress = (web.ProgressEvent e) {
        final loaded = e.loaded.toInt();
        onProgress(loaded, chunkTotal);
      }.toJS;
    }

    xhr.onload = (web.Event e) {
      if (xhr.status >= 200 && xhr.status < 300) {
        completer.complete();
      } else {
        final resp = xhr.response;
        final requestOptions = dio.RequestOptions(path: url);
        completer.completeError(
          dio.DioException(
            requestOptions: requestOptions,
            response: dio.Response(
              requestOptions: requestOptions,
              statusCode: xhr.status,
              data: resp,
            ),
            type: dio.DioExceptionType.badResponse,
          ),
        );
      }
    }.toJS;

    xhr.onerror = (web.Event e) {
      completer.completeError('Network error during upload');
    }.toJS;

    xhr.onabort = (web.Event e) {
      // Handled by cancel token logic mostly, but if aborted externally
      if (!completer.isCompleted) {
        completer.completeError(
          dio.DioException(
            requestOptions: dio.RequestOptions(path: url),
            type: dio.DioExceptionType.cancel,
          ),
        );
      }
    }.toJS;

    if (cancelToken != null) {
      if (cancelToken.isCancelled) {
        return Future.error(cancelToken.cancelError!);
      }
      cancelToken.whenCancel.then((_) {
        xhr.abort();
        if (!completer.isCompleted) {
          completer.completeError(cancelToken.cancelError!);
        }
      });
    }

    xhr.send(formData);

    return completer.future;
  }

  static Future<void> uploadBlobChunk(
    dynamic blob,
    String url,
    String token,
    String hash,
    String targetDir,
    int chunkSize,
    String fileName,
    int totalChunks,
    int index,
    dio.CancelToken? cancelToken,
    String nameStrategy,
    String? relativePath, {
    String? saveType,
    int? fileMtimeMs,
    int? fileBirthtimeMs,
    void Function(int sent, int total)? onProgress,
  }) async {
    // blob is expected to be a web.Blob or something compatible that formData accepts
    final webBlob = blob as web.Blob;
    if (_shouldUseP2p(url)) {
      if (cancelToken != null && cancelToken.isCancelled) {
        return Future.error(cancelToken.cancelError!);
      }
      final bytes = await _readBlobBytes(webBlob);
      await _uploadChunkViaP2p(
        url: url,
        token: token,
        hash: hash,
        targetDir: targetDir,
        chunkSize: chunkSize,
        fileName: fileName,
        totalChunks: totalChunks,
        index: index,
        nameStrategy: nameStrategy,
        chunkBytes: bytes,
        saveType: saveType,
        cancelToken: cancelToken,
        relativePath: relativePath,
        fileMtimeMs: fileMtimeMs,
        fileBirthtimeMs: fileBirthtimeMs,
      );
      if (onProgress != null) {
        onProgress(bytes.length, bytes.length);
      }
      return;
    }

    final formData = web.FormData();
    formData.append('hash', hash.toJS);
    formData.append('targetDir', targetDir.toJS);
    formData.append('chunkSize', chunkSize.toString().toJS);
    formData.append('fileName', fileName.toJS);
    if (relativePath != null) {
      formData.append('relativePath', relativePath.toJS);
    }
    formData.append('totalChunks', totalChunks.toString().toJS);
    formData.append('nameStrategy', nameStrategy.toJS);
    if (saveType != null) {
      formData.append('saveType', saveType.toJS);
    }
    formData.append('index', index.toString().toJS);
    if (fileMtimeMs != null) {
      formData.append('mtimeMs', fileMtimeMs.toString().toJS);
    }
    if (fileBirthtimeMs != null) {
      formData.append('birthtimeMs', fileBirthtimeMs.toString().toJS);
    }
    formData.append('file', webBlob, 'chunk');

    final xhr = web.XMLHttpRequest();
    xhr.open('POST', url);
    xhr.setRequestHeader('Authorization', 'Bearer $token');
    xhr.responseType = 'json';

    final completer = Completer<void>();

    if (onProgress != null) {
      xhr.upload.onprogress = (web.ProgressEvent e) {
        final total = e.total.toInt();
        final loaded = e.loaded.toInt();
        onProgress(loaded, total);
      }.toJS;
    }

    xhr.onload = (web.Event e) {
      if (xhr.status >= 200 && xhr.status < 300) {
        completer.complete();
      } else {
        final resp = xhr.response;
        final requestOptions = dio.RequestOptions(path: url);
        completer.completeError(
          dio.DioException(
            requestOptions: requestOptions,
            response: dio.Response(
              requestOptions: requestOptions,
              statusCode: xhr.status,
              data: resp,
            ),
            type: dio.DioExceptionType.badResponse,
          ),
        );
      }
    }.toJS;

    xhr.onerror = (web.Event e) {
      completer.completeError('Network error during upload');
    }.toJS;

    xhr.onabort = (web.Event e) {
      if (!completer.isCompleted) {
        completer.completeError(
          dio.DioException(
            requestOptions: dio.RequestOptions(path: url),
            type: dio.DioExceptionType.cancel,
          ),
        );
      }
    }.toJS;

    if (cancelToken != null) {
      if (cancelToken.isCancelled) {
        return Future.error(cancelToken.cancelError!);
      }
      cancelToken.whenCancel.then((_) {
        xhr.abort();
        if (!completer.isCompleted) {
          completer.completeError(cancelToken.cancelError!);
        }
      });
    }

    xhr.send(formData);

    return completer.future;
  }

  static Future<void> uploadXFileChunk(
    dynamic xFile,
    String url,
    String token,
    String hash,
    String targetDir,
    int chunkSize,
    String fileName,
    int totalChunks,
    int index,
    int start,
    int end,
    dio.CancelToken? cancelToken,
    String nameStrategy,
    String? relativePath, {
    String? saveType,
    int? fileMtimeMs,
    int? fileBirthtimeMs,
    void Function(int sent, int total)? onProgress,
  }) async {
    // This method is intended to be used on Web only, where XFile might need conversion.
    // However, if we are in upload_web_file_helper_web.dart, we are on web.
    // The issue is how to get the Blob from XFile efficiently without reading all into memory if possible,
    // or just using the XFile's openRead which we did in UploadCore.
    // But wait, in UploadCore we had:
    // final stream = fileRef.openRead(start, end);
    // ...
    // final blob = web.Blob([bytes.toJS].toJS);
    //
    // If we move that logic here, we can avoid importing 'web' in UploadCore.

    // On Web, XFile is backed by a Blob or File usually.
    // But cross_file's XFile on web doesn't expose the underlying Blob directly easily without reading.
    // However, we can use openRead as before.

    final fileRef = xFile as XFile;
    final stream = fileRef.openRead(start, end);
    final bytesBuilder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      bytesBuilder.add(chunk);
    }
    final bytes = bytesBuilder.takeBytes();
    if (_shouldUseP2p(url)) {
      await _uploadChunkViaP2p(
        url: url,
        token: token,
        hash: hash,
        targetDir: targetDir,
        chunkSize: chunkSize,
        fileName: fileName,
        totalChunks: totalChunks,
        index: index,
        nameStrategy: nameStrategy,
        chunkBytes: bytes,
        saveType: saveType,
        cancelToken: cancelToken,
        relativePath: relativePath,
        fileMtimeMs: fileMtimeMs,
        fileBirthtimeMs: fileBirthtimeMs,
      );
      if (onProgress != null) {
        onProgress(bytes.length, bytes.length);
      }
      return;
    }

    final blob = web.Blob([bytes.toJS].toJS);
    await uploadBlobChunk(
      blob,
      url,
      token,
      hash,
      targetDir,
      chunkSize,
      fileName,
      totalChunks,
      index,
      cancelToken,
      nameStrategy,
      relativePath,
      saveType: saveType,
      fileMtimeMs: fileMtimeMs,
      fileBirthtimeMs: fileBirthtimeMs,
      onProgress: onProgress,
    );
  }
}
