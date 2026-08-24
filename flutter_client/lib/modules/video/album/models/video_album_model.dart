class VideoAlbumPreviewItem {
  final String fullpath;
  final String firstFilePath;

  VideoAlbumPreviewItem({required this.fullpath, required this.firstFilePath});

  factory VideoAlbumPreviewItem.fromJson(Map<String, dynamic> json) {
    return VideoAlbumPreviewItem(
      fullpath: json['fullpath']?.toString() ?? '',
      firstFilePath: json['first_file_path']?.toString() ?? '',
    );
  }
}

class VideoAlbumItem {
  final int id;
  final int ownerId;
  final String name;
  final bool isPublic;
  final bool isOwner;
  final List<VideoAlbumPreviewItem> previews;

  VideoAlbumItem({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.isPublic,
    required this.isOwner,
    required this.previews,
  });

  factory VideoAlbumItem.fromJson(Map<String, dynamic> json) {
    final previewsRaw = (json['previews'] as List<dynamic>? ?? []);
    final previews = previewsRaw
        .whereType<Map>()
        .map((e) => VideoAlbumPreviewItem.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.fullpath.isNotEmpty || e.firstFilePath.isNotEmpty)
        .toList();

    return VideoAlbumItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      ownerId: (json['owner_id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      isPublic:
          (json['is_public'] as num?)?.toInt() == 1 ||
          json['is_public'] == true,
      isOwner: json['is_owner'] == true,
      previews: previews,
    );
  }
}

class VideoAlbumListResult {
  final List<VideoAlbumItem> items;
  final int total;
  final int page;
  final int pageSize;

  VideoAlbumListResult({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory VideoAlbumListResult.fromJson(Map<String, dynamic> json) {
    final raw = (json['items'] as List<dynamic>? ?? []);
    final items = raw
        .whereType<Map>()
        .map((e) => VideoAlbumItem.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.id > 0)
        .toList();

    final pagination =
        (json['pagination'] as Map?)?.cast<String, dynamic>() ?? {};
    final total = (pagination['total'] as num?)?.toInt() ?? 0;
    final page = (pagination['page'] as num?)?.toInt() ?? 1;
    final pageSize = (pagination['pageSize'] as num?)?.toInt() ?? 20;

    return VideoAlbumListResult(
      items: items,
      total: total,
      page: page,
      pageSize: pageSize,
    );
  }
}

class VideoAlbumDetail {
  final int id;
  final int ownerId;
  final String name;
  final bool isPublic;

  VideoAlbumDetail({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.isPublic,
  });

  factory VideoAlbumDetail.fromJson(Map<String, dynamic> json) {
    return VideoAlbumDetail(
      id: (json['id'] as num?)?.toInt() ?? 0,
      ownerId: (json['owner_id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      isPublic:
          (json['is_public'] as num?)?.toInt() == 1 ||
          json['is_public'] == true,
    );
  }
}
