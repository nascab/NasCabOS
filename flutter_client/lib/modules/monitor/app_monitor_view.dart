import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../base/views/app_base_page.dart';
import 'monitor_view.dart';

/// App端设备监控页面
/// App Monitor View
class AppMonitorView extends StatelessWidget {
  const AppMonitorView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBasePage(
      title: 'monitor_device_monitor'.tr,
      body: const MonitorView(),
    );
  }
}
