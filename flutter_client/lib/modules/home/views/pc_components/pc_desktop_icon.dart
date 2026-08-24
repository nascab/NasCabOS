import 'package:flutter/material.dart';
import '../pc_home_controller.dart';
import 'package:get/get.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../../../music/play_service/controller/music_play_service_controller.dart';

/// 桌面图标右键回调：context, 全局位置, 当前 app 名称
typedef DesktopRightTapCallback = void Function(
  BuildContext context,
  Offset position,
  String appName,
);

class PcDesktopIcon extends StatelessWidget {
  static const double tileWidth = 90;
  static const double iconSize = 58;
  static const double verticalPadding = 12;
  static const double labelGap = 10;
  static const double labelHeight = 25;
  static const double borderRadius = 16;
  static const double tileHeight =
      verticalPadding * 2 + iconSize + labelGap + labelHeight;

  final String appName;
  final int index;
  final DesktopRightTapCallback? onDesktopRightTap;

  const PcDesktopIcon({
    super.key,
    required this.appName,
    required this.index,
    this.onDesktopRightTap,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = PcHomeController.instance;
    return LongPressDraggable<int>(
      //长按拖动组件
      data: index,
      //feedback属性是在拖动过程中显示的widget。它代表了被拖动的对象在屏幕上移动时的视觉反馈。
      feedback: _pcIconWidget(context, appName, dragging: true),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _pcIconWidget(context, appName),
      ),
      onDragEnd: (d) {},

      ///child属性指的是当用户长按时，实际的widget。这是用户在拖动开始前看到的元素。
      child: DragTarget<int>(
        onWillAcceptWithDetails: (from) => from.data != index,
        onAcceptWithDetails: (from) {
          ctrl.reorderIcon(from.data, index);
        },
        builder: (context, candidate, rejected) {
          return GestureDetector(
            onSecondaryTapDown: onDesktopRightTap == null
                ? null
                : (details) {
                    onDesktopRightTap!.call(
                      context,
                      details.globalPosition,
                      appName,
                    );
                  },
            child: InkWell(
              key: Key(appName),
              borderRadius: BorderRadius.circular(borderRadius),
              //桌面app点击事件
              onTap: () {
              final desktopRect = ctrl.getDeskRect();
              if (appName == 'monitor') {
                const size = Size(320, 620);
                ctrl.openApp(
                  windowId: appName,
                  viewBuilder: ctrl.builtinAppViewBuilder(appName),
                  title: "app_$appName".tr,
                  icon: ctrl.buildAppIcon(appName),
                  showTitle: false,
                  resizable: false,
                  maximizable: false,
                  minimizable: false,
                  minSize: size,
                  initialSize: size,
                  initialPosition: Offset(
                    desktopRect.right - size.width,
                    desktopRect.top,
                  ),
                );
                return;
              }
              if (appName == 'process') {
                ctrl.openApp(
                  windowId: appName,
                  viewBuilder: ctrl.builtinAppViewBuilder(appName),
                  title: 'app_process'.tr,
                  icon: ctrl.buildAppIcon(appName),
                  showTitle: false,
                );
                return;
              }
              if (appName == 'task_center') {
                final w = ctrl.windows.defaultWindowWidth;
                final h = ctrl.windows.defaultWindowHeight;
                ctrl.openApp(
                  windowId: appName,
                  viewBuilder: ctrl.builtinAppViewBuilder(appName),
                  title: 'app_$appName'.tr,
                  icon: ctrl.buildAppIcon(appName),
                  initialSize: Size(w, h),
                  initialPosition: Offset(
                    desktopRect.right - w,
                    desktopRect.top,
                  ),
                );
                return;
              }
              //其他app打开
              ctrl.openApp(
                windowId: appName,
                viewBuilder: ctrl.builtinAppViewBuilder(appName),
                title: 'app_$appName'.tr,
                icon: ctrl.buildAppIcon(appName),
                showTitle: appName != 'movie' && appName != 'process',
              );
            },
              child: _pcIconWidget(
                context,
                appName,
                highlight: candidate.isNotEmpty,
              ),
            ),
          );
        },
      ),
    );
  }

  /// 桌面图标 组件
  Widget _pcIconWidget(
    BuildContext context,
    String appName, {
    bool dragging = false,
    bool highlight = false,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: tileWidth,
      height: tileHeight,
      padding: const EdgeInsets.symmetric(vertical: verticalPadding),
      decoration: BoxDecoration(
        color: highlight
            ? theme.colorScheme.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: iconSize,
              height: iconSize,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/app_icons/$appName.webp',
                    width: iconSize,
                    height: iconSize,
                    filterQuality: FilterQuality.high,
                    isAntiAlias: true,
                    // 按物理像素解码，避免 Web 上逻辑尺寸×DPR 与纹理缩放不对齐产生锯齿
                    cacheWidth: (iconSize *
                            MediaQuery.devicePixelRatioOf(context))
                        .round()
                        .clamp(1, 4096),
                    cacheHeight: (iconSize *
                            MediaQuery.devicePixelRatioOf(context))
                        .round()
                        .clamp(1, 4096),
                    errorBuilder: (c, e, s) {
                      return Icon(
                        Icons.apps,
                        size: iconSize,
                        color: theme.colorScheme.onSurface,
                      );
                    },
                  ),
                  if (appName == 'music')
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Center(
                          child: Obx(() {
                            final playCtrl =
                                MusicPlayServiceController.instance;
                            final show =
                                playCtrl.isReady.value &&
                                playCtrl.isPlaying.value &&
                                playCtrl.playlist.isNotEmpty;
                            if (!show) return const SizedBox.shrink();
                            return SpinKitWave(
                              color: Colors.white.withValues(alpha: 0.9),
                              size: 22,
                              itemCount: 6,
                            );
                          }),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: labelGap),
          // app名字 文本
          SizedBox(
            height: labelHeight,
            child: Center(
              child: Text(
                'app_$appName'.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.85),
                      offset: const Offset(0, 1),
                      blurRadius: 6,
                    ),
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.55),
                      offset: const Offset(0, 0),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
