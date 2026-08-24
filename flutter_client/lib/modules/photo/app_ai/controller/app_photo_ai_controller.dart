import 'package:get/get.dart';
import '../../../../utils/toast_util.dart';
import '../models/app_photo_ai_models.dart';
import '../service/app_photo_ai_api_service.dart';

class AppPhotoAiController extends GetxController {
  final AppPhotoAiApiService _api = AppPhotoAiApiService();

  final RxBool isLoading = false.obs;
  final Rxn<AppPhotoAiOverviewResult> overview =
      Rxn<AppPhotoAiOverviewResult>();

  bool get faceEnabled => overview.value?.faces.faceEnable ?? true;
  bool get sceneEnabled => overview.value?.scenes.placeEnable ?? true;
  bool get similarEnabled => overview.value?.similarEnable ?? true;

  @override
  void onInit() {
    super.onInit();
    refreshOverview(showToastOnError: false);
  }

  Future<void> refreshOverview({bool showToastOnError = true}) async {
    if (isLoading.value) return;
    isLoading.value = true;
    try {
      final res = await _api.fetchOverview(limit: 20);
      if (!res.success || res.data == null) {
        if (showToastOnError) {
          ToastUtil.show(res.message ?? 'operation_failed'.tr);
        }
        return;
      }
      overview.value = res.data!;
    } finally {
      isLoading.value = false;
      update();
    }
  }
}
