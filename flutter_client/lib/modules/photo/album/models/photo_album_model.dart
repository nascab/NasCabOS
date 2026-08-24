class PhotoAlbumPreviewItem {
  final String fullpath;

  PhotoAlbumPreviewItem({required this.fullpath});

  factory PhotoAlbumPreviewItem.fromJson(Map<String, dynamic> json) {
    return PhotoAlbumPreviewItem(fullpath: json['fullpath']?.toString() ?? '');
  }
}

class PhotoAlbumItem {
  final int id;
  final int ownerId;
  final String name;
  final bool isPublic;
  final bool isOwner;
  final List<PhotoAlbumPreviewItem> previews;
  /// 非自己创建的相册时，接口返回的创建人用户名（用于展示「创建人：xxx」）
  final String? ownerUsername;

  PhotoAlbumItem({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.isPublic,
    required this.isOwner,
    required this.previews,
    this.ownerUsername,
  });

  factory PhotoAlbumItem.fromJson(Map<String, dynamic> json) {
    final previewsRaw = (json['previews'] as List<dynamic>? ?? []);
    final previews = previewsRaw
        .whereType<Map>()
        .map((e) => PhotoAlbumPreviewItem.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.fullpath.isNotEmpty)
        .toList();

    return PhotoAlbumItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      ownerId: (json['owner_id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      isPublic:
          (json['is_public'] as num?)?.toInt() == 1 ||
          json['is_public'] == true,
      isOwner: json['is_owner'] == true,
      previews: previews,
      ownerUsername: json['owner_username']?.toString(),
    );
  }
}

class PhotoAlbumShareItem {
  final int uid;
  final String? username;
  final bool canAdd;
  final bool canDelete;

  PhotoAlbumShareItem({
    required this.uid,
    required this.username,
    required this.canAdd,
    required this.canDelete,
  });

  factory PhotoAlbumShareItem.fromJson(Map<String, dynamic> json) {
    return PhotoAlbumShareItem(
      uid: (json['uid'] as num?)?.toInt() ?? 0,
      username: json['username']?.toString(),
      canAdd:
          (json['can_add'] as num?)?.toInt() != 0 || json['can_add'] == true,
      canDelete:
          (json['can_delete'] as num?)?.toInt() != 0 ||
          json['can_delete'] == true,
    );
  }
}

class PhotoAlbumDetail {
  final int id;
  final int ownerId;
  final String name;
  final bool isPublic;
  final List<PhotoAlbumShareItem> shares;

  PhotoAlbumDetail({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.isPublic,
    required this.shares,
  });

  factory PhotoAlbumDetail.fromJson(Map<String, dynamic> json) {
    final sharesRaw = (json['shares'] as List<dynamic>? ?? []);
    final shares = sharesRaw
        .whereType<Map>()
        .map((e) => PhotoAlbumShareItem.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.uid > 0)
        .toList();

    return PhotoAlbumDetail(
      id: (json['id'] as num?)?.toInt() ?? 0,
      ownerId: (json['owner_id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      isPublic:
          (json['is_public'] as num?)?.toInt() == 1 ||
          json['is_public'] == true,
      shares: shares,
    );
  }
}

class PhotoAlbumListResult {
  final List<PhotoAlbumItem> items;
  final int total;
  final int page;
  final int pageSize;

  PhotoAlbumListResult({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory PhotoAlbumListResult.fromJson(Map<String, dynamic> json) {
    final raw = (json['items'] as List<dynamic>? ?? []);
    final items = raw
        .whereType<Map>()
        .map((e) => PhotoAlbumItem.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.id > 0)
        .toList();

    final pagination =
        (json['pagination'] as Map?)?.cast<String, dynamic>() ?? {};
    final total = (pagination['total'] as num?)?.toInt() ?? 0;
    final page = (pagination['page'] as num?)?.toInt() ?? 1;
    final pageSize = (pagination['pageSize'] as num?)?.toInt() ?? 20;

    return PhotoAlbumListResult(
      items: items,
      total: total,
      page: page,
      pageSize: pageSize,
    );
  }
}
