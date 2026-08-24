import 'package:get/get.dart';
import '../../history/controller/book_history_controller.dart';
import '../../list/service/book_list_api_service.dart';

class BookMainController extends GetxController {
  final RxString currentPageKey = 'library.book'.obs;
  final RxDouble leftWidth = 160.0.obs;
  final RxBool sidebarCollapsed = false.obs;

  final RxBool isLibraryExpanded = true.obs;
  final RxBool isBookListExpanded = true.obs;
  final RxBool isSettingsExpanded = true.obs;

  final RxInt bookCount = 0.obs;
  final RxInt comicCount = 0.obs;

  final BookListApiService _api = BookListApiService.instance;

  @override
  void onInit() {
    super.onInit();
    fetchIndexCounts();
  }

  Future<void> fetchIndexCounts() async {
    final res = await _api.getIndexCounts();
    final data = res.data;
    if (res.success && data != null) {
      bookCount.value = data.book;
      comicCount.value = data.comic;
    }
  }

  void selectPage(String key) {
    currentPageKey.value = key;
    if (key == 'library.history' &&
        Get.isRegistered<BookHistoryController>()) {
      Get.find<BookHistoryController>().refreshHistory(showLoading: true);
    }
  }
}
