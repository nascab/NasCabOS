class VideoCollectionPreviewItem {
  final String fullpath;
  final String firstFilePath;

  VideoCollectionPreviewItem({
    required this.fullpath,
    required this.firstFilePath,
  });

  factory VideoCollectionPreviewItem.fromJson(Map<String, dynamic> json) {
    return VideoCollectionPreviewItem(
      fullpath: json['fullpath']?.toString() ?? '',
      firstFilePath: json['first_file_path']?.toString() ?? '',
    );
  }
}

class VideoCollectionItem {
  final int id;
  final int ownerId;
  final String name;
  final List<String> pathList;
  final dynamic createTime;
  final List<VideoCollectionPreviewItem> previews;

  VideoCollectionItem({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.pathList,
    required this.createTime,
    required this.previews,
  });

  factory VideoCollectionItem.fromJson(Map<String, dynamic> json) {
    final previewsRaw = (json['previews'] as List<dynamic>? ?? []);
    final previews = previewsRaw
        .whereType<Map>()
        .map(
          (e) => VideoCollectionPreviewItem.fromJson(e.cast<String, dynamic>()),
        )
        .where((e) => e.fullpath.isNotEmpty)
        .toList();

    final pathListRaw = (json['path_list'] as List<dynamic>? ?? []);
    final pathList = pathListRaw.map((e) => e.toString()).toList();

    return VideoCollectionItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      ownerId: (json['uid'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      pathList: pathList,
      createTime: json['create_time'],
      previews: previews,
    );
  }
}

class VideoCollectionListResult {
  final List<VideoCollectionItem> items;
  final int total;
  final int page;
  final int pageSize;

  VideoCollectionListResult({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory VideoCollectionListResult.fromJson(Map<String, dynamic> json) {
    final raw = (json['items'] as List<dynamic>? ?? []);
    final items = raw
        .whereType<Map>()
        .map((e) => VideoCollectionItem.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.id > 0)
        .toList();

    final pagination =
        (json['pagination'] as Map?)?.cast<String, dynamic>() ?? {};
    final total = (pagination['total'] as num?)?.toInt() ?? 0;
    final page = (pagination['page'] as num?)?.toInt() ?? 1;
    final pageSize = (pagination['pageSize'] as num?)?.toInt() ?? 20;

    return VideoCollectionListResult(
      items: items,
      total: total,
      page: page,
      pageSize: pageSize,
    );
  }
}
