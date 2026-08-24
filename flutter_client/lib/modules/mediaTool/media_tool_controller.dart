import 'package:get/get.dart';

class MediaToolController extends GetxController {
  final RxString currentPageKey = 'image.compress'.obs;
  final RxDouble leftWidth = 180.0.obs;
  final RxBool sidebarCollapsed = false.obs;

  final RxBool isImageExpanded = true.obs;
  final RxBool isVideoExpanded = true.obs;
  final RxBool isAudioExpanded = true.obs;
  final RxBool isOtherExpanded = true.obs;

  void selectPage(String key) {
    currentPageKey.value = key;
  }
}
