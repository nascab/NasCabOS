import 'package:get/get.dart';

class FileClipboardController extends GetxService {
  static FileClipboardController get instance =>
      Get.find<FileClipboardController>();

  final RxList<String> items = <String>[].obs;
  final RxString action = ''.obs;

  static FileClipboardController ensure() {
    if (Get.isRegistered<FileClipboardController>()) {
      return Get.find<FileClipboardController>();
    }
    return Get.put(FileClipboardController(), permanent: true);
  }
}
