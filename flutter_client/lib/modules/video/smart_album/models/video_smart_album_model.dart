class VideoSmartAlbumPreviewItem {
  final String fullpath;
  final String firstFilePath;

  VideoSmartAlbumPreviewItem({
    required this.fullpath,
    required this.firstFilePath,
  });

  factory VideoSmartAlbumPreviewItem.fromJson(Map<String, dynamic> json) {
    return VideoSmartAlbumPreviewItem(
      fullpath: json['fullpath']?.toString() ?? '',
      firstFilePath: json['first_file_path']?.toString() ?? '',
    );
  }
}

class VideoSmartAlbumItem {
  final int id;
  final int uid;
  final String name;
  final String type;
  final Map<String, dynamic> filterContent;
  final List<VideoSmartAlbumPreviewItem> previews;

  VideoSmartAlbumItem({
    required this.id,
    required this.uid,
    required this.name,
    required this.type,
    required this.filterContent,
    required this.previews,
  });

  factory VideoSmartAlbumItem.fromJson(Map<String, dynamic> json) {
    final previewsRaw = (json['previews'] as List<dynamic>? ?? []);
    final previews = previewsRaw
        .whereType<Map>()
        .map(
          (e) => VideoSmartAlbumPreviewItem.fromJson(e.cast<String, dynamic>()),
        )
        .where((e) => e.fullpath.isNotEmpty || e.firstFilePath.isNotEmpty)
        .toList();

    return VideoSmartAlbumItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      uid: (json['uid'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? 'condition',
      filterContent:
          (json['filter_content'] as Map?)?.cast<String, dynamic>() ?? {},
      previews: previews,
    );
  }
}

class VideoSmartAlbumListResult {
  final List<VideoSmartAlbumItem> items;
  final int total;
  final int page;
  final int pageSize;

  VideoSmartAlbumListResult({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory VideoSmartAlbumListResult.fromJson(Map<String, dynamic> json) {
    final raw = (json['items'] as List<dynamic>? ?? []);
    final items = raw
        .whereType<Map>()
        .map((e) => VideoSmartAlbumItem.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.id > 0)
        .toList();

    final pagination =
        (json['pagination'] as Map?)?.cast<String, dynamic>() ?? {};
    final total = (pagination['total'] as num?)?.toInt() ?? 0;
    final page = (pagination['page'] as num?)?.toInt() ?? 1;
    final pageSize = (pagination['pageSize'] as num?)?.toInt() ?? 20;

    return VideoSmartAlbumListResult(
      items: items,
      total: total,
      page: page,
      pageSize: pageSize,
    );
  }
}

class VideoSmartAlbumDetail {
  final int id;
  final int uid;
  final String name;
  final String type;
  final Map<String, dynamic> filterContent;

  VideoSmartAlbumDetail({
    required this.id,
    required this.uid,
    required this.name,
    required this.type,
    required this.filterContent,
  });

  factory VideoSmartAlbumDetail.fromJson(Map<String, dynamic> json) {
    return VideoSmartAlbumDetail(
      id: (json['id'] as num?)?.toInt() ?? 0,
      uid: (json['uid'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? 'condition',
      filterContent:
          (json['filter_content'] as Map?)?.cast<String, dynamic>() ?? {},
    );
  }
}
