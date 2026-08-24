enum PhotoBackupSourceType { album, folder }

enum PhotoBackupRunTrigger { uploadNew, uploadAll, autoStart }

class PhotoBackupTask {
  final int id;
  final String serverId;
  final int userId;
  final String name;
  final PhotoBackupSourceType sourceType;
  final String sourceId;
  final String sourceName;
  final String targetDir;
  final String nameStrategy;
  final String saveType;
  final bool uploadLivePhotoVideo;
  final bool autoStartOnLaunch;
  final int createdAtMs;
  final int updatedAtMs;

  const PhotoBackupTask({
    required this.id,
    required this.serverId,
    required this.userId,
    required this.name,
    required this.sourceType,
    required this.sourceId,
    required this.sourceName,
    required this.targetDir,
    required this.nameStrategy,
    required this.saveType,
    required this.uploadLivePhotoVideo,
    required this.autoStartOnLaunch,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  static PhotoBackupTask fromMap(Map<String, Object?> row) {
    int asInt(Object? value, int fallback) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? fallback;
    }

    final sourceTypeRaw = (row['source_type']?.toString() ?? '').trim();
    final sourceType = sourceTypeRaw == 'album'
        ? PhotoBackupSourceType.album
        : PhotoBackupSourceType.folder;

    return PhotoBackupTask(
      id: asInt(row['id'], 0),
      serverId: (row['server_id']?.toString() ?? '').trim(),
      userId: asInt(row['user_id'], 0),
      name: (row['name']?.toString() ?? '').trim(),
      sourceType: sourceType,
      sourceId: (row['source_id']?.toString() ?? '').trim(),
      sourceName: (row['source_name']?.toString() ?? '').trim(),
      targetDir: (row['target_dir']?.toString() ?? '').trim(),
      nameStrategy: (row['name_strategy']?.toString() ?? 'skip').trim(),
      saveType: (row['save_type']?.toString() ?? '').trim(),
      uploadLivePhotoVideo: asInt(row['upload_live_photo_video'], 0) == 1,
      autoStartOnLaunch: asInt(row['auto_start_on_launch'], 0) == 1,
      createdAtMs: asInt(row['created_at_ms'], 0),
      updatedAtMs: asInt(row['updated_at_ms'], 0),
    );
  }
}

class PhotoBackupRunRecord {
  final int id;
  final int taskId;
  final String triggerType;
  final int startedAtMs;
  final int finishedAtMs;
  final int successCount;
  final int failedCount;
  final int totalBytes;

  const PhotoBackupRunRecord({
    required this.id,
    required this.taskId,
    required this.triggerType,
    required this.startedAtMs,
    required this.finishedAtMs,
    required this.successCount,
    required this.failedCount,
    required this.totalBytes,
  });

  static PhotoBackupRunRecord fromMap(Map<String, Object?> row) {
    int asInt(Object? value, int fallback) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? fallback;
    }

    return PhotoBackupRunRecord(
      id: asInt(row['id'], 0),
      taskId: asInt(row['task_id'], 0),
      triggerType: (row['trigger_type']?.toString() ?? '').trim(),
      startedAtMs: asInt(row['started_at_ms'], 0),
      finishedAtMs: asInt(row['finished_at_ms'], 0),
      successCount: asInt(row['success_count'], 0),
      failedCount: asInt(row['failed_count'], 0),
      totalBytes: asInt(row['total_bytes'], 0),
    );
  }
}

class PhotoBackupFileRecord {
  final int id;
  final int taskId;
  final int runId;
  final String sourceUniqueId;
  final String displayName;
  final String localPath;
  final int size;
  final int sourceCreateAtMs;
  final int uploadedAtMs;
  final String status;
  final String error;

  const PhotoBackupFileRecord({
    required this.id,
    required this.taskId,
    required this.runId,
    required this.sourceUniqueId,
    required this.displayName,
    required this.localPath,
    required this.size,
    required this.sourceCreateAtMs,
    required this.uploadedAtMs,
    required this.status,
    required this.error,
  });

  static PhotoBackupFileRecord fromMap(Map<String, Object?> row) {
    int asInt(Object? value, int fallback) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? fallback;
    }

    return PhotoBackupFileRecord(
      id: asInt(row['id'], 0),
      taskId: asInt(row['task_id'], 0),
      runId: asInt(row['run_id'], 0),
      sourceUniqueId: (row['source_unique_id']?.toString() ?? '').trim(),
      displayName: (row['display_name']?.toString() ?? '').trim(),
      localPath: (row['local_path']?.toString() ?? '').trim(),
      size: asInt(row['size'], 0),
      sourceCreateAtMs: asInt(row['source_create_at_ms'], 0),
      uploadedAtMs: asInt(row['uploaded_at_ms'], 0),
      status: (row['status']?.toString() ?? '').trim(),
      error: (row['error']?.toString() ?? '').trim(),
    );
  }
}
