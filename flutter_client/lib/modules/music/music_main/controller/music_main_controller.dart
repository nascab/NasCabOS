import 'package:get/get.dart';
import '../../sub_list/controller/music_sub_list_controller.dart';
import '../../list/service/music_list_api_service.dart';

class MusicMainController extends GetxController {
  final RxString currentPageKey = 'library.songs'.obs;
  final RxDouble leftWidth = 160.0.obs;
  final RxBool sidebarCollapsed = false.obs;
  final RxBool hidePlayerBar = false.obs;
  final RxBool showFullPlayer = false.obs;

  final RxBool isLibraryExpanded = true.obs;
  final RxBool isSettingsExpanded = true.obs;
  final RxBool isPlaylistsExpanded = true.obs;

  final RxInt songCount = 0.obs;

  final MusicListApiService _api = MusicListApiService.instance;

  @override
  void onInit() {
    super.onInit();
    fetchLibraryCounts();
  }

  Future<void> fetchLibraryCounts() async {
    final res = await _api.getLibraryCounts();
    final data = res.data;
    if (res.success && data != null) {
      songCount.value = data.songs;
    }
  }

  void selectPage(String key) {
    if (Get.isRegistered<MusicSubListOverlayController>()) {
      final overlayCtrl = Get.find<MusicSubListOverlayController>();
      overlayCtrl.close();
    }
    hidePlayerBar.value = false;
    showFullPlayer.value = false;
    currentPageKey.value = key;
  }

  void openFullPlayer() {
    showFullPlayer.value = true;
  }

  void closeFullPlayer() {
    showFullPlayer.value = false;
  }
}
