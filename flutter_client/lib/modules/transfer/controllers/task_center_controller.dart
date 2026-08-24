import 'package:get/get.dart';

class TaskCenterController extends GetxController {
  static TaskCenterController get to => Get.find();

  final RxInt selectedIndex = 0.obs;
  final RxString currentKey = 'task.upload'.obs;

  bool _syncing = false;

  static const _indexToKey = <int, String>{
    0: 'task.upload',
    1: 'task.download',
    2: 'task.file_log',
  };
  static const _keyToIndex = <String, int>{
    'task.upload': 0,
    'task.download': 1,
    'task.file_log': 2,
  };

  @override
  void onInit() {
    super.onInit();
    currentKey.value = _indexToKey[selectedIndex.value] ?? 'task.upload';

    ever(selectedIndex, (idx) {
      if (_syncing) return;
      final nextKey = _indexToKey[idx] ?? 'task.upload';
      if (currentKey.value == nextKey) return;
      _syncing = true;
      currentKey.value = nextKey;
      _syncing = false;
    });

    ever(currentKey, (key) {
      if (_syncing) return;
      final nextIndex = _keyToIndex[key] ?? 0;
      if (selectedIndex.value == nextIndex) return;
      _syncing = true;
      selectedIndex.value = nextIndex;
      _syncing = false;
    });
  }

  void jumpToPage(int index) {
    selectedIndex.value = index;
  }

  void selectKey(String key) {
    currentKey.value = key;
  }
}
