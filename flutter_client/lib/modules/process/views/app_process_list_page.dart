import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../base/views/app_base_page.dart';
import 'process_list_view.dart';

/// App 端「进程」全屏页
class AppProcessListPage extends StatelessWidget {
  const AppProcessListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBasePage(
      title: 'app_process'.tr,
      body: const ProcessListView(),
    );
  }
}
