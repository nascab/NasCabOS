import 'package:get/get.dart';
import 'package:flutter/material.dart';

class ToastUtil {
  static void show(String message, {String title = ''}) {
    Get.closeAllSnackbars();
    Get.snackbar(
      title.isNotEmpty ? title.tr : 'tip'.tr,
      message,
      colorText: Colors.white,
    );
  }
}
