import 'package:get/get.dart';
import '../../../../utils/dialog_util.dart';
import '../../../folder_view/folder_view_module_type.dart';
import '../service/photo_home_api_service.dart';

class PhotoHomeController extends GetxController {
  final RxString currentPageKey = 'all.timeline'.obs;
  final RxDouble leftWidth = 160.0.obs;
  final RxBool sidebarCollapsed = false.obs;

  final RxBool isAllExpanded = true.obs;
  final RxBool isAlbumExpanded = true.obs;
  final RxBool isAiExpanded = true.obs;
  final RxBool isSettingsExpanded = true.obs;
  // 照片总数
  final RxInt totalCount = 0.obs;

  final PhotoHomeApiService _apiService = PhotoHomeApiService.instance;

  @override
  void onInit() {
    super.onInit();
    fetchTotalCount();
  }

  Future<void> fetchTotalCount() async {
    final res = await _apiService.getTotalCount();
    if (res.success && res.data != null) {
      totalCount.value = res.data!;
    }
  }

  void selectPage(String key) {
    if (key == 'ai.gps_supplement' &&
        !FolderViewModuleType.photo.isServerVersionAtLeast(5)) {
      DialogUtil.showInfoDialog(
        title: 'tip'.tr,
        content: 'server_version_too_low'.tr,
      );
      return;
    }
    currentPageKey.value = key;
  }
}
