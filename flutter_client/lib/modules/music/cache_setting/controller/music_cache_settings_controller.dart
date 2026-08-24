import 'package:get/get.dart';

import '../../play_service/controller/music_play_service_controller.dart';

class MusicCacheSettingsController extends GetxController {
  final RxBool loading = false.obs;
  final RxBool clearing = false.obs;

  final RxInt cachedCount = 0.obs;
  final RxInt cachedBytes = 0.obs;

  MusicPlayServiceController get _playCtrl =>
      MusicPlayServiceController.instance;

  RxBool get enabled => _playCtrl.audioCacheEnabled;

  RxInt get maxItems => _playCtrl.audioCacheMaxItems;

  @override
  void onInit() {
    super.onInit();
    refreshStats(showLoading: true);
  }

  Future<void> toggleEnabled(bool v) async {
    await _playCtrl.setAudioCacheEnabled(v);
    await refreshStats(showLoading: false);
  }

  Future<void> setMaxItems(int v) async {
    await _playCtrl.setAudioCacheMaxItems(v);
    await refreshStats(showLoading: false);
  }

  Future<void> refreshStats({bool showLoading = false}) async {
    if (loading.value) return;
    if (showLoading) loading.value = true;
    try {
      final stats = await _playCtrl.getAudioCacheStats();
      cachedCount.value = stats.count;
      cachedBytes.value = stats.totalBytes;
    } finally {
      loading.value = false;
    }
  }

  Future<void> clearCache() async {
    if (clearing.value) return;
    clearing.value = true;
    try {
      await _playCtrl.clearAudioCache();
      await refreshStats(showLoading: false);
    } finally {
      clearing.value = false;
    }
  }
}
