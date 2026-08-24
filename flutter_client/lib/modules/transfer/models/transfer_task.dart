enum TransferStatus { pending, uploading, paused, completed, error }

enum TransferType { upload, download }

class TransferTask {
  String id;
  String name;
  String localPath;
  String remotePath; // Target directory for upload, Source file for download
  TransferType type;
  TransferStatus status;
  int totalSize;
  int processedSize;
  String? error;
  DateTime createdTime;
  String? fileHash; // For resume
  int? chunkSize; // Dynamic chunk size
  List<String>? folderCompleted; // Completed relative paths for folder upload
  List<Map<String, dynamic>>?
  folderRefs; // Runtime-only: source file refs for folder upload

  // Runtime only (not persisted)
  bool isCalculatingHash = false;

  /// 文件浏览器等入口已知类型时传入：`true`=文件夹，`false`=文件，`null`=未知（走 attributes/listDirectory 探测）。
  bool? remoteIsDirectory;

  TransferTask({
    required this.id,
    required this.name,
    required this.localPath,
    required this.remotePath,
    required this.type,
    this.status = TransferStatus.pending,
    this.totalSize = 0,
    this.processedSize = 0,
    this.error,
    DateTime? createdTime,
    this.fileHash,
    this.chunkSize,
    this.folderCompleted,
    this.remoteIsDirectory,
  }) : createdTime = createdTime ?? DateTime.now();

  double get progress => totalSize == 0 ? 0 : processedSize / totalSize;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'localPath': localPath,
      'remotePath': remotePath,
      'type': type.index,
      'status': status.index,
      'totalSize': totalSize,
      'processedSize': processedSize,
      'createdTime': createdTime.millisecondsSinceEpoch,
      'fileHash': fileHash,
      'error': error,
      'chunkSize': chunkSize,
      'folderCompleted': folderCompleted,
    };
  }

  factory TransferTask.fromJson(Map<String, dynamic> json) {
    return TransferTask(
      id: json['id'],
      name: json['name'],
      localPath: json['localPath'],
      remotePath: json['remotePath'],
      type: TransferType.values[json['type']],
      status: TransferStatus.values[json['status']],
      totalSize: json['totalSize'],
      processedSize: json['processedSize'],
      createdTime: DateTime.fromMillisecondsSinceEpoch(json['createdTime']),
      fileHash: json['fileHash'],
      error: json['error'],
      chunkSize: json['chunkSize'],
      folderCompleted: (json['folderCompleted'] is List)
          ? List<String>.from(json['folderCompleted'])
          : null,
    );
  }
}
