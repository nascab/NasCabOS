import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../../modules/base/components/custom_no_data.dart';
import '../controller/photo_trash_controller.dart';
import './parts/photo_trash_control_bar.dart';
import './parts/photo_trash_bottom_bar.dart';
import './parts/photo_trash_list.dart';

// 回收站页面主组件
class PhotoTrashView extends StatelessWidget {
  const PhotoTrashView({super.key});

  @override
  Widget build(BuildContext context) {
    final customColors = Theme.of(context).extension<CustomColors>();
    return GetBuilder<PhotoTrashController>(
      init: PhotoTrashController(),
      builder: (controller) {
        return Scaffold(
          backgroundColor: customColors?.mainContentBgColor,
          body: Column(
            children: [
              PhotoTrashControlBar(controller: controller),
              Expanded(
                child: Obx(() {
                  if (controller.isLoading.value &&
                      controller.photoItems.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (controller.photoItems.isEmpty) {
                    return CustomNoData(text: 'recycle_bin_empty'.tr);
                  }

                  return RefreshIndicator(
                    onRefresh: () => controller.refreshList(),
                    child: PhotoTrashList(controller: controller),
                  );
                }),
              ),
              // 只有当有数据时才显示底部操作栏
              Obx(() {
                if (controller.photoItems.isEmpty) {
                  return const SizedBox.shrink();
                }
                return PhotoTrashBottomBar(controller: controller);
              }),
            ],
          ),
        );
      },
    );
  }
}
