class VideoHomeItemBean {
  final int id;
  final String mediaType;
  final String path;
  final String filename;
  final String firstFilePath;
  final String nfoName;
  final int nfoYear;
  final double nfoScore;
  final String nfoRegions;
  final String nfoGenres;
  final String posterPath;
  final String fanartPath;
  final String logoPath;
  final double progress;
  final bool isFavorite;
  final String? viewTime;
  final String? createTime;
  final String fullPath;
  final String playFilePath;

  const VideoHomeItemBean({
    required this.id,
    required this.mediaType,
    required this.path,
    required this.filename,
    required this.firstFilePath,
    required this.nfoName,
    required this.nfoYear,
    required this.nfoScore,
    required this.nfoRegions,
    required this.nfoGenres,
    required this.posterPath,
    required this.fanartPath,
    required this.logoPath,
    required this.progress,
    this.isFavorite = false,
    required this.viewTime,
    required this.createTime,
    required this.fullPath,
    this.playFilePath = '',
  });

  VideoHomeItemBean copyWith({
    int? id,
    String? mediaType,
    String? path,
    String? filename,
    String? firstFilePath,
    String? nfoName,
    int? nfoYear,
    double? nfoScore,
    String? nfoRegions,
    String? nfoGenres,
    String? posterPath,
    String? fanartPath,
    String? logoPath,
    double? progress,
    bool? isFavorite,
    String? viewTime,
    String? createTime,
    String? fullPath,
    String? playFilePath,
  }) {
    return VideoHomeItemBean(
      id: id ?? this.id,
      mediaType: mediaType ?? this.mediaType,
      path: path ?? this.path,
      filename: filename ?? this.filename,
      firstFilePath: firstFilePath ?? this.firstFilePath,
      nfoName: nfoName ?? this.nfoName,
      nfoYear: nfoYear ?? this.nfoYear,
      nfoScore: nfoScore ?? this.nfoScore,
      nfoRegions: nfoRegions ?? this.nfoRegions,
      nfoGenres: nfoGenres ?? this.nfoGenres,
      posterPath: posterPath ?? this.posterPath,
      fanartPath: fanartPath ?? this.fanartPath,
      logoPath: logoPath ?? this.logoPath,
      progress: progress ?? this.progress,
      isFavorite: isFavorite ?? this.isFavorite,
      viewTime: viewTime ?? this.viewTime,
      createTime: createTime ?? this.createTime,
      fullPath: fullPath ?? this.fullPath,
      playFilePath: playFilePath ?? this.playFilePath,
    );
  }

  factory VideoHomeItemBean.fromJson(Map<String, dynamic> json) {
    final rawFav = json['is_favorite'];
    final isFav = rawFav == true || rawFav == 1 || rawFav == '1';
    return VideoHomeItemBean(
      id: (json['id'] as num?)?.toInt() ?? 0,
      mediaType: (json['media_type'] as String?) ?? '',
      path: (json['path'] as String?) ?? '',
      filename: (json['filename'] as String?) ?? '',
      firstFilePath:
          (json['first_file_path'] ?? json['firstFilePath'])?.toString() ?? '',
      fullPath: (json['full_path'] ?? json['full_path'])?.toString() ?? '',
      playFilePath:
          (json['play_file_path'] ?? json['playFilePath'])?.toString() ?? '',
      nfoName: (json['nfo_name'] as String?) ?? '',
      nfoYear: (json['nfo_year'] as num?)?.toInt() ?? 0,
      nfoScore: (json['nfo_score'] as num?)?.toDouble() ?? 0,
      nfoRegions: (json['nfo_regions'] as String?) ?? '',
      nfoGenres: (json['nfo_genres'] as String?) ?? '',
      posterPath: (json['poster_path'] as String?) ?? '',
      fanartPath: (json['fanart_path'] as String?) ?? '',
      logoPath: (json['logo_path'] as String?) ?? '',
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      isFavorite: isFav,
      viewTime: json['view_time']?.toString(),
      createTime: json['create_time']?.toString(),
    );
  }
}
