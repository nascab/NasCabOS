import 'package:get/get.dart';
import '../models/photo_album_model.dart';
import '../service/photo_album_api_service.dart';
import '../../collection/models/photo_collection_model.dart';
import '../../smart_album/models/photo_smart_album_model.dart';

class PhotoAlbumOverviewController extends GetxController {
  final PhotoAlbumApiService _api = PhotoAlbumApiService();

  final RxBool isLoading = false.obs;
  final RxList<PhotoAlbumItem> albums = <PhotoAlbumItem>[].obs;
  final RxList<PhotoSmartAlbumItem> smartAlbums = <PhotoSmartAlbumItem>[].obs;
  final RxList<PhotoCollectionItem> collections = <PhotoCollectionItem>[].obs;

  final RxInt albumTotal = 0.obs;
  final RxInt smartAlbumTotal = 0.obs;
  final RxInt collectionTotal = 0.obs;

  final int limit;
  PhotoAlbumOverviewController({this.limit = 6});

  @override
  void onInit() {
    super.onInit();
    refreshOverview();
  }

  Future<void> refreshOverview() async {
    if (isLoading.value) return;
    isLoading.value = true;
    try {
      final res = await _api.getAlbumOverview(limit: limit);
      if (!res.success || res.data == null) return;
      final data = res.data!;

      albums.assignAll(data.albums.items);
      smartAlbums.assignAll(data.smartAlbums.items);
      collections.assignAll(data.collections.items);

      albumTotal.value = data.albums.total;
      smartAlbumTotal.value = data.smartAlbums.total;
      collectionTotal.value = data.collections.total;
    } finally {
      isLoading.value = false;
    }
  }
}
