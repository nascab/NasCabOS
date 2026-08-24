class PhotoSmartAlbumPreviewItem {
  final String fullpath;

  PhotoSmartAlbumPreviewItem({required this.fullpath});

  factory PhotoSmartAlbumPreviewItem.fromJson(Map<String, dynamic> json) {
    return PhotoSmartAlbumPreviewItem(
      fullpath: json['fullpath']?.toString() ?? '',
    );
  }
}

class PhotoSmartAlbumItem {
  final int id;
  final int uid;
  final String name;
  final String type;
  final Map<String, dynamic> filterContent;
  final List<PhotoSmartAlbumPreviewItem> previews;

  PhotoSmartAlbumItem({
    required this.id,
    required this.uid,
    required this.name,
    required this.type,
    required this.filterContent,
    required this.previews,
  });

  factory PhotoSmartAlbumItem.fromJson(Map<String, dynamic> json) {
    final previewsRaw = (json['previews'] as List<dynamic>? ?? []);
    final previews = previewsRaw
        .whereType<Map>()
        .map(
          (e) => PhotoSmartAlbumPreviewItem.fromJson(e.cast<String, dynamic>()),
        )
        .where((e) => e.fullpath.isNotEmpty)
        .toList();

    return PhotoSmartAlbumItem(
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

class PhotoSmartAlbumListResult {
  final List<PhotoSmartAlbumItem> items;
  final int total;
  final int page;
  final int pageSize;

  PhotoSmartAlbumListResult({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory PhotoSmartAlbumListResult.fromJson(Map<String, dynamic> json) {
    final raw = (json['items'] as List<dynamic>? ?? []);
    final items = raw
        .whereType<Map>()
        .map((e) => PhotoSmartAlbumItem.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.id > 0)
        .toList();

    final pagination =
        (json['pagination'] as Map?)?.cast<String, dynamic>() ?? {};
    final total = (pagination['total'] as num?)?.toInt() ?? 0;
    final page = (pagination['page'] as num?)?.toInt() ?? 1;
    final pageSize = (pagination['pageSize'] as num?)?.toInt() ?? 20;

    return PhotoSmartAlbumListResult(
      items: items,
      total: total,
      page: page,
      pageSize: pageSize,
    );
  }
}

class PhotoSmartAlbumDetail {
  final int id;
  final int uid;
  final String name;
  final String type;
  final Map<String, dynamic> filterContent;

  PhotoSmartAlbumDetail({
    required this.id,
    required this.uid,
    required this.name,
    required this.type,
    required this.filterContent,
  });

  factory PhotoSmartAlbumDetail.fromJson(Map<String, dynamic> json) {
    return PhotoSmartAlbumDetail(
      id: (json['id'] as num?)?.toInt() ?? 0,
      uid: (json['uid'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? 'condition',
      filterContent:
          (json['filter_content'] as Map?)?.cast<String, dynamic>() ?? {},
    );
  }
}
