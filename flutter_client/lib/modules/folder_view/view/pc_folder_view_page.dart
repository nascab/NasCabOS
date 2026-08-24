import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../utils/dialog_util.dart';
import '../../base/components/custom_glass_card.dart';
import '../../base/components/custom_divider.dart';
import '../../base/components/custom_expandable_search_bar.dart';
import '../../files/controllers/pc_file_explorer_controller.dart';
import '../../files/views/pc_components/pc_file_breadcrumb.dart';
import '../../files/views/pc_components/pc_file_right_area.dart';
import '../controller/pc_folder_view_controller.dart';
import '../folder_view_module_type.dart';

class PcFolderViewPage extends StatefulWidget {
  const PcFolderViewPage({super.key, required this.moduleType});

  final FolderViewModuleType moduleType;

  @override
  State<PcFolderViewPage> createState() => _PcFolderViewPageState();
}

class _PcFolderViewPageState extends State<PcFolderViewPage> {
  static const double _topBarHeight = 40;
  static const double _searchBarHeight = 30;

  PcFolderViewController? _controller;
  String? _controllerTag;
  TextEditingController? _searchController;
  Worker? _searchSyncWorker;
  bool _lowVersionDialogShown = false;

  @override
  void initState() {
    super.initState();
    if (_isServerVersionTooLow()) return;
    _controllerTag = 'pc_folder_view_${widget.moduleType.name}_${UniqueKey()}';
    _controller = Get.put(
      PcFolderViewController(moduleType: widget.moduleType),
      tag: _controllerTag!,
      permanent: false,
    );
    _searchController = TextEditingController(
      text: _controller!.searchQuery.value,
    );
    _searchSyncWorker = ever<String>(_controller!.searchQuery, (_) {
      final desired = _controller!.searchQuery.value;
      if (_searchController!.text == desired) return;
      _searchController!.value = _searchController!.value.copyWith(
        text: desired,
        selection: TextSelection.collapsed(offset: desired.length),
        composing: TextRange.empty,
      );
    });
  }

  @override
  void dispose() {
    _searchSyncWorker?.dispose();
    _searchController?.dispose();
    if (_controllerTag != null) {
      Get.delete<PcFolderViewController>(tag: _controllerTag!, force: true);
    }
    super.dispose();
  }

  bool _isServerVersionTooLow() {
    return !widget.moduleType.isServerVersionSupported;
  }

  void _showLowServerVersionDialogOnce() {
    if (_lowVersionDialogShown) return;
    _lowVersionDialogShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      DialogUtil.showInfoDialog(
        title: 'tip'.tr,
        content: 'server_version_too_low'.tr,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isServerVersionTooLow()) {
      _showLowServerVersionDialogOnce();
      final theme = Theme.of(context);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.moduleType.titleKey.tr,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            CustomGlassCard(
              padding: const EdgeInsets.all(16),
              child: Text(
                'server_version_too_low'.tr,
                style: theme.textTheme.bodyMedium?.copyWith(
                  // color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final controllerTag = _controllerTag;
    final searchController = _searchController;
    final controller = _controller;
    if (controllerTag == null ||
        searchController == null ||
        controller == null) {
      return const SizedBox.shrink();
    }

    return GetBuilder<PcFolderViewController>(
      init: controller,
      tag: controllerTag,
      builder: (ctrl) {
        ctrl.onlyShowDir.value = false;
        final theme = Theme.of(context);
        return Column(
          children: [
            SizedBox(
              height: _topBarHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
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
                            Obx(
                              () => Tooltip(
                                message: 'back'.tr,
                                child: SizedBox(
                                  width: _searchBarHeight,
                                  height: _searchBarHeight,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: ctrl.isRoot ? null : ctrl.goUp,
                                    child: Center(
                                      child: Icon(
                                        Icons.arrow_back_ios_new_rounded,
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
                            Expanded(child: PcFileBreadcrumb(ctrl: ctrl)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    CustomExpandableSearchBar(
                      hintText: 'folder_search_placeholder'.tr,
                      controller: searchController,
                      onChanged: ctrl.setSearchQuery,
                      onClear: () => ctrl.setSearchQuery(''),
                      height: _searchBarHeight,
                      expandedWidth: 180,
                    ),
                  ],
                ),
              ),
            ),
            const CustomDivider(height: 1),
            Expanded(child: PcFileRightArea(ctrl: ctrl)),
          ],
        );
      },
    );
  }
}
