import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../home/views/pc_home_controller.dart';
import '../../base/components/custom_expandable_search_bar.dart';
import '../../base/components/custom_split_view.dart';
import 'pc_components/pc_file_breadcrumb.dart';
import 'pc_components/pc_file_left_tree.dart';
import 'pc_components/pc_file_right_area.dart';
import '../controllers/pc_file_explorer_controller.dart';
import '../controllers/file_shortcut_service.dart';
import '../../base/components/custom_divider.dart';

/// 文件浏览器视图 由于每个文件浏览器视图都需要独立的控制器，所以需要为每个视图生成唯一的tag
/// 文件浏览器组件对打开多个文件浏览器视图时，每个视图都需要独立的控制器，所以需要为每个视图生成唯一的tag
class PcFileBrowser extends StatefulWidget {
  final String? initialPath;
  final bool listenHomeNavigateSignal;
  final String? windowId;
  const PcFileBrowser({
    super.key,
    this.initialPath,
    this.listenHomeNavigateSignal = true,
    this.windowId,
  });

  @override
  State<PcFileBrowser> createState() => _PcFileBrowserState();
}

class _PcFileBrowserState extends State<PcFileBrowser> {
  late final PcFileExplorerController controller;
  late final String _controllerTag;
  String? _windowId;
  Worker? _navigateWorker;
  late final TextEditingController _searchCtrl;
  Worker? _searchSyncWorker;
  // 显式注册控制器，确保在任何组件使用前就已注册
  static const double _topBarHeight = 40;
  static const double _searchBarHeight = 30;

  @override
  void initState() {
    super.initState();
    // 生成唯一tag，固定前缀+随机后缀
    _controllerTag =
        'file_explorer_controller_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';
    // 有初始路径时不自动加载根目录，避免与 postFrameCallback 中的 navigateTo 竞态导致闪根目录或两次请求。
    // PC 端通过 openFolderAt 打开时，path 在 PcHomeController.folderNavigatePath 中，widget.initialPath 为空，需一并考虑
    final pathFromWidget = widget.initialPath?.trim() ?? '';
    final pathFromHome = widget.listenHomeNavigateSignal
        ? (PcHomeController.instance.folderNavigatePath.value?.trim() ?? '')
        : '';
    final hasInitialPath = pathFromWidget.isNotEmpty || pathFromHome.isNotEmpty;
    controller = Get.put(
      PcFileExplorerController(autoLoadRoot: !hasInitialPath),
      tag: _controllerTag,
      permanent: false,
    );
    _searchCtrl = TextEditingController(text: controller.searchQuery.value);
    _searchSyncWorker = ever<String>(controller.searchQuery, (_) {
      final desired = controller.searchQuery.value;
      if (_searchCtrl.text == desired) return;
      _searchCtrl.value = _searchCtrl.value.copyWith(
        text: desired,
        selection: TextSelection.collapsed(offset: desired.length),
        composing: TextRange.empty,
      );
    });

    _windowId = widget.windowId;
    if (_windowId != null && _windowId!.trim().isNotEmpty) {
      FileShortcutService.ensure().register(
        windowId: _windowId!.trim(),
        controller: controller,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initial = widget.initialPath?.trim() ?? '';
      if (initial.isNotEmpty) {
        controller.navigateTo(initial);
        return;
      }
      if (!widget.listenHomeNavigateSignal) return;
      final homeCtrl = PcHomeController.instance;
      final p = homeCtrl.folderNavigatePath.value?.trim() ?? '';
      if (p.isNotEmpty) {
        controller.navigateTo(p);
        // 使用完一次 home 导航路径后立即清空，防止下次纯打开「文件」应用时继续沿用上次目录
        homeCtrl.folderNavigatePath.value = null;
      }
    });

    if (widget.listenHomeNavigateSignal) {
      final homeCtrl = PcHomeController.instance;
      _navigateWorker = ever<int>(homeCtrl.folderNavigateNonce, (_) async {
        final p = homeCtrl.folderNavigatePath.value?.trim() ?? '';
        if (p.isEmpty) return;
        await controller.navigateTo(p);
      });
    }
  }

  @override
  void dispose() {
    // 组件销毁时手动删除控制器
    _navigateWorker?.dispose();
    _searchSyncWorker?.dispose();
    _searchCtrl.dispose();
    final wid = _windowId?.trim() ?? '';
    if (wid.isNotEmpty) {
      FileShortcutService.ensure().unregister(wid);
    }
    Get.delete<PcFileExplorerController>(tag: _controllerTag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<PcFileExplorerController>(
      tag: _controllerTag,
      builder: (ctrl) {
        //显示所有文件
        ctrl.onlyShowDir.value = false;
        final theme = Theme.of(context);
        return Column(
          children: [
            // 顶部区域：左侧返回+面包屑（带边框），右侧搜索栏（与 title bar 同高，左侧为红绿灯按钮留空）
            SizedBox(
              height: _topBarHeight,
              child: Padding(
                padding: const EdgeInsets.only(left: 72, right: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: _searchBarHeight,
                        padding: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: Row(
                          children: [
                            //返回上一级
                            Obx(
                              () => Tooltip(
                                message: 'back'.tr,
                                child: SizedBox(
                                  width: _searchBarHeight,
                                  height: _searchBarHeight,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: ctrl.isRoot
                                        ? null
                                        : () => ctrl.goUp(),
                                    child: Center(
                                      child: Icon(
                                        Icons.arrow_back_ios_new_outlined,
                                        size: _searchBarHeight * 0.5,
                                        color: ctrl.isRoot
                                            ? theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.3)
                                            : theme.colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // 面包屑
                            Expanded(child: PcFileBreadcrumb(ctrl: ctrl)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    CustomExpandableSearchBar(
                      hintText: 'folder_search_placeholder'.tr,
                      controller: _searchCtrl,
                      onChanged: (v) => ctrl.setSearchQuery(v),
                      onClear: () => ctrl.setSearchQuery(''),
                      height: _searchBarHeight,
                      expandedWidth: 180,
                    ),
                  ],
                ),
              ),
            ),
            const CustomDivider(height: 1),
            // 主区域：左树形 + 右文件
            Expanded(
              child: Obx(() {
                return CustomSplitView(
                  leftWidth: ctrl.leftWidth.value,
                  onResize: ctrl.setLeftWidth,
                  left: PcFileLeftTree(ctrl: ctrl),
                  right: PcFileRightArea(ctrl: ctrl),
                );
              }),
            ),
          ],
        );
      },
    );
  }
}
