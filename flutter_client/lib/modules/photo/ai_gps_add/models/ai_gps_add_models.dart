int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.floor();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

class AiGpsAddPhotoItem {
  final int id;
  final String path;
  final String filename;
  final int size;
  final int isLvp;
  final int isMergeLvp;
  final int type;
  final int width;
  final int height;
  final String originalDate;
  final String originalTime;
  final String fullpath;
  final int duration;
  final String fileHash;
  final bool isFavorite;
  final String liveFilename;
  final String rawFilename;
  final double latitude;
  final double longitude;

  const AiGpsAddPhotoItem({
    required this.id,
    required this.path,
    required this.filename,
    required this.size,
    required this.isLvp,
    this.isMergeLvp = 0,
    required this.type,
    required this.width,
    required this.height,
    required this.originalDate,
    required this.originalTime,
    required this.fullpath,
    required this.duration,
    required this.fileHash,
    required this.isFavorite,
    required this.liveFilename,
    required this.rawFilename,
    required this.latitude,
    required this.longitude,
  });

  bool get hasGps => latitude != 0 && longitude != 0;

  factory AiGpsAddPhotoItem.fromJson(Map<String, dynamic> json) {
    return AiGpsAddPhotoItem(
      id: _asInt(json['id']),
      path: json['path']?.toString() ?? '',
      filename: json['filename']?.toString() ?? '',
      size: _asInt(json['size'] ?? json['file_size']),
      isLvp: _asInt(json['is_lvp']),
      isMergeLvp: _asInt(json['is_merge_lvp']),
      type: _asInt(json['type']),
      width: _asInt(json['width']),
      height: _asInt(json['height']),
      originalDate: json['original_date']?.toString() ?? '',
      originalTime: json['original_time']?.toString() ?? '',
      fullpath: json['fullpath']?.toString() ?? '',
      duration: _asInt(json['duration']),
      fileHash: json['file_hash']?.toString() ?? '',
      isFavorite: _asInt(json['is_favorite']) == 1,
      liveFilename: json['live_filename']?.toString() ?? '',
      rawFilename: json['raw_filename']?.toString() ?? '',
      latitude: _asDouble(json['latitude']),
      longitude: _asDouble(json['longitude']),
    );
  }
}

class AiGpsAddBatch {
  final int id;
  final String batchKey;
  final int sourceIndexId;
  final String camera;
  final double latitude;
  final double longitude;
  final int status;
  final int windowStart;
  final int windowEnd;
  final List<AiGpsAddPhotoItem> referencePhotos;
  final List<AiGpsAddPhotoItem> pendingPhotos;

  const AiGpsAddBatch({
    required this.id,
    required this.batchKey,
    required this.sourceIndexId,
    required this.camera,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.windowStart,
    required this.windowEnd,
    required this.referencePhotos,
    required this.pendingPhotos,
  });

  factory AiGpsAddBatch.fromJson(Map<String, dynamic> json) {
    final rawReference = json['referencePhotos'] as List<dynamic>? ?? const [];
    final rawPending = json['pendingPhotos'] as List<dynamic>? ?? const [];

    return AiGpsAddBatch(
      id: _asInt(json['id']),
      batchKey: json['batchKey']?.toString() ?? '',
      sourceIndexId: _asInt(json['sourceIndexId']),
      camera: json['camera']?.toString() ?? '',
      latitude: _asDouble(json['latitude']),
      longitude: _asDouble(json['longitude']),
      status: _asInt(json['status']),
      windowStart: _asInt(json['windowStart']),
      windowEnd: _asInt(json['windowEnd']),
      referencePhotos: rawReference
          .whereType<Map>()
          .map((e) => AiGpsAddPhotoItem.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false),
      pendingPhotos: rawPending
          .whereType<Map>()
          .map((e) => AiGpsAddPhotoItem.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }

  AiGpsAddBatch copyWith({
    int? id,
    String? batchKey,
    int? sourceIndexId,
    String? camera,
    double? latitude,
    double? longitude,
    int? status,
    int? windowStart,
    int? windowEnd,
    List<AiGpsAddPhotoItem>? referencePhotos,
    List<AiGpsAddPhotoItem>? pendingPhotos,
  }) {
    return AiGpsAddBatch(
      id: id ?? this.id,
      batchKey: batchKey ?? this.batchKey,
      sourceIndexId: sourceIndexId ?? this.sourceIndexId,
      camera: camera ?? this.camera,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      status: status ?? this.status,
      windowStart: windowStart ?? this.windowStart,
      windowEnd: windowEnd ?? this.windowEnd,
      referencePhotos: referencePhotos ?? this.referencePhotos,
      pendingPhotos: pendingPhotos ?? this.pendingPhotos,
    );
  }
}

class AiGpsAddStatus {
  final bool running;
  final bool hasPendingBatch;
  final bool allCompleted;
  final AiGpsAddBatch? batch;

  const AiGpsAddStatus({
    required this.running,
    required this.hasPendingBatch,
    required this.allCompleted,
    required this.batch,
  });

  factory AiGpsAddStatus.fromJson(Map<String, dynamic> json) {
    final batchJson = json['batch'];
    return AiGpsAddStatus(
      running: json['running'] == true || json['running'] == 1 || json['running'] == '1',
      hasPendingBatch: json['hasPendingBatch'] == true ||
          json['hasPendingBatch'] == 1 ||
          json['hasPendingBatch'] == '1',
      allCompleted: json['allCompleted'] == true ||
          json['allCompleted'] == 1 ||
          json['allCompleted'] == '1',
      batch: batchJson is Map
          ? AiGpsAddBatch.fromJson(batchJson.cast<String, dynamic>())
          : null,
    );
  }
}
