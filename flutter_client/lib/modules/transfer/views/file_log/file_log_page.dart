import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../utils/device_utils.dart';
import '../../../../utils/popup_menu_util.dart';
import '../../../../modules/base/components/custom_bordered_icon_button.dart';
import '../../../../modules/base/components/custom_expandable_search_bar.dart';
import '../../../../modules/base/components/custom_hover_select_menu.dart';
import '../../../../modules/base/components/custom_no_data.dart';
import '../../controllers/file_log_controller.dart';
import 'file_log_item.dart';

class FileLogPage extends StatefulWidget {
  const FileLogPage({super.key});

  @override
  State<FileLogPage> createState() => _FileLogPageState();
}

class _FileLogPageState extends State<FileLogPage> {
  late final FileLogController controller;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    controller = Get.put(FileLogController());
  }

  static const Map<String, IconData> _statusIcons = {
    'processing': Icons.hourglass_top,
    'waiting': Icons.schedule,
    'completed': Icons.check_circle_outline,
    'failed': Icons.error_outline,
  };

  static const Map<String, IconData> _typeIcons = {
    'all': Icons.list_outlined,
    'copy': Icons.copy_outlined,
    'move': Icons.drive_file_move_outline,
    'delete': Icons.delete_outline,
    'rename': Icons.edit_outlined,
  };

  List<CustomHoverSelectMenuItem<String>> _buildStatusMenuItems() {
    return controller.statusOptions.entries.map((e) {
      return CustomHoverSelectMenuItem<String>(
        value: e.key,
        label: e.value.tr,
        icon: _statusIcons[e.key] ?? Icons.help_outline,
      );
    }).toList();
  }

  List<CustomHoverSelectMenuItem<String>> _buildTypeMenuItems() {
    return controller.typeOptions.entries.map((e) {
      return CustomHoverSelectMenuItem<String>(
        value: e.key,
        label: e.value.tr,
        icon: _typeIcons[e.key] ?? Icons.help_outline,
      );
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (Get.isRegistered<FileLogController>()) {
      Get.delete<FileLogController>();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = Theme.of(context).extension<CustomColors>();
    final isMobile = DeviceUtils.isMobile;
    final paddingH = isMobile ? 12.0 : 16.0;

    return Container(
      decoration: BoxDecoration(
        color: customColors?.mainContentBgColor,
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(12)),
      ),
      child: Column(
        children: [
          // 顶部操作栏：左侧状态+类型筛选，右侧搜索+清除
          Padding(
            padding: EdgeInsets.fromLTRB(
              paddingH,
              isMobile ? 6.0 : 16.0,
              paddingH,
              8,
            ),
            child: Row(
              children: [
                Obx(
                  () => CustomHoverSelectMenu<String>(
                    value: controller.selectedStatus.value,
                    buttonIcon: Icons.filter_alt_outlined,
                    items: _buildStatusMenuItems(),
                    onSelected: controller.onStatusChanged,
                  ),
                ),
                const SizedBox(width: 8),
                Obx(
                  () => CustomHoverSelectMenu<String>(
                    value: controller.selectedType.value,
                    buttonIcon: Icons.filter_alt_outlined,
                    items: _buildTypeMenuItems(),
                    onSelected: controller.onTypeChanged,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CustomExpandableSearchBar(
                    hintText: 'search'.tr,
                    defaultExpanded: !isMobile,
                    onChanged: controller.onSearch,
                    controller: _searchController,
                    alignment: Alignment.centerRight,
                  ),
                ),
                const SizedBox(width: 8),
                Builder(
                  builder: (ctx) => CustomBorderedIconButton(
                    icon: Icons.delete_sweep,
                    tooltip: 'task_clear_all'.tr,
                    onTap: () {
                      final renderBox =
                          ctx.findRenderObject() as RenderBox;
                      final offset = renderBox.localToGlobal(Offset.zero);
                      final size = renderBox.size;
                      PopupMenuUtil.showBelowContent<String>(
                        context: ctx,
                        position: RelativeRect.fromLTRB(
                          offset.dx,
                          offset.dy + size.height + 4,
                          offset.dx + size.width,
                          offset.dy + size.height + 4,
                        ),
                        items: [
                          PopupMenuItem(
                            value: 'completed',
                            child: Text('task_clear_completed'.tr),
                          ),
                          PopupMenuItem(
                            value: 'error',
                            child: Text('task_clear_error'.tr),
                          ),
                          PopupMenuItem(
                            value: 'waiting',
                            child: Text('task_clear_waiting'.tr),
                          ),
                          PopupMenuItem(
                            value: 'all',
                            child: Text('task_clear_all'.tr),
                          ),
                        ],
                      ).then((value) {
                        if (value == null) return;
                        controller.clearLogs(type: value);
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: Obx(() {
              if (controller.isLoading.value && controller.logs.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              if (controller.logs.isEmpty) {
                return CustomNoData(text: 'no_data'.tr);
              }

              return RefreshIndicator(
                onRefresh: controller.onRefresh,
                child: ListView.builder(
                  controller: controller.scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? paddingH - 4 : 0,
                  ),
                  itemCount: controller.logs.length + 1,
                  itemBuilder: (context, index) {
                    if (index == controller.logs.length) {
                      return controller.isLoadMore.value
                          ? Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            )
                          : const SizedBox(height: 16);
                    }

                    final log = controller.logs[index];
                    return FileLogItem(
                      log: log,
                      controller: controller,
                      compact: isMobile,
                    );
                  },
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
