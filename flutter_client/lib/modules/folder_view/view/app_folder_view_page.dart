import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../core/theme/custom_colors.dart';
import '../../../utils/dialog_util.dart';
import '../../base/components/custom_divider.dart';
import '../../base/components/custom_glass_card.dart';
import '../../../utils/device_utils.dart';
import '../../files/views/app_components/app_file_list_body.dart';
import '../../files/views/app_components/app_file_multi_select_bar.dart';
import '../../files/views/app_components/app_file_search_bar.dart';
import '../../files/views/app_components/app_file_sheets.dart';
import '../../files/views/app_components/app_file_toolbar.dart';
import '../../files/views/app_components/app_file_top_actions_bar.dart';
import '../../files/controllers/file_controller.dart';
import '../controller/app_folder_view_controller.dart';
import '../folder_view_module_type.dart';

class AppFolderViewPage extends StatefulWidget {
  const AppFolderViewPage({
    super.key,
    required this.moduleType,
    this.initialPath,
    this.initFolderName,
    this.isRootPage = true,
  });

  final FolderViewModuleType moduleType;
  final String? initialPath;
  final String? initFolderName;
  final bool isRootPage;

  @override
  State<AppFolderViewPage> createState() => _AppFolderViewPageState();
}

class _AppFolderViewPageState extends State<AppFolderViewPage> {
  static const String _childRouteName = 'app_folder_view_child_route';
  final TextEditingController _searchController = TextEditingController();
  String? _ctrlTag;
  AppFolderViewController? _ctrl;
  bool _lowVersionDialogShown = false;

  @override
  void initState() {
    super.initState();
    if (_isServerVersionTooLow()) return;
    _ctrlTag = 'app_folder_view_${widget.moduleType.name}_${UniqueKey()}';
    _ctrl = Get.put(
      AppFolderViewController(moduleType: widget.moduleType, autoLoadRoot: false),
      tag: _ctrlTag!,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ctrl?.listDirectory(widget.initialPath ?? '', null);
    });
  }

  @override
  void dispose() {
    if (_ctrlTag != null) {
      Get.delete<AppFolderViewController>(tag: _ctrlTag!, force: true);
    }
    _searchController.dispose();
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
      return SafeArea(
        bottom: false,
        child: SingleChildScrollView(
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
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final ctrlTag = _ctrlTag;
    final controller = _ctrl;
    if (ctrlTag == null || controller == null) return const SizedBox.shrink();

    return GetBuilder<AppFolderViewController>(
      init: controller,
      tag: ctrlTag,
      builder: (ctrl) {
        ctrl.onlyShowDir.value = false;

        final statusBarStyle = DeviceUtils.isMobile
            ? SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: theme.brightness == Brightness.dark
                    ? Brightness.light
                    : Brightness.dark,
                statusBarBrightness: theme.brightness,
              )
            : null;

        return WillPopScope(
          onWillPop: () async {
            if (ctrl.isMultiSelectMode.value) {
              ctrl.exitMultiSelectMode();
              return false;
            }
            return true;
          },
          child: statusBarStyle != null
              ? AnnotatedRegion<SystemUiOverlayStyle>(
                  value: statusBarStyle,
                  child: _buildScaffold(theme, ctrl),
                )
              : _buildScaffold(theme, ctrl),
        );
      },
    );
  }

  Widget _buildScaffold(ThemeData theme, AppFolderViewController ctrl) {
    final customColors = theme.extension<CustomColors>();
    return Scaffold(
      backgroundColor: customColors!.mainContentBgColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 顶部操作栏
            AppFileTopActionsBar(
              title: (() {
                if (!widget.isRootPage) {
                  final t = (widget.initFolderName ?? '').trim();
                  return t.isEmpty ? widget.moduleType.titleKey.tr : t;
                }
                return widget.moduleType.titleKey.tr;
              })(),
              showBack: !widget.isRootPage,
              onBackPressed: () {
                if (ctrl.isMultiSelectMode.value) {
                  ctrl.exitMultiSelectMode();
                  return;
                }
                if (widget.isRootPage) {
                  return;
                }
                Get.back();
              },
              onClosePressed: () {
                if (widget.isRootPage) return;
                Navigator.of(context).popUntil((route) {
                  return route.settings.name != _childRouteName;
                });
              },
              showClose: !widget.isRootPage,
              onCreatePressed: () => showAppFileCreateSheet(context, ctrl),
            ),
            // 搜索栏
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: AppFileSearchBar(
                ctrl: ctrl,
                controller: _searchController,
              ),
            ),
            // 视图选择 文件类型筛选
            AppFileToolbar(
              ctrl: ctrl,
              onSortPressed: () => showAppFileSortSheet(context, ctrl),
              onFilterPressed: () => showAppFileFilterSheet(context, ctrl),
              onViewPressed: () => showAppFileViewSheet(context, ctrl),
            ),
            const CustomDivider(height: 1),
            Expanded(
              child: RefreshIndicator(
                onRefresh: ctrl.refreshPage,
                //主列表
                child: AppFileListBody(
                  ctrl: ctrl,
                  onOpenDir: (path, folderName) async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        settings: const RouteSettings(name: _childRouteName),
                        builder: (_) => AppFolderViewPage(
                          moduleType: widget.moduleType,
                          initialPath: path,
                          initFolderName: folderName,
                          isRootPage: false,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Obx(() {
        if (ctrl.isMultiSelectMode.value) {
          return AppFileMultiSelectBar(ctrl: ctrl);
        }
        return const SizedBox.shrink();
      }),
    );
  }
}
