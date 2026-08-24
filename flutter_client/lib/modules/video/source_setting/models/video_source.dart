class VideoSource {
  final int id;
  final String path;
  final bool exists;
  final String mediaType;
  final int matchNfo;
  final int scanWhenStart;
  final int scanWhenChange;
  final int isShow;
  final String? ctime;
  final int scanInterval;
  final int scanIntervalMs;
  final String? scanIntervalConfig;
  final int lastScanTime;

  const VideoSource({
    required this.id,
    required this.path,
    required this.exists,
    required this.mediaType,
    required this.matchNfo,
    required this.scanWhenStart,
    required this.scanWhenChange,
    required this.isShow,
    required this.ctime,
    required this.scanInterval,
    required this.scanIntervalMs,
    required this.scanIntervalConfig,
    required this.lastScanTime,
  });

  factory VideoSource.fromJson(Map<String, dynamic> json) {
    return VideoSource(
      id: (json['id'] as num?)?.toInt() ?? 0,
      path: (json['path'] as String?) ?? '',
      exists: (json['exists'] as bool?) ?? true,
      mediaType: (json['media_type'] as String?) ?? '',
      matchNfo: (json['match_nfo'] as num?)?.toInt() ?? 0,
      scanWhenStart: (json['scan_when_start'] as num?)?.toInt() ?? 0,
      scanWhenChange: (json['scan_when_change'] as num?)?.toInt() ?? 1,
      isShow: (json['is_show'] as num?)?.toInt() ?? 1,
      ctime: json['ctime']?.toString(),
      scanInterval: (json['scan_interval'] as num?)?.toInt() ?? 0,
      scanIntervalMs: (json['scan_interval_ms'] as num?)?.toInt() ?? 0,
      scanIntervalConfig: json['scan_interval_config']?.toString(),
      lastScanTime: (json['last_scan_time'] as num?)?.toInt() ?? 0,
    );
  }

  VideoSource copyWith({
    String? mediaType,
    int? matchNfo,
    int? scanWhenStart,
    int? scanWhenChange,
    int? isShow,
    int? scanInterval,
    int? scanIntervalMs,
    String? scanIntervalConfig,
    int? lastScanTime,
  }) {
    return VideoSource(
      id: id,
      path: path,
      exists: exists,
      mediaType: mediaType ?? this.mediaType,
      matchNfo: matchNfo ?? this.matchNfo,
      scanWhenStart: scanWhenStart ?? this.scanWhenStart,
      scanWhenChange: scanWhenChange ?? this.scanWhenChange,
      isShow: isShow ?? this.isShow,
      ctime: ctime,
      scanInterval: scanInterval ?? this.scanInterval,
      scanIntervalMs: scanIntervalMs ?? this.scanIntervalMs,
      scanIntervalConfig: scanIntervalConfig ?? this.scanIntervalConfig,
      lastScanTime: lastScanTime ?? this.lastScanTime,
    );
  }
}
