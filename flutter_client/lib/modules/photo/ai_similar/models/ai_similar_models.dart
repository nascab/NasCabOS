import '../../timeline/models/photo_timeline_model.dart';

class AiSimilarPagination {
  final int total;
  final int page;
  final int pageSize;

  const AiSimilarPagination({
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory AiSimilarPagination.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is double) return v.floor();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    return AiSimilarPagination(
      total: asInt(json['total']),
      page: asInt(json['page']),
      pageSize: asInt(json['pageSize'] ?? json['page_size']),
    );
  }
}

class AiSimilarGroupItem {
  final int id;
  final int indexId;
  final List<TimelinePhotoItem> photos;
  final String? createTime;

  const AiSimilarGroupItem({
    required this.id,
    required this.indexId,
    required this.photos,
    required this.createTime,
  });

  factory AiSimilarGroupItem.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is double) return v.floor();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    final rawPhotos = json['photos'] as List<dynamic>? ?? const [];
    final photos = rawPhotos
        .whereType<Map>()
        .map((e) => TimelinePhotoItem.fromJson(e.cast<String, dynamic>()))
        .toList();

    return AiSimilarGroupItem(
      id: asInt(json['id']),
      indexId: asInt(json['index_id']),
      photos: photos,
      createTime: json['create_time']?.toString(),
    );
  }
}

class AiSimilarListResult {
  final bool similarEnable;
  final List<AiSimilarGroupItem> items;
  final AiSimilarPagination pagination;

  const AiSimilarListResult({
    required this.similarEnable,
    required this.items,
    required this.pagination,
  });

  factory AiSimilarListResult.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    final items = rawItems
        .whereType<Map>()
        .map((e) => AiSimilarGroupItem.fromJson(e.cast<String, dynamic>()))
        .toList();

    final paginationJson = (json['pagination'] is Map)
        ? (json['pagination'] as Map)
        : <dynamic, dynamic>{};

    return AiSimilarListResult(
      similarEnable:
          json['similarEnable'] == 1 ||
          json['similarEnable'] == '1' ||
          json['similarEnable'] == true,
      items: items,
      pagination: AiSimilarPagination.fromJson(
        paginationJson.cast<String, dynamic>(),
      ),
    );
  }
}
