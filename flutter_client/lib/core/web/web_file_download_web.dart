import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

bool get supportsFileSystemAccess {
  final w = web.window as JSObject;
  if (!w.hasProperty('__nascabHasShowSaveFilePicker'.toJS).toDart) return false;
  try {
    final ok = w.callMethod<JSAny?>('__nascabHasShowSaveFilePicker'.toJS);
    return (ok as JSBoolean?)?.toDart ?? false;
  } catch (_) {
    return false;
  }
}

bool get supportsStreamSaver {
  final w = web.window as JSObject;
  if (!w.hasProperty('__nascabStreamSaverInit'.toJS).toDart) return false;
  try {
    final ok = w.callMethod<JSAny?>('__nascabStreamSaverInit'.toJS);
    return (ok as JSBoolean?)?.toDart ?? false;
  } catch (_) {
    return false;
  }
}

Future<JSObject> pickSaveFileHandle({required String filename}) async {
  final safeName = filename.trim().isEmpty ? 'download' : filename.trim();
  final w = web.window as JSObject;
  if (!supportsFileSystemAccess ||
      !w.hasProperty('__nascabShowSaveFilePicker'.toJS).toDart) {
    throw UnsupportedError('File System Access API not supported');
  }
  final handlePromise = w.callMethod<JSPromise<JSObject>>(
    '__nascabShowSaveFilePicker'.toJS,
    safeName.toJS,
  );
  return await handlePromise.toDart;
}

Future<void> saveStreamWithHandle(
  Stream<Uint8List> stream, {
  required JSObject handle,
  int startByteOffset = 0,
}) async {
  final JSObject? createOpts = startByteOffset > 0
      ? (<String, Object?>{'keepExistingData': true}.jsify() as JSObject)
      : null;
  final JSPromise<JSObject> writablePromise = createOpts != null
      ? handle.callMethod<JSPromise<JSObject>>('createWritable'.toJS, createOpts)
      : handle.callMethod<JSPromise<JSObject>>('createWritable'.toJS);
  final writable = await writablePromise.toDart;

  if (startByteOffset > 0) {
    final seekP = writable.callMethod<JSPromise<JSAny?>>(
      'seek'.toJS,
      startByteOffset.toDouble().toJS,
    );
    await seekP.toDart;
  }

  Future<void> writeChunk(Uint8List chunk) async {
    if (chunk.isEmpty) return;
    final jsBuf = Uint8List.fromList(chunk).buffer.toJS;
    final p = writable.callMethod<JSPromise<JSAny?>>('write'.toJS, jsBuf);
    await p.toDart;
  }

  try {
    await for (final chunk in stream) {
      await writeChunk(chunk);
    }
    final p = writable.callMethod<JSPromise<JSAny?>>('close'.toJS);
    await p.toDart;
  } catch (_) {
    try {
      final p = writable.callMethod<JSPromise<JSAny?>>('abort'.toJS);
      await p.toDart;
    } catch (_) {}
    rethrow;
  }
}

JSObject createStreamSaverWriter({
  required String filename,
  String? mimeType,
  int? size,
}) {
  final safeName = filename.trim().isEmpty ? 'download' : filename.trim();
  final w = web.window as JSObject;
  if (!w.hasProperty('__nascabStreamSaverCreateWriter'.toJS).toDart) {
    throw UnsupportedError('StreamSaver not supported');
  }
  final JSAny? sizeArg = size?.toJS;
  return w.callMethod<JSObject>(
    '__nascabStreamSaverCreateWriter'.toJS,
    safeName.toJS,
    sizeArg,
    (mimeType ?? '').toJS,
  );
}

Future<void> writeStreamToStreamSaverWriter(
  Stream<Uint8List> stream, {
  required JSObject writer,
}) async {
  final w = web.window as JSObject;
  if (!w.hasProperty('__nascabStreamSaverWrite'.toJS).toDart ||
      !w.hasProperty('__nascabStreamSaverClose'.toJS).toDart) {
    throw UnsupportedError('StreamSaver not supported');
  }
  try {
    await for (final chunk in stream) {
      if (chunk.isEmpty) continue;
      final jsBuf = Uint8List.fromList(chunk).buffer.toJS;
      final p = w.callMethod<JSPromise<JSAny?>>(
        '__nascabStreamSaverWrite'.toJS,
        writer,
        jsBuf,
      );
      await p.toDart;
    }
    final p = w.callMethod<JSPromise<JSAny?>>(
      '__nascabStreamSaverClose'.toJS,
      writer,
    );
    await p.toDart;
  } catch (_) {
    try {
      if (w.hasProperty('__nascabStreamSaverAbort'.toJS).toDart) {
        final p = w.callMethod<JSPromise<JSAny?>>(
          '__nascabStreamSaverAbort'.toJS,
          writer,
        );
        await p.toDart;
      }
    } catch (_) {}
    rethrow;
  }
}

Future<void> triggerDownloadFromBytes(
  Uint8List bytes, {
  required String filename,
  String? mimeType,
}) async {
  final type = (mimeType ?? 'application/octet-stream').split(';').first.trim();
  final jsBuf = Uint8List.fromList(bytes).buffer.toJS;
  final parts = <JSAny>[jsBuf];
  final blob = web.Blob(parts.toJS, web.BlobPropertyBag(type: type));
  final objUrl = web.URL.createObjectURL(blob);

  final a = web.document.createElement('a') as web.HTMLAnchorElement;
  a.href = objUrl;
  a.download = filename;
  a.style.display = 'none';
  web.document.body?.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(objUrl);
}

Future<void> triggerDownloadFromChunks(
  Iterable<Uint8List> chunks, {
  required String filename,
  String? mimeType,
}) async {
  final type = (mimeType ?? 'application/octet-stream').split(';').first.trim();
  final parts = <JSAny>[];
  for (final c in chunks) {
    final jsBuf = Uint8List.fromList(c).buffer.toJS;
    parts.add(jsBuf);
  }
  final blob = web.Blob(parts.toJS, web.BlobPropertyBag(type: type));
  final objUrl = web.URL.createObjectURL(blob);

  final a = web.document.createElement('a') as web.HTMLAnchorElement;
  a.href = objUrl;
  a.download = filename;
  a.style.display = 'none';
  web.document.body?.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(objUrl);
}

Future<void> saveStreamWithPicker(
  Stream<Uint8List> stream, {
  required String filename,
  String? mimeType,
}) async {
  final safeName = filename.trim().isEmpty ? 'download' : filename.trim();
  final w = web.window as JSObject;
  if (!w.hasProperty('showSaveFilePicker'.toJS).toDart) {
    throw UnsupportedError('File System Access API not supported');
  }

  final options =
      <String, Object?>{'suggestedName': safeName}.jsify() as JSObject;

  final handlePromise = w.callMethod<JSPromise<JSObject>>(
    'showSaveFilePicker'.toJS,
    options,
  );
  final handle = await handlePromise.toDart;

  final writablePromise = handle.callMethod<JSPromise<JSObject>>(
    'createWritable'.toJS,
  );
  final writable = await writablePromise.toDart;

  Future<void> writeChunk(Uint8List chunk) async {
    if (chunk.isEmpty) return;
    final jsBuf = Uint8List.fromList(chunk).buffer.toJS;
    final p = writable.callMethod<JSPromise<JSAny?>>('write'.toJS, jsBuf);
    await p.toDart;
  }

  try {
    await for (final chunk in stream) {
      await writeChunk(chunk);
    }
    final p = writable.callMethod<JSPromise<JSAny?>>('close'.toJS);
    await p.toDart;
  } catch (_) {
    try {
      final p = writable.callMethod<JSPromise<JSAny?>>('abort'.toJS);
      await p.toDart;
    } catch (_) {}
    rethrow;
  }
}

Future<void> saveStreamWithStreamSaver(
  Stream<Uint8List> stream, {
  required String filename,
  String? mimeType,
  int? size,
}) async {
  final safeName = filename.trim().isEmpty ? 'download' : filename.trim();
  final w = web.window as JSObject;
  if (!supportsStreamSaver) {
    throw UnsupportedError('StreamSaver not supported');
  }

  JSObject? writer;
  try {
    if (!w.hasProperty('__nascabStreamSaverCreateWriter'.toJS).toDart ||
        !w.hasProperty('__nascabStreamSaverWrite'.toJS).toDart ||
        !w.hasProperty('__nascabStreamSaverClose'.toJS).toDart) {
      throw UnsupportedError('StreamSaver not supported');
    }

    final JSAny? sizeArg = size?.toJS;
    writer = w.callMethod<JSObject>(
      '__nascabStreamSaverCreateWriter'.toJS,
      safeName.toJS,
      sizeArg,
      (mimeType ?? '').toJS,
    );

    await for (final chunk in stream) {
      if (chunk.isEmpty) continue;
      final jsBuf = Uint8List.fromList(chunk).buffer.toJS;
      final p = w.callMethod<JSPromise<JSAny?>>(
        '__nascabStreamSaverWrite'.toJS,
        writer,
        jsBuf,
      );
      await p.toDart;
    }

    final p = w.callMethod<JSPromise<JSAny?>>(
      '__nascabStreamSaverClose'.toJS,
      writer,
    );
    await p.toDart;
  } catch (_) {
    try {
      if (writer != null) {
        if (w.hasProperty('__nascabStreamSaverAbort'.toJS).toDart) {
          final p = w.callMethod<JSPromise<JSAny?>>(
            '__nascabStreamSaverAbort'.toJS,
            writer,
          );
          await p.toDart;
        } else {
          final p = writer.callMethod<JSPromise<JSAny?>>('abort'.toJS);
          await p.toDart;
        }
      }
    } catch (_) {}
    rethrow;
  }
}
