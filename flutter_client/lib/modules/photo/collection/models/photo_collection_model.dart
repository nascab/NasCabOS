class PhotoCollectionPreviewItem {
  final String fullpath;

  PhotoCollectionPreviewItem({required this.fullpath});

  factory PhotoCollectionPreviewItem.fromJson(Map<String, dynamic> json) {
    return PhotoCollectionPreviewItem(
      fullpath: json['fullpath']?.toString() ?? '',
    );
  }
}

class PhotoCollectionItem {
  final int id;
  final int ownerId;
  final String name;
  final List<String> pathList;
  final dynamic createTime;
  final List<PhotoCollectionPreviewItem> previews;

  PhotoCollectionItem({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.pathList,
    required this.createTime,
    required this.previews,
  });

  factory PhotoCollectionItem.fromJson(Map<String, dynamic> json) {
    final previewsRaw = (json['previews'] as List<dynamic>? ?? []);
    final previews = previewsRaw
        .whereType<Map>()
        .map(
          (e) => PhotoCollectionPreviewItem.fromJson(e.cast<String, dynamic>()),
        )
        .where((e) => e.fullpath.isNotEmpty)
        .toList();

    final pathListRaw = (json['path_list'] as List<dynamic>? ?? []);
    final pathList = pathListRaw.map((e) => e.toString()).toList();

    return PhotoCollectionItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      ownerId: (json['uid'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      pathList: pathList,
      createTime: json['create_time'],
      previews: previews,
    );
  }
}

class PhotoCollectionListResult {
  final List<PhotoCollectionItem> items;
  final int total;
  final int page;
  final int pageSize;

  PhotoCollectionListResult({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory PhotoCollectionListResult.fromJson(Map<String, dynamic> json) {
    final raw = (json['items'] as List<dynamic>? ?? []);
    final items = raw
        .whereType<Map>()
        .map((e) => PhotoCollectionItem.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.id > 0)
        .toList();

    final pagination =
        (json['pagination'] as Map?)?.cast<String, dynamic>() ?? {};
    final total = (pagination['total'] as num?)?.toInt() ?? 0;
    final page = (pagination['page'] as num?)?.toInt() ?? 1;
    final pageSize = (pagination['pageSize'] as num?)?.toInt() ?? 20;

    return PhotoCollectionListResult(
      items: items,
      total: total,
      page: page,
      pageSize: pageSize,
    );
  }
}
