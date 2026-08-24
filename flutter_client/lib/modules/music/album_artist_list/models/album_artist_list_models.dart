import '../../list/models/music_list_models.dart';

class AlbumArtistGroupItem {
  final String keyType;
  final String name;
  final String firstFilePath;
  final int indexCount;

  const AlbumArtistGroupItem({
    required this.keyType,
    required this.name,
    required this.firstFilePath,
    required this.indexCount,
  });

  bool get isAlbum => keyType.trim().toLowerCase() == 'album';
  bool get isArtist => keyType.trim().toLowerCase() == 'artist';

  factory AlbumArtistGroupItem.fromJson(Map<String, dynamic> json) {
    return AlbumArtistGroupItem(
      keyType: (json['key_type'] ?? json['keyType'])?.toString() ?? '',
      name: (json['name']?.toString() ?? '').trim(),
      firstFilePath:
          (json['first_file_path'] ?? json['firstFilePath'])?.toString() ?? '',
      indexCount: (json['index_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class AlbumArtistListPagedResult {
  final List<AlbumArtistGroupItem> items;
  final MusicListPagination pagination;
  final List<MusicListPathItem> validPaths;

  const AlbumArtistListPagedResult({
    required this.items,
    required this.pagination,
    required this.validPaths,
  });

  const AlbumArtistListPagedResult.empty()
    : items = const <AlbumArtistGroupItem>[],
      pagination = const MusicListPagination.empty(),
      validPaths = const <MusicListPathItem>[];

  factory AlbumArtistListPagedResult.fromJson(Map<String, dynamic> json) {
    List<AlbumArtistGroupItem> parseItems(dynamic v) {
      final list = v is List ? v : const <dynamic>[];
      return list
          .whereType<Map>()
          .map((e) => AlbumArtistGroupItem.fromJson(e.cast<String, dynamic>()))
          .where((e) => e.name.isNotEmpty)
          .toList();
    }

    List<MusicListPathItem> parseValidPaths(dynamic v) {
      final list = v is List ? v : const <dynamic>[];
      return list
          .map((e) {
            if (e is String) {
              final p = e.trim();
              return MusicListPathItem(path: p, valid: true);
            }
            if (e is Map) {
              return MusicListPathItem.fromJson(e.cast<String, dynamic>());
            }
            return const MusicListPathItem(path: '', valid: false);
          })
          .where((e) => e.path.isNotEmpty)
          .toList();
    }

    final paginationRaw = json['pagination'];
    final paginationMap = paginationRaw is Map
        ? paginationRaw.cast<String, dynamic>()
        : <String, dynamic>{};
    final validPathsRaw = json['validPaths'] ?? json['valid_paths'];
    return AlbumArtistListPagedResult(
      items: parseItems(json['items']),
      pagination: MusicListPagination.fromJson(paginationMap),
      validPaths: parseValidPaths(validPathsRaw),
    );
  }
}
