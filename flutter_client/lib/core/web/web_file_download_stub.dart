import 'dart:typed_data';

bool get supportsFileSystemAccess => false;
bool get supportsStreamSaver => false;
Future<dynamic> pickSaveFileHandle({required String filename}) async {
  throw UnsupportedError('Not supported on this platform');
}

Future<void> saveStreamWithHandle(
  Stream<Uint8List> stream, {
  required dynamic handle,
  int startByteOffset = 0,
}) async {
  throw UnsupportedError('Not supported on this platform');
}

dynamic createStreamSaverWriter({
  required String filename,
  String? mimeType,
  int? size,
}) {
  throw UnsupportedError('Not supported on this platform');
}

Future<void> writeStreamToStreamSaverWriter(
  Stream<Uint8List> stream, {
  required dynamic writer,
}) async {
  throw UnsupportedError('Not supported on this platform');
}

Future<void> triggerDownloadFromBytes(
  Uint8List bytes, {
  required String filename,
  String? mimeType,
}) async {
  throw UnsupportedError('Not supported on this platform');
}

Future<void> triggerDownloadFromChunks(
  Iterable<Uint8List> chunks, {
  required String filename,
  String? mimeType,
}) async {
  throw UnsupportedError('Not supported on this platform');
}

Future<void> saveStreamWithPicker(
  Stream<Uint8List> stream, {
  required String filename,
  String? mimeType,
}) async {
  throw UnsupportedError('Not supported on this platform');
}

Future<void> saveStreamWithStreamSaver(
  Stream<Uint8List> stream, {
  required String filename,
  String? mimeType,
  int? size,
}) async {
  throw UnsupportedError('Not supported on this platform');
}
