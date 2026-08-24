// Dio 下载进度/状态回调用的轻量类型（替代已移除的 background_downloader 模型）。

enum NascabTaskStatus {
  enqueued,
  running,
  complete,
  failed,
  canceled,
  paused,
  notFound,
}

class NascabTaskException implements Exception {
  NascabTaskException(this.description);
  final String description;
  @override
  String toString() => description;
}

class NascabTaskHttpException extends NascabTaskException {
  NascabTaskHttpException(super.description, this.httpResponseCode);
  final int httpResponseCode;
}

class NascabDownloadWorkerTask {
  NascabDownloadWorkerTask({
    required this.taskId,
    required this.url,
    required this.filename,
    required this.directory,
    this.metaData,
    required this.displayName,
  });

  final String taskId;
  final String url;
  final String filename;
  final String directory;
  final String? metaData;
  final String displayName;
}

sealed class NascabTaskUpdate {
  NascabDownloadWorkerTask get task;
}

class NascabTaskStatusUpdate extends NascabTaskUpdate {
  NascabTaskStatusUpdate(this.task, this.status, [this.exception]);

  @override
  final NascabDownloadWorkerTask task;
  final NascabTaskStatus status;
  final NascabTaskException? exception;
}

class NascabTaskProgressUpdate extends NascabTaskUpdate {
  NascabTaskProgressUpdate(this.task, this.progress);

  @override
  final NascabDownloadWorkerTask task;
  final double progress;
}
