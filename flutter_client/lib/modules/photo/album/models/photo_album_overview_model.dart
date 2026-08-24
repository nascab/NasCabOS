import '../../collection/models/photo_collection_model.dart';
import '../../smart_album/models/photo_smart_album_model.dart';
import 'photo_album_model.dart';

class PhotoAlbumOverviewBlock<T> {
  final List<T> items;
  final int total;

  PhotoAlbumOverviewBlock({required this.items, required this.total});
}

class PhotoAlbumOverviewResult {
  final PhotoAlbumOverviewBlock<PhotoAlbumItem> albums;
  final PhotoAlbumOverviewBlock<PhotoCollectionItem> collections;
  final PhotoAlbumOverviewBlock<PhotoSmartAlbumItem> smartAlbums;

  PhotoAlbumOverviewResult({
    required this.albums,
    required this.collections,
    required this.smartAlbums,
  });

  factory PhotoAlbumOverviewResult.fromJson(Map<String, dynamic> json) {
    final albumsJson = (json['albums'] as Map?)?.cast<String, dynamic>() ?? {};
    final collectionsJson =
        (json['collections'] as Map?)?.cast<String, dynamic>() ?? {};
    final smartAlbumsJson =
        (json['smart_albums'] as Map?)?.cast<String, dynamic>() ?? {};

    List<T> parseItems<T>(
      Map<String, dynamic> block,
      T Function(Map<String, dynamic>) fromJson,
    ) {
      final raw = (block['items'] as List<dynamic>? ?? []);
      return raw
          .whereType<Map>()
          .map((e) => fromJson(e.cast<String, dynamic>()))
          .toList(growable: false);
    }

    int parseTotal(Map<String, dynamic> block) {
      final v = block['total'];
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    return PhotoAlbumOverviewResult(
      albums: PhotoAlbumOverviewBlock<PhotoAlbumItem>(
        items: parseItems<PhotoAlbumItem>(
          albumsJson,
          PhotoAlbumItem.fromJson,
        ).where((e) => e.id > 0).toList(growable: false),
        total: parseTotal(albumsJson),
      ),
      collections: PhotoAlbumOverviewBlock<PhotoCollectionItem>(
        items: parseItems<PhotoCollectionItem>(
          collectionsJson,
          PhotoCollectionItem.fromJson,
        ).where((e) => e.id > 0).toList(growable: false),
        total: parseTotal(collectionsJson),
      ),
      smartAlbums: PhotoAlbumOverviewBlock<PhotoSmartAlbumItem>(
        items: parseItems<PhotoSmartAlbumItem>(
          smartAlbumsJson,
          PhotoSmartAlbumItem.fromJson,
        ).where((e) => e.id > 0).toList(growable: false),
        total: parseTotal(smartAlbumsJson),
      ),
    );
  }
}
