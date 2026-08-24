class AiSceneCover {
  final String fullpath;

  AiSceneCover({required this.fullpath});

  factory AiSceneCover.fromJson(Map<String, dynamic> json) {
    return AiSceneCover(fullpath: json['fullpath']?.toString() ?? '');
  }
}

class AiSceneItem {
  final String placeName;
  final String placeNameRaw;
  final int photoCount;
  final bool isHide;
  final AiSceneCover? cover;

  AiSceneItem({
    required this.placeName,
    required this.placeNameRaw,
    required this.photoCount,
    required this.isHide,
    this.cover,
  });

  factory AiSceneItem.fromJson(Map<String, dynamic> json) {
    final coverRaw = json['cover'];
    final rawName =
        (json['place_name_raw'] ?? json['placeNameRaw'] ?? json['place_name'])
            ?.toString() ??
        '';
    return AiSceneItem(
      placeName: json['place_name']?.toString() ?? '',
      placeNameRaw: rawName,
      photoCount:
          (json['photo_count'] as num?)?.toInt() ??
          (json['photoCount'] as num?)?.toInt() ??
          0,
      isHide: (json['is_hide'] as num?)?.toInt() == 1,
      cover: coverRaw is Map
          ? AiSceneCover.fromJson(coverRaw.cast<String, dynamic>())
          : null,
    );
  }
}

class AiSceneListResult {
  final List<AiSceneItem> items;
  final int total;
  final int page;
  final int pageSize;
  final bool placeEnable;

  AiSceneListResult({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.placeEnable,
  });

  factory AiSceneListResult.fromJson(Map<String, dynamic> json) {
    bool parseEnable(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v.toInt() == 1;
      if (v is String) return v == '1' || v.toLowerCase() == 'true';
      return true;
    }

    final raw = (json['items'] as List<dynamic>? ?? []);
    final items = raw
        .whereType<Map>()
        .map((e) => AiSceneItem.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.placeNameRaw.trim().isNotEmpty)
        .toList();

    final pagination =
        (json['pagination'] as Map?)?.cast<String, dynamic>() ?? {};
    final total = (pagination['total'] as num?)?.toInt() ?? 0;
    final page = (pagination['page'] as num?)?.toInt() ?? 1;
    final pageSize = (pagination['pageSize'] as num?)?.toInt() ?? 50;

    return AiSceneListResult(
      items: items,
      total: total,
      page: page,
      pageSize: pageSize,
      placeEnable: parseEnable(json['placeEnable'] ?? json['place_enable']),
    );
  }
}
