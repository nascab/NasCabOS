import 'dart:convert';

class FileOperationLog {
  final int id;
  final String type;
  final List<String> sourcePath;
  final String? targetPath;
  final int uid;
  final String state;
  final String? message;
  final int? totalSize;
  final int? copiedSize;
  final int? createTime;

  FileOperationLog({
    required this.id,
    required this.type,
    required this.sourcePath,
    this.targetPath,
    required this.uid,
    required this.state,
    this.message,
    this.totalSize,
    this.copiedSize,
    this.createTime,
  });

  factory FileOperationLog.fromJson(Map<String, dynamic> json) {
    List<String> parsedSourcePath = [];
    if (json['source_path'] != null) {
      try {
        final decoded = jsonDecode(json['source_path']);
        if (decoded is List) {
          parsedSourcePath = decoded.map((e) => e.toString()).toList();
        }
      } catch (e) {
        // Fallback if not a JSON string or other error
        parsedSourcePath = [json['source_path'].toString()];
      }
    }

    return FileOperationLog(
      id: json['id'],
      type: json['type'],
      sourcePath: parsedSourcePath,
      targetPath: json['target_path'],
      uid: json['uid'],
      state: json['state'],
      message: json['message'],
      totalSize: json['total_size'],
      copiedSize: json['copied_size'],
      createTime: json['create_time'],
    );
  }

  double get progress {
    if (totalSize == null || totalSize == 0) return 0.0;
    if (copiedSize == null) return 0.0;
    return copiedSize! / totalSize!;
  }
}

class FileLogListResponse {
  final List<FileOperationLog> list;
  final int total;
  final int page;
  final int pageSize;

  FileLogListResponse({
    required this.list,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory FileLogListResponse.fromJson(Map<String, dynamic> json) {
    return FileLogListResponse(
      list: (json['list'] as List)
          .map((e) => FileOperationLog.fromJson(e))
          .toList(),
      total: json['total'],
      page: json['page'],
      pageSize: json['pageSize'],
    );
  }
}
