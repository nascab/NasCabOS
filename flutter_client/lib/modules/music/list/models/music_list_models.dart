class MusicListItem {
  final int id;
  final String path;
  final String filename;
  final String fileHash;
  final String title;
  final String artist;
  final String album;
  final String year;
  final String genre;
  /// 时长（秒），与数据库及接口约定一致。
  final int duration;
  final int size;
  final String ext;
  final int hasInnerCover;
  final String showType;
  final int musicCount;
  final bool isFavorite;
  final bool isFromFile;
  final String? ctime;
  final String? mtime;
  final String? birthtime;
  final String firstFilePath;
  final String fullPath;
  final int? bitrate;
  final int? sampleRate;
  final int? bitDepth;

  const MusicListItem({
    required this.id,
    required this.path,
    required this.filename,
    required this.fileHash,
    required this.title,
    required this.artist,
    required this.album,
    required this.year,
    required this.genre,
    required this.duration,
    required this.size,
    required this.ext,
    required this.hasInnerCover,
    required this.showType,
    required this.musicCount,
    required this.isFavorite,
    this.isFromFile = false,
    required this.ctime,
    required this.mtime,
    required this.birthtime,
    required this.firstFilePath,
    required this.fullPath,
    required this.bitrate,
    required this.sampleRate,
    required this.bitDepth,
  });

  bool get isSeries => showType.trim().toLowerCase() == 'series';

  String get displayTitle {
    return filename.trim();
    // final t = title.trim();
    // if (t.isNotEmpty) return t;
    // return filename.trim();
  }

  String get displaySubtitle {
    final a = artist.trim();
    final al = album.trim();
    if (a.isNotEmpty && al.isNotEmpty) return '$a · $al';
    if (a.isNotEmpty) return a;
    if (al.isNotEmpty) return al;
    return '';
  }

  MusicListItem copyWith({
    bool? isFavorite,
    int? id,
    String? showType,
    bool? isFromFile,
  }) => MusicListItem(
    id: id ?? this.id,
    path: path,
    filename: filename,
    fileHash: fileHash,
    title: title,
    artist: artist,
    album: album,
    year: year,
    genre: genre,
    duration: duration,
    size: size,
    ext: ext,
    hasInnerCover: hasInnerCover,
    showType: showType ?? this.showType,
    musicCount: musicCount,
    isFavorite: isFavorite ?? this.isFavorite,
    isFromFile: isFromFile ?? this.isFromFile,
    ctime: ctime,
    mtime: mtime,
    birthtime: birthtime,
    firstFilePath: firstFilePath,
    fullPath: fullPath,
    bitrate: bitrate,
    sampleRate: sampleRate,
    bitDepth: bitDepth,
  );

  factory MusicListItem.fromJson(Map<String, dynamic> json) {
    final isFavoriteRaw = json['is_favorite'] ?? json['isFavorite'];
    final isFavorite = isFavoriteRaw == true || isFavoriteRaw == 1;
    final isFromFileRaw = json['is_from_file'] ?? json['isFromFile'];
    final isFromFile = isFromFileRaw == true || isFromFileRaw == 1;

    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      if (v is String) {
        final s = v.trim();
        if (s.isEmpty) return null;
        return num.tryParse(s)?.toInt();
      }
      return null;
    }

    return MusicListItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      path: (json['path']?.toString() ?? ''),
      filename: (json['filename']?.toString() ?? ''),
      fileHash: (json['file_hash'] ?? json['fileHash'])?.toString() ?? '',
      title: (json['title']?.toString() ?? ''),
      artist: (json['artist']?.toString() ?? ''),
      album: (json['album']?.toString() ?? ''),
      year: (json['year']?.toString() ?? ''),
      genre: (json['genre']?.toString() ?? ''),
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      size: (json['size'] as num?)?.toInt() ?? 0,
      ext: (json['ext']?.toString() ?? ''),
      hasInnerCover: (json['has_inner_cover'] as num?)?.toInt() ?? 0,
      showType: (json['show_type']?.toString() ?? ''),
      musicCount: (json['music_count'] as num?)?.toInt() ?? 0,
      isFavorite: isFavorite,
      isFromFile: isFromFile,
      ctime: json['ctime']?.toString(),
      mtime: json['mtime']?.toString(),
      birthtime: json['birthtime']?.toString(),
      firstFilePath:
          (json['first_file_path'] ?? json['firstFilePath'])?.toString() ?? '',
      fullPath: (json['full_path'] ?? json['fullPath'])?.toString() ?? '',
      bitrate: parseInt(json['bitrate']),
      sampleRate: parseInt(json['sample_rate'] ?? json['sampleRate']),
      bitDepth: parseInt(json['bit_depth'] ?? json['bitDepth']),
    );
  }
}

class MusicListPagination {
  final int total;
  final int page;
  final int limit;
  final int totalPages;
  final bool hasNextPage;
  final bool hasPrevPage;

  const MusicListPagination({
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
    required this.hasNextPage,
    required this.hasPrevPage,
  });

  const MusicListPagination.empty()
    : total = 0,
      page = 1,
      limit = 30,
      totalPages = 0,
      hasNextPage = false,
      hasPrevPage = false;

  factory MusicListPagination.fromJson(Map<String, dynamic> json) {
    return MusicListPagination(
      total: (json['total'] as num?)?.toInt() ?? 0,
      page: (json['page'] as num?)?.toInt() ?? 1,
      limit: (json['limit'] as num?)?.toInt() ?? 30,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 0,
      hasNextPage: (json['hasNextPage'] as bool?) ?? false,
      hasPrevPage: (json['hasPrevPage'] as bool?) ?? false,
    );
  }
}

class MusicListFilterOptions {
  final List<String> artists;
  final List<String> albums;
  final List<String> genres;

  const MusicListFilterOptions({
    required this.artists,
    required this.albums,
    required this.genres,
  });

  factory MusicListFilterOptions.fromJson(Map<String, dynamic> json) {
    List<String> parseStringList(dynamic v) {
      final list = v is List ? v : const <dynamic>[];
      return list
          .map((e) => e.toString())
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return MusicListFilterOptions(
      artists: parseStringList(json['artists']),
      albums: parseStringList(json['albums']),
      genres: parseStringList(json['genres']),
    );
  }
}

class MusicListPathItem {
  final String path;
  final bool valid;

  const MusicListPathItem({required this.path, required this.valid});

  factory MusicListPathItem.fromJson(Map<String, dynamic> json) {
    return MusicListPathItem(
      path: (json['path']?.toString() ?? '').trim(),
      valid: (json['valid'] as bool?) ?? false,
    );
  }
}

class MusicListPagedResult {
  final List<MusicListItem> items;
  final MusicListPagination pagination;
  final MusicListFilterOptions? filters;
  final List<MusicListPathItem> validPaths;

  const MusicListPagedResult({
    required this.items,
    required this.pagination,
    required this.filters,
    required this.validPaths,
  });

  const MusicListPagedResult.empty()
    : items = const <MusicListItem>[],
      pagination = const MusicListPagination.empty(),
      filters = null,
      validPaths = const <MusicListPathItem>[];

  factory MusicListPagedResult.fromJson(Map<String, dynamic> json) {
    List<MusicListItem> parseItems(dynamic v) {
      final list = v is List ? v : const <dynamic>[];
      return list
          .whereType<Map>()
          .map((e) => MusicListItem.fromJson(e.cast<String, dynamic>()))
          .where((e) => e.id > 0)
          .toList();
    }

    List<MusicListPathItem> parseValidPaths(dynamic v) {
      final list = v is List ? v : const <dynamic>[];
      return list
          .map((e) {
            if (e is String) {
              final p = e.trim();
              return MusicListPathItem(path: p, valid: true);
            }
            if (e is Map) {
              return MusicListPathItem.fromJson(e.cast<String, dynamic>());
            }
            return const MusicListPathItem(path: '', valid: false);
          })
          .where((e) => e.path.isNotEmpty)
          .toList();
    }

    final paginationRaw = json['pagination'];
    final paginationMap = paginationRaw is Map
        ? paginationRaw.cast<String, dynamic>()
        : <String, dynamic>{};
    final filtersRaw = json['filters'] ?? json['filterOptions'];
    final filtersMap = filtersRaw is Map
        ? filtersRaw.cast<String, dynamic>()
        : null;
    final validPathsRaw = json['validPaths'] ?? json['valid_paths'];
    return MusicListPagedResult(
      items: parseItems(json['items']),
      pagination: MusicListPagination.fromJson(paginationMap),
      filters: filtersMap == null
          ? null
          : MusicListFilterOptions.fromJson(filtersMap),
      validPaths: parseValidPaths(validPathsRaw),
    );
  }
}

class MusicListPagingQuery {
  final int page;
  final int pageSize;
  final bool hasMore;
  final String? listType;
  final int? listId;
  final int? seriesIndexId;
  final int? collectionId;
  final bool isFavorite;
  final bool isHistory;
  final String? search;
  final List<String>? artists;
  final List<String>? albums;
  final List<String>? genres;
  final List<String>? sourceList;
  final String? sortBy;
  final String? sortOrder;

  const MusicListPagingQuery({
    required this.page,
    required this.pageSize,
    required this.hasMore,
    this.listType,
    this.listId,
    this.seriesIndexId,
    this.collectionId,
    this.isFavorite = false,
    this.isHistory = false,
    this.search,
    this.artists,
    this.albums,
    this.genres,
    this.sourceList,
    this.sortBy,
    this.sortOrder,
  });
}
