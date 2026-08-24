class AiFaceItem {
  final int faceId;
  final int faceCount;
  final String? coverFileHash;
  final String? name;
  final bool isHide;

  AiFaceItem({
    required this.faceId,
    required this.faceCount,
    this.coverFileHash,
    this.name,
    this.isHide = false,
  });

  factory AiFaceItem.fromJson(Map<String, dynamic> json) {
    return AiFaceItem(
      faceId:
          (json['face_id'] as num?)?.toInt() ??
          (json['faceId'] as num?)?.toInt() ??
          0,
      faceCount:
          (json['face_count'] as num?)?.toInt() ??
          (json['faceCount'] as num?)?.toInt() ??
          0,
      coverFileHash: json['cover_file_hash']?.toString(),
      name: json['name']?.toString(),
      isHide: (json['is_hide'] as num?)?.toInt() == 1,
    );
  }
}

class AiFaceListResult {
  final List<AiFaceItem> items;
  final int total;
  final int page;
  final int pageSize;
  final bool faceEnable;

  AiFaceListResult({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.faceEnable,
  });

  factory AiFaceListResult.fromJson(Map<String, dynamic> json) {
    bool parseEnable(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v.toInt() == 1;
      if (v is String) return v == '1' || v.toLowerCase() == 'true';
      return true;
    }

    final raw = (json['items'] as List<dynamic>? ?? []);
    final items = raw
        .whereType<Map>()
        .map((e) => AiFaceItem.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.faceId > 0)
        .toList();

    final pagination =
        (json['pagination'] as Map?)?.cast<String, dynamic>() ?? {};
    final total = (pagination['total'] as num?)?.toInt() ?? 0;
    final page = (pagination['page'] as num?)?.toInt() ?? 1;
    final pageSize = (pagination['pageSize'] as num?)?.toInt() ?? 50;

    return AiFaceListResult(
      items: items,
      total: total,
      page: page,
      pageSize: pageSize,
      faceEnable: parseEnable(json['faceEnable'] ?? json['face_enable']),
    );
  }
}
