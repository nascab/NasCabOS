import 'package:flutter/material.dart';
import '../app_home_controller.dart';
import 'app_server_info_card.dart';

class AppHomeTopArea extends StatelessWidget {
  final AppHomeController controller;

  const AppHomeTopArea({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    // 高度不写死，随卡片内容自适应，避免低分辨率/窄屏或大字体下卡片底部被裁切
    return Padding(
      padding: EdgeInsets.fromLTRB(10, topPadding, 10, 10),
      child: SizedBox(
        width: double.infinity,
        child: AppServerInfoCard(controller: controller),
      ),
    );
  }
}
