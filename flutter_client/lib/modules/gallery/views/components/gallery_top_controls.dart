import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:NasCabOS/utils/device_utils.dart';
import '../../../base/components/custom_icon_button.dart';
import '../../controllers/custom_gallery_controller.dart';

void _showShortcutsHelp(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('gallery_shortcuts_title'.tr),
      content: SingleChildScrollView(
        child: Text(
          'gallery_shortcuts_content'.tr,
          style: const TextStyle(height: 1.5),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('ok'.tr),
        ),
      ],
    ),
  );
}

/// 画廊顶部控制按钮组件
class GalleryTopControls extends StatelessWidget {
  const GalleryTopControls({super.key, this.onInfoPressed});

  /// 点击「查看照片信息」时的回调；若提供则替代默认的 toggleInfoPanel（用于手机端弹出底部 sheet）
  final VoidCallback? onInfoPressed;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<CustomGalleryController>();
    // 手机端下移按钮行，避免与刘海/状态栏重叠导致只有 icon 底部一小块能响应
    final isPhone = DeviceUtils.isPhone(context);
    final topPadding = isPhone
        ? MediaQuery.of(context).padding.top + 20.0
        : 30.0;
    // 手机端缩小按钮间距以节省空间（判断逻辑与 DeviceUtils.isMobile 一致：见 device_utils.dart isPhone/isMobile）
    final buttonSpacing = isPhone ? 4.0 : 10.0;
    final iconSize = 24.0;
    final buttonSize = isPhone ? 40.0 : 30.0;

    return Positioned(
      top: 0,
      right: 0,
      left: 0,
      height: 100,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.7),
              Colors.black.withValues(alpha: 0.3),
              Colors.black.withValues(alpha: 0.0),
            ],
          ),
        ),
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: EdgeInsets.only(top: topPadding, right: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Obx(() {
                  if (!controller.showInfoButton.value) {
                    return const SizedBox.shrink();
                  }
                  return Row(
                    children: [
                      if (!isPhone) ...[
                        CustomIconButton(
                          icon: Icons.help_outline,
                          onPressed: () => _showShortcutsHelp(context),
                          iconColor: Colors.white,
                          iconSize: iconSize,
                          buttonSize: buttonSize,
                          tooltip: 'gallery_help_tooltip'.tr,
                        ),
                        SizedBox(width: buttonSpacing),
                      ],
                      CustomIconButton(
                        icon: Icons.info_outline,
                        onPressed: () => onInfoPressed != null
                            ? onInfoPressed!()
                            : controller.toggleInfoPanel(),
                        iconColor: Colors.white,
                        iconSize: iconSize,
                        buttonSize: buttonSize,
                        tooltip: 'info'.tr,
                      ),
                      SizedBox(width: buttonSpacing),
                    ],
                  );
                }),
                // 旋转左
                CustomIconButton(
                  icon: Icons.rotate_left_outlined,
                  onPressed: () {
                    final index = controller.pageController.hasClients
                        ? controller.pageController.page?.round() ?? 0
                        : 0;
                    controller.rotateLeft(index);
                  },
                  iconColor: Colors.white,
                  iconSize: iconSize,
                  buttonSize: buttonSize,
                  tooltip: 'gallery_rotate_left'.tr,
                ),
                SizedBox(width: buttonSpacing),
                // 旋转右
                CustomIconButton(
                  icon: Icons.rotate_right_outlined,
                  onPressed: () {
                    final index = controller.pageController.hasClients
                        ? controller.pageController.page?.round() ?? 0
                        : 0;
                    controller.rotateRight(index);
                  },
                  iconColor: Colors.white,
                  iconSize: iconSize,
                  buttonSize: buttonSize,
                  tooltip: 'gallery_rotate_right'.tr,
                ),
                SizedBox(width: buttonSpacing),
                // 删除
                CustomIconButton(
                  icon: Icons.delete_outlined,
                  onPressed: () => controller.deleteCurrentImage(),
                  iconColor: Colors.white,
                  iconSize: iconSize,
                  buttonSize: buttonSize,
                  tooltip: 'delete'.tr,
                ),
                SizedBox(width: buttonSpacing),
                // 下载
                CustomIconButton(
                  icon: Icons.download_rounded,
                  onPressed: () => controller.downloadCurrentImage(),
                  iconColor: Colors.white,
                  iconSize: iconSize,
                  buttonSize: buttonSize,
                  tooltip: 'download'.tr,
                ),
                SizedBox(width: buttonSpacing),
                // 自动播放/暂停 - 使用Obx监听状态变化
                Obx(
                  () => CustomIconButton(
                    icon: controller.isAutoPlaying.value
                        ? Icons.pause_circle_outlined
                        : Icons.play_circle_outline,
                    onPressed: () => controller.toggleAutoPlay(),
                    iconColor: controller.isAutoPlaying.value
                        ? Colors.blue
                        : Colors.white,
                    iconSize: iconSize,
                    buttonSize: buttonSize,
                    tooltip: controller.isAutoPlaying.value
                        ? 'gallery_pause_slideshow'.tr
                        : 'gallery_start_slideshow'.tr,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
