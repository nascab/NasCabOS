/// 时间轴日期item
class TimelineDateItem {
  final String originalDate;
  final int count;

  TimelineDateItem({required this.originalDate, required this.count});

  factory TimelineDateItem.fromJson(Map<String, dynamic> json) {
    return TimelineDateItem(
      originalDate: json['original_date'] ?? '',
      count: _asInt(json['date_photo_count']),
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class TimelinePhotoItem {
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
  final String rawShowExt;

  TimelinePhotoItem({
    required this.id,
    required this.path,
    required this.filename,
    this.size = 0,
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
    this.liveFilename = '',
    this.rawFilename = '',
    this.rawShowExt = '',
  });

  factory TimelinePhotoItem.fromJson(Map<String, dynamic> json) {
    return TimelinePhotoItem(
      id: TimelineDateItem._asInt(json['id']),
      path: json['path'] ?? '',
      filename: json['filename'] ?? '',
      size: TimelineDateItem._asInt(json['size'] ?? json['file_size']),
      isLvp: TimelineDateItem._asInt(json['is_lvp']),
      isMergeLvp: TimelineDateItem._asInt(json['is_merge_lvp']),
      type: TimelineDateItem._asInt(json['type']),
      width: TimelineDateItem._asInt(json['width']),
      height: TimelineDateItem._asInt(json['height']),
      originalDate: json['original_date'] ?? '',
      originalTime: json['original_time']?.toString() ?? '',
      fullpath: json['fullpath'] ?? '',
      duration: json['duration'] != null
          ? TimelineDateItem._asInt(json['duration'])
          : 0,
      fileHash: json['file_hash'] ?? '',
      isFavorite: TimelineDateItem._asInt(json['is_favorite']) == 1,
      liveFilename: json['live_filename'] ?? '',
      rawFilename: json['raw_filename'] ?? '',
      rawShowExt: json['raw_show_ext'] ?? '',
    );
  }

  TimelinePhotoItem copyWith({
    int? id,
    String? path,
    String? filename,
    int? size,
    int? isLvp,
    int? type,
    int? width,
    int? height,
    String? originalDate,
    String? originalTime,
    String? fullpath,
    int? duration,
    String? fileHash,
    bool? isFavorite,
    String? liveFilename,
    String? rawFilename,
    String? rawShowExt,
  }) {
    return TimelinePhotoItem(
      id: id ?? this.id,
      path: path ?? this.path,
      filename: filename ?? this.filename,
      size: size ?? this.size,
      isLvp: isLvp ?? this.isLvp,
      type: type ?? this.type,
      width: width ?? this.width,
      height: height ?? this.height,
      originalDate: originalDate ?? this.originalDate,
      originalTime: originalTime ?? this.originalTime,
      fullpath: fullpath ?? this.fullpath,
      duration: duration ?? this.duration,
      fileHash: fileHash ?? this.fileHash,
      isFavorite: isFavorite ?? this.isFavorite,
      liveFilename: liveFilename ?? this.liveFilename,
      rawFilename: rawFilename ?? this.rawFilename,
      rawShowExt: rawShowExt ?? this.rawShowExt,
    );
  }
}

class TimelinePathItem {
  final String path;
  final bool valid;

  TimelinePathItem({required this.path, required this.valid});

  factory TimelinePathItem.fromJson(Map<String, dynamic> json) {
    return TimelinePathItem(
      path: json['path'] ?? '',
      valid: json['valid'] ?? false,
    );
  }
}

class TimelineDetectedFaceItem {
  final int faceId;
  final int faceCount;
  final String? name;
  final bool isHide;

  TimelineDetectedFaceItem({
    required this.faceId,
    required this.faceCount,
    this.name,
    this.isHide = false,
  });

  factory TimelineDetectedFaceItem.fromJson(Map<String, dynamic> json) {
    return TimelineDetectedFaceItem(
      faceId: TimelineDateItem._asInt(json['face_id'] ?? json['faceId']),
      faceCount: TimelineDateItem._asInt(
        json['face_count'] ?? json['faceCount'],
      ),
      name: json['name']?.toString(),
      isHide: TimelineDateItem._asInt(json['is_hide'] ?? json['isHide']) == 1,
    );
  }
}

class TimelineDateListResult {
  final List<TimelineDateItem> items;
  final List<TimelinePathItem> validPaths;

  TimelineDateListResult({required this.items, required this.validPaths});
}

class TimelineDateInfo {
  final String originalDate;
  final String geo;
  final String camera;

  TimelineDateInfo({
    required this.originalDate,
    required this.geo,
    required this.camera,
  });

  factory TimelineDateInfo.fromJson(Map<String, dynamic> json) {
    return TimelineDateInfo(
      originalDate: json['original_date'] ?? '',
      geo: json['geo'] ?? '',
      camera: json['camera'] ?? '',
    );
  }
}

class TimelinePhotoListResult {
  final List<TimelinePhotoItem> photoList;
  final List<TimelineDateInfo> dateInfoList;

  TimelinePhotoListResult({
    required this.photoList,
    required this.dateInfoList,
  });
}

class TimelineYearItem {
  final int year;
  final int count;
  final TimelinePhotoItem cover;

  TimelineYearItem({
    required this.year,
    required this.count,
    required this.cover,
  });

  factory TimelineYearItem.fromJson(Map<String, dynamic> json) {
    return TimelineYearItem(
      year: TimelineDateItem._asInt(json['year']),
      count: TimelineDateItem._asInt(json['count']),
      cover: TimelinePhotoItem.fromJson(
        (json['cover'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
    );
  }
}

class TimelineYearListResult {
  final List<TimelineYearItem> items;
  TimelineYearListResult({required this.items});
}

/// 单次拉取照片列表接口后的处理结果。
///
/// 该结果主要用于：
/// - 决定是否还有更多数据（根据 `incomingCount` 与分页大小对比）
/// - 识别本次是否真正“新增”了数据（`addedCount`），避免陷入重复拉取
class FetchResult {
  final bool hasData;
  final int incomingCount;
  final int addedCount;

  const FetchResult({
    required this.hasData,
    required this.incomingCount,
    required this.addedCount,
  });
}
