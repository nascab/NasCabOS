class MusicSource {
  final int id;
  final String path;
  final bool exists;
  final int scanWhenStart;
  final int scanWhenChange;
  final int isShow;
  final String showType;
  final String? ctime;
  final int scanInterval;
  final int scanIntervalMs;
  final String? scanIntervalConfig;
  final int lastScanTime;

  const MusicSource({
    required this.id,
    required this.path,
    required this.exists,
    required this.scanWhenStart,
    required this.scanWhenChange,
    required this.isShow,
    required this.showType,
    required this.ctime,
    required this.scanInterval,
    required this.scanIntervalMs,
    required this.scanIntervalConfig,
    required this.lastScanTime,
  });

  factory MusicSource.fromJson(Map<String, dynamic> json) {
    final showTypeRaw = (json['show_type'] ?? '').toString();
    final showType = showTypeRaw.isNotEmpty ? showTypeRaw : 'music';
    return MusicSource(
      id: (json['id'] as num?)?.toInt() ?? 0,
      path: (json['path'] as String?) ?? '',
      exists: (json['exists'] as bool?) ?? true,
      scanWhenStart: (json['scan_when_start'] as num?)?.toInt() ?? 0,
      scanWhenChange: (json['scan_when_change'] as num?)?.toInt() ?? 1,
      isShow: (json['is_show'] as num?)?.toInt() ?? 1,
      showType: showType,
      ctime: json['ctime']?.toString(),
      scanInterval: (json['scan_interval'] as num?)?.toInt() ?? 0,
      scanIntervalMs: (json['scan_interval_ms'] as num?)?.toInt() ?? 0,
      scanIntervalConfig: json['scan_interval_config']?.toString(),
      lastScanTime: (json['last_scan_time'] as num?)?.toInt() ?? 0,
    );
  }

  MusicSource copyWith({
    String? path,
    bool? exists,
    int? scanWhenStart,
    int? scanWhenChange,
    int? isShow,
    String? showType,
    String? ctime,
    int? scanInterval,
    int? scanIntervalMs,
    String? scanIntervalConfig,
    int? lastScanTime,
  }) {
    return MusicSource(
      id: id,
      path: path ?? this.path,
      exists: exists ?? this.exists,
      scanWhenStart: scanWhenStart ?? this.scanWhenStart,
      scanWhenChange: scanWhenChange ?? this.scanWhenChange,
      isShow: isShow ?? this.isShow,
      showType: showType ?? this.showType,
      ctime: ctime ?? this.ctime,
      scanInterval: scanInterval ?? this.scanInterval,
      scanIntervalMs: scanIntervalMs ?? this.scanIntervalMs,
      scanIntervalConfig: scanIntervalConfig ?? this.scanIntervalConfig,
      lastScanTime: lastScanTime ?? this.lastScanTime,
    );
  }
}
