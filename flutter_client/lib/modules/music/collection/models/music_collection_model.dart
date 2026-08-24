class MusicCollectionPreviewItem {
  final int id;
  final String path;
  final String filename;
  final String showType;
  final String firstFilePath;
  final int hasInnerCover;

  MusicCollectionPreviewItem({
    required this.id,
    required this.path,
    required this.filename,
    required this.showType,
    required this.firstFilePath,
    this.hasInnerCover = 0,
  });

  factory MusicCollectionPreviewItem.fromJson(Map<String, dynamic> json) {
    return MusicCollectionPreviewItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      path: json['path']?.toString() ?? '',
      filename: json['filename']?.toString() ?? '',
      showType: json['show_type']?.toString() ?? '',
      firstFilePath: json['first_file_path']?.toString() ?? '',
      hasInnerCover: (json['has_inner_cover'] as num?)?.toInt() ?? 0,
    );
  }

  String get fullPath {
    final p = path.trim();
    final f = filename.trim();
    if (p.isEmpty) return '';
    if (f.isEmpty) return p;
    if (p.endsWith('/')) return '$p$f';
    return '$p/$f';
  }
}

class MusicCollectionItem {
  final int id;
  final int ownerId;
  final String name;
  final List<String> pathList;
  final dynamic createTime;
  final List<MusicCollectionPreviewItem> previews;

  MusicCollectionItem({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.pathList,
    required this.createTime,
    required this.previews,
  });

  factory MusicCollectionItem.fromJson(Map<String, dynamic> json) {
    final pathListRaw = (json['path_list'] as List<dynamic>? ?? []);
    final pathList = pathListRaw.map((e) => e.toString()).toList();

    final previewsRaw = (json['previews'] as List<dynamic>? ?? []);
    final previews = previewsRaw
        .whereType<Map>()
        .map(
          (e) => MusicCollectionPreviewItem.fromJson(e.cast<String, dynamic>()),
        )
        .where((e) => e.id > 0)
        .toList();

    return MusicCollectionItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      ownerId: (json['uid'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      pathList: pathList,
      createTime: json['create_time'],
      previews: previews,
    );
  }
}

class MusicCollectionListResult {
  final List<MusicCollectionItem> items;
  final int total;
  final int page;
  final int pageSize;

  MusicCollectionListResult({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory MusicCollectionListResult.fromJson(Map<String, dynamic> json) {
    final raw = (json['items'] as List<dynamic>? ?? []);
    final items = raw
        .whereType<Map>()
        .map((e) => MusicCollectionItem.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.id > 0)
        .toList();

    final pagination =
        (json['pagination'] as Map?)?.cast<String, dynamic>() ?? {};
    final total = (pagination['total'] as num?)?.toInt() ?? 0;
    final page = (pagination['page'] as num?)?.toInt() ?? 1;
    final pageSize = (pagination['pageSize'] as num?)?.toInt() ?? 20;

    return MusicCollectionListResult(
      items: items,
      total: total,
      page: page,
      pageSize: pageSize,
    );
  }
}
