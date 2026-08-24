class BookCollectionPreviewItem {
  final int id;
  final String fileHash;
  final String showType;
  final int coverState;
  final String fullPath;
  final String firstFilePath;

  BookCollectionPreviewItem({
    required this.id,
    required this.fileHash,
    required this.showType,
    required this.coverState,
    required this.fullPath,
    required this.firstFilePath,
  });

  factory BookCollectionPreviewItem.fromJson(Map<String, dynamic> json) {
    return BookCollectionPreviewItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      fileHash: json['file_hash']?.toString() ?? '',
      showType: json['show_type']?.toString() ?? '',
      coverState: (json['cover_state'] as num?)?.toInt() ?? 0,
      fullPath: json['full_path']?.toString() ?? '',
      firstFilePath: json['first_file_path']?.toString() ?? '',
    );
  }
}

class BookCollectionItem {
  final int id;
  final int ownerId;
  final String name;
  final List<String> pathList;
  final dynamic createTime;
  final List<BookCollectionPreviewItem> previews;

  BookCollectionItem({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.pathList,
    required this.createTime,
    required this.previews,
  });

  factory BookCollectionItem.fromJson(Map<String, dynamic> json) {
    final pathListRaw = (json['path_list'] as List<dynamic>? ?? []);
    final pathList = pathListRaw.map((e) => e.toString()).toList();

    final previewsRaw = (json['previews'] as List<dynamic>? ?? []);
    final previews = previewsRaw
        .whereType<Map>()
        .map(
          (e) => BookCollectionPreviewItem.fromJson(e.cast<String, dynamic>()),
        )
        .where((e) => e.id > 0)
        .toList();

    return BookCollectionItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      ownerId: (json['uid'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      pathList: pathList,
      createTime: json['create_time'],
      previews: previews,
    );
  }
}

class BookCollectionListResult {
  final List<BookCollectionItem> items;
  final int total;
  final int page;
  final int pageSize;

  BookCollectionListResult({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory BookCollectionListResult.fromJson(Map<String, dynamic> json) {
    final raw = (json['items'] as List<dynamic>? ?? []);
    final items = raw
        .whereType<Map>()
        .map((e) => BookCollectionItem.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.id > 0)
        .toList();

    final pagination =
        (json['pagination'] as Map?)?.cast<String, dynamic>() ?? {};
    final total = (pagination['total'] as num?)?.toInt() ?? 0;
    final page = (pagination['page'] as num?)?.toInt() ?? 1;
    final pageSize = (pagination['pageSize'] as num?)?.toInt() ?? 20;

    return BookCollectionListResult(
      items: items,
      total: total,
      page: page,
      pageSize: pageSize,
    );
  }
}
