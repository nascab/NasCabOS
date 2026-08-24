import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:get/get.dart';
import 'package:flutter_box_transform/flutter_box_transform.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'pc_components/pc_app_window.dart';
import '../../../core/user/current_user_controller.dart';
import '../../../core/api/api_controller.dart';
import '../../../core/routes/app_routes.dart';
import 'pc_components/pc_dock_bar.dart';
import 'pc_components/pc_desktop_icon.dart';
import 'pc_home_controller.dart';
import 'pc_components/pc_all_apps_overlay.dart';
import 'components/user_info_dialog.dart';
import '../../../utils/context_menu_util.dart';
import 'pc_components/pc_wallpaper_picker_view.dart';
import 'components/session_wallpaper_background.dart';
import '../../base/components.dart';

class PcHomePage extends GetView<PcHomeController> {
  PcHomePage({super.key});
  final PcHomeController ctrl = Get.put(PcHomeController());

  /// 本地无登录状态时显示占位页，避免空白或异常
  Widget _buildSessionExpiredPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.info_outline,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'service_nascab_session_expired'.tr,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  CurrentUserController.instance.clear();
                  ApiController.instance.clearAuthInfo();
                  AppRoutes.toLogin();
                },
                child: Text('ok'.tr),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建桌面右键菜单项：点在 app 上时含「打开」，否则不含。
  List<ContextMenuEntry> _buildDesktopContextMenuEntries(
    BuildContext context, {
    String? appName,
  }) {
    final entries = <ContextMenuEntry>[];
    if (appName != null) {
      entries.add(
        CustomContextMenuItem.create(
          label: Text('open'.tr),
          icon: const Icon(Icons.open_in_new),
          value: 'open',
          onSelected: (_) {
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
            ctrl.openApp(
              windowId: appName,
              viewBuilder: ctrl.builtinAppViewBuilder(appName),
              title: 'app_$appName'.tr,
              icon: ctrl.buildAppIcon(appName),
              showTitle: appName != 'movie' && appName != 'process',
            );
          },
        ),
      );
    }
    entries.addAll([
      CustomContextMenuItem.create(
        label: Text('my_account'.tr),
        icon: const Icon(Icons.account_box_outlined),
        value: 'my_account',
        onSelected: (_) => Get.dialog(const UserInfoDialog()),
      ),
      CustomContextMenuItem.create(
        label: Text('app_task_center'.tr),
        icon: const Icon(Icons.sync_outlined),
        value: 'task_center',
        onSelected: (_) {
          ctrl.openApp(
            windowId: 'task_center',
            viewBuilder: ctrl.builtinAppViewBuilder('task_center'),
            title: 'app_task_center'.tr,
            icon: ctrl.buildAppIcon('task_center'),
          );
        },
      ),
      CustomContextMenuItem.create(
        label: Text('message_center'.tr),
        icon: const Icon(Icons.notifications_outlined),
        value: 'message_center',
        onSelected: (_) {
          ctrl.openApp(
            windowId: 'message_center',
            viewBuilder: ctrl.builtinAppViewBuilder('message_center'),
          );
        },
      ),
      CustomContextMenuItem.create(
        label: Text('home_desktop_change_wallpaper'.tr),
        icon: const Icon(Icons.wallpaper),
        value: 'change_wallpaper',
        onSelected: (_) {
          showDialog(
            context: context,
            builder: (ctx) {
              return AlertDialog(
                contentPadding: const EdgeInsets.all(16),
                insetPadding: const EdgeInsets.all(20),
                constraints: const BoxConstraints(
                  maxWidth: 900,
                  maxHeight: 700,
                ),
                content: const PcWallpaperPickerView(),
              );
            },
          );
        },
      ),
      CustomContextMenuItem.create(
        label: Text('home_dock_show_desktop'.tr),
        icon: const Icon(Icons.computer_outlined),
        value: 'show_desktop',
        onSelected: (_) {
          final apps = List<String>.from(ctrl.openedApps);
          for (final app in apps) {
            ctrl.minimizeApp(app);
          }
        },
      ),
    ]);
    return entries;
  }

  Future<void> _showDesktopContextMenu(
    BuildContext context,
    Offset position, {
    String? appName,
  }) async {
    final entries = _buildDesktopContextMenuEntries(context, appName: appName);
    await ContextMenuUtil.showAtPosition(
      context,
      entries: entries,
      position: position,
    );
  }

  // 构建应用窗口的方法，提取为独立方法以保持组件稳定性
  Widget _buildAppWindow({required String windowId}) {
    // 使用Obx只包裹窗口的动态属性，而不是整个窗口
    return Obx(() {
      final isMaximized = ctrl.isMaximized(windowId);
      final isMinimized = ctrl.minimizedApps.contains(windowId);

      // 计算窗口位置和大小
      final pos = ctrl.getWindowPos(windowId);
      final size = ctrl.getWindowSize(windowId);
      final desktopRect = ctrl.getDeskRect();
      // 确保窗口尺寸在有效范围内
      final minSize = ctrl.windowMinSize(windowId) ?? const Size(600, 500);
      final minW = minSize.width;
      final minH = minSize.height;

      final maxW = desktopRect.width < minW ? minW : desktopRect.width;
      final maxH = desktopRect.height < minH ? minH : desktopRect.height;
      final effectiveMinW = minW.clamp(0.0, maxW);
      final effectiveMinH = minH.clamp(0.0, maxH);
      final w = size.width.clamp(effectiveMinW, maxW);
      final h = size.height.clamp(effectiveMinH, maxH);

      // 计算安全位置
      final minX = desktopRect.left;
      final minY = desktopRect.top;
      final maxX = desktopRect.right - w;
      final maxY = desktopRect.bottom - h;
      final x = maxX < minX ? minX : pos.dx.clamp(minX, maxX);
      final y = maxY < minY ? minY : pos.dy.clamp(minY, maxY);
      final safePos = Offset(x, y);
      final safeSize = Size(w, h);

      // 保存安全位置和大小 - 延迟执行，避免在构建过程中修改状态
      if (!isMaximized) {
        if (safePos != pos || safeSize != size) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (safePos != pos) {
              ctrl.setLastPosition(windowId, safePos);
            }
            if (safeSize != size) {
              ctrl.setLastSize(windowId, safeSize);
            }
          });
        }
      }

      // 计算当前矩形
      final currentRect = isMaximized
          ? Rect.fromLTWH(desktopRect.left, desktopRect.top, maxW, maxH)
          : Rect.fromLTWH(
              safePos.dx,
              safePos.dy,
              safeSize.width,
              safeSize.height,
            );

      return TransformableBox(
        key: ValueKey('box_$windowId'),
        rect: currentRect,
        clampingRect: Rect.fromLTWH(
          desktopRect.left,
          desktopRect.top,
          maxW,
          maxH,
        ),
        visibleHandles: const {},
        draggable: false,
        // 缩放相关配置
        enabledHandles: ctrl.windowCanResize(windowId)
            ? {
                HandlePosition.bottomRight,
                HandlePosition.topLeft,
                HandlePosition.bottomLeft,
                HandlePosition.topRight,
                HandlePosition.bottom,
                HandlePosition.left,
                HandlePosition.top,
              }
            : {},
        constraints: BoxConstraints(
          minWidth: effectiveMinW,
          minHeight: effectiveMinH,
          maxWidth: maxW,
          maxHeight: maxH,
        ),
        onChanged: (result, event) {
          // 如果是最大化状态，拖拽边缘改变大小时，自动退出最大化
          if (ctrl.isMaximized(windowId)) {
            ctrl.maximizeApp(windowId);
          }
          ctrl.setLastPosition(windowId, result.rect.topLeft);
          ctrl.setLastSize(windowId, result.rect.size);
          ctrl.focusWindow(windowId);
        },
        // 稳定的contentBuilder，不依赖外部变量
        contentBuilder: (context, rect, flip) {
          final viewBuilder = ctrl.windowViewBuilder(windowId);
          if (viewBuilder == null) {
            return const SizedBox.shrink();
          }
          return RepaintBoundary(
            child: SizedBox(
              width: rect.width,
              height: rect.height,
              child: AnimatedOpacity(
                opacity: isMinimized ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeInOut,
                child: IgnorePointer(
                  ignoring: isMinimized,
                  child: PcAppWindow(
                    key: Key('win_content_$windowId'),
                    windowId: windowId,
                    title: ctrl.windowTitle(windowId),
                    showTitle: ctrl.windowShowTitle(windowId),
                    viewBuilder: viewBuilder,
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!CurrentUserController.instance.isLoggedIn ||
        !ApiController.instance.state.isAuthenticated) {
      return _buildSessionExpiredPlaceholder(context);
    }
    final theme = Theme.of(context);
    final ctrl = PcHomeController.instance;
    final viewportSize = MediaQuery.of(context).size;
    final virtualWidth = viewportSize.width < (ctrl.dockOuterWidthPc + 600)
        ? (ctrl.dockOuterWidthPc + 600)
        : viewportSize.width;
    final virtualHeight = viewportSize.height < 500
        ? 500.0
        : viewportSize.height;
    final virtualSize = Size(virtualWidth, virtualHeight);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ctrl.windows.setVirtualDeskSize(virtualSize);
    });
    final enablePan =
        virtualWidth > viewportSize.width ||
        virtualHeight > viewportSize.height;
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Obx(() {
        return Stack(
          children: [
            InteractiveViewer(
              panEnabled: enablePan,
              scaleEnabled: false,
              constrained: false,
              minScale: 1,
              maxScale: 1,
              child: SizedBox(
                width: virtualWidth,
                height: virtualHeight,
                child: Stack(
                  children: [
                    // 墙纸 背景：空白处右键显示桌面菜单（不含「打开」）
                    Positioned.fill(
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: (event) {
                          if (event.kind != PointerDeviceKind.mouse ||
                              event.buttons != kSecondaryMouseButton) {
                            return;
                          }
                          _showDesktopContextMenu(
                            context,
                            event.position,
                            appName: null,
                          );
                        },
                        child: SessionWallpaperBackground(
                          fit: BoxFit.cover,
                          placeholder: Center(
                            child: Text('home_no_wallpaper'.tr),
                          ),
                        ),
                      ),
                    ),
                    // 主区域
                    Positioned.fill(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 状态栏
                          // PcHomeStatusBar(height: ctrl.statusBarHeightPc),
                          // 桌面图标
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return GetBuilder<ApiController>(
                                  builder: (api) {
                                    return Obx(() {
                                  final apps = ctrl.showApps; //所有可显示app
                                  final availableHeight =
                                      constraints.maxHeight; //计算桌面区域可用高度
                                  const columnTopPadding = 10.0;
                                  const rowGap = 10.0;
                                  final perCol =
                                      (availableHeight -
                                          columnTopPadding +
                                          rowGap) ~/
                                      (PcDesktopIcon.tileHeight + rowGap);
                                  final perColumn = perCol <= 0
                                      ? 1
                                      : perCol; //保证至少显示1个
                                  final columns =
                                      <List<String>>[]; // 二维数组，每个子数组表示一列app
                                  for (int i = 0; i < apps.length; i++) {
                                    final colIndex = i ~/ perColumn;
                                    if (columns.length <= colIndex) {
                                      columns.add([]);
                                    }
                                    columns[colIndex].add(apps[i]);
                                  }
                                  return RepaintBoundary(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: SizedBox(
                                        width: constraints.maxWidth,
                                        height: constraints.maxHeight,
                                        child: Stack(
                                          children: [
                                            // 桌面空白处右键显示菜单（不含「打开」）
                                            Positioned.fill(
                                              child: Listener(
                                                behavior:
                                                    HitTestBehavior.translucent,
                                                onPointerDown: (event) {
                                                  if (event.kind !=
                                                          PointerDeviceKind
                                                              .mouse ||
                                                      event.buttons !=
                                                          kSecondaryMouseButton) {
                                                    return;
                                                  }
                                                  _showDesktopContextMenu(
                                                    context,
                                                    event.position,
                                                    appName: null,
                                                  );
                                                },
                                                child: const SizedBox.expand(),
                                              ),
                                            ),
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const SizedBox(
                                                  width: 89,
                                                ), // 12(dock left margin) + 61(dock width) + 16(spacing)
                                                for (
                                                  int c = 0;
                                                  c < columns.length;
                                                  c++
                                                )
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                      right: 20,
                                                      top: columnTopPadding,
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        for (
                                                          int r = 0;
                                                          r <
                                                              columns[c]
                                                                  .length;
                                                          r++
                                                        ) ...[
                                                          PcDesktopIcon(
                                                            appName: columns[c]
                                                                [r],
                                                            index: c *
                                                                    perColumn +
                                                                r,
                                                            onDesktopRightTap:
                                                                (ctx, position,
                                                                    name) {
                                                              _showDesktopContextMenu(
                                                                ctx,
                                                                position,
                                                                appName: name,
                                                              );
                                                            },
                                                          ),
                                                          if (r !=
                                                              columns[c]
                                                                      .length -
                                                                  1)
                                                            const SizedBox(
                                                              height: rowGap,
                                                            ),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                    // app窗口绘制
                    Positioned.fill(
                      child: Stack(
                        children: [
                          // 使用Obx只包裹需要响应变化的部分，而不是整个窗口列表
                          Obx(() {
                            final opened = ctrl.openedApps;

                            // 使用Stack来显示所有窗口，依靠z-index顺序
                            return Stack(
                              children: [
                                for (final windowId in opened)
                                  KeyedSubtree(
                                    key: ValueKey('window_$windowId'),
                                    child: _buildAppWindow(windowId: windowId),
                                  ),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            /// 左侧dock栏
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: 2, top: 6, bottom: 6),
                  child: SizedBox(
                    width: ctrl.dockOuterWidthPc,
                    child: const PcDockBar(),
                  ),
                ),
              ),
            ),
            Obx(() {
              if (!ctrl.showP2pConnectingHint.value) {
                return const SizedBox.shrink();
              }
              return Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'home_server_connecting'.tr,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
            if (ctrl.showAllAppsOverlay) const PcAllAppsOverlay(),
          ],
        );
      }),
    );
  }
}
