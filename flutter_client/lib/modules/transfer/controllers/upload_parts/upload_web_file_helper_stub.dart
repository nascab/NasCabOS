import 'package:dio/dio.dart' as dio;

class UploadWebFileHelper {
  static List<Map<String, dynamic>> getFilesFromDataTransferSync(
    dynamic transfer,
  ) {
    throw UnsupportedError('Not supported on this platform');
  }

  static Future<List<Map<String, dynamic>>> getFilesFromDataTransfer(
    dynamic transfer,
  ) async {
    throw UnsupportedError('Not supported on this platform');
  }

  static Future<List<dynamic>> pickDirectoryFiles() async {
    throw UnsupportedError('Not supported on this platform');
  }

  static Future<List<dynamic>> pickFiles() async {
    throw UnsupportedError('Not supported on this platform');
  }

  static String getFileName(dynamic file) => '';
  static int getFileSize(dynamic file) => 0;
  static String getRelativePath(dynamic file) => '';
  static int getLastModified(dynamic file) =>
      DateTime.now().millisecondsSinceEpoch;
  static Stream<List<int>> readFileChunk(
    dynamic file,
    int start,
    int end,
  ) async* {
    yield [];
  }

  static Future<List<int>> readFileBytes(dynamic file) async => [];

  static Future<void> uploadFormFile(
    dynamic file,
    String url,
    String token, {
    dio.CancelToken? cancelToken,
    void Function(int sent, int total)? onProgress,
  }) async {
    throw UnsupportedError('Not supported on this platform');
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
    throw UnsupportedError('Not supported on this platform');
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
    throw UnsupportedError('Not supported on this platform');
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
    throw UnsupportedError('Not supported on this platform');
  }
}
