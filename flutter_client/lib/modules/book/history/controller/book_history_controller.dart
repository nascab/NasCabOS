import 'package:get/get.dart';
import 'package:NasCabOS/modules/book/list/service/book_list_api_service.dart';
import 'package:NasCabOS/utils/dialog_util.dart';
import 'package:NasCabOS/utils/toast_util.dart';

class BookHistoryController extends GetxController {
  final RxList<BookListItem> items = <BookListItem>[].obs;
  final RxBool loading = false.obs;
  final RxBool firstLoaded = false.obs;

  @override
  void onInit() {
    super.onInit();
    refreshHistory(showLoading: true);
  }

  Future<void> refreshHistory({required bool showLoading}) async {
    if (loading.value) return;
    loading.value = true;
    try {
      final res = await BookListApiService.instance.listHistory(
        showLoading: showLoading,
      );
      items.assignAll(res.items);
      firstLoaded.value = true;
    } finally {
      loading.value = false;
    }
  }

  Future<void> clearHistory() async {
    final confirmed = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: 'book_history_clear_confirm'.tr,
      confirmText: 'ok'.tr,
      cancelText: 'cancel'.tr,
      barrierDismissible: true,
    );
    if (confirmed != true) return;

    loading.value = true;
    try {
      await BookListApiService.instance.clearHistory(showLoading: true);
      items.clear();
      ToastUtil.show('operation_success'.tr);
    } finally {
      loading.value = false;
    }
  }
}
