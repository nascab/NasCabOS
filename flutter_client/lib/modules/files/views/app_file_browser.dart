import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../base/components/custom_divider.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/custom_colors.dart';
import '../../../utils/device_utils.dart';
import '../../home/views/app_home_page.dart';
import '../../home/views/pc_home_page.dart';
import '../controllers/app_file_controller.dart';
import 'app_components/app_file_bottom_nav_bar.dart';
import 'app_components/app_file_list_body.dart';
import 'app_components/app_file_multi_select_bar.dart';
import 'app_components/app_file_search_bar.dart';
import 'app_components/app_file_sheets.dart';
import 'app_components/app_file_toolbar.dart';
import 'app_components/app_file_top_actions_bar.dart';

class AppFileBrowser extends StatefulWidget {
  const AppFileBrowser({
    super.key,
    this.initialPath,
    this.initFolderName,
    this.isRootPage = true,
  });

  final String? initialPath;
  final String? initFolderName;
  final bool isRootPage;

  @override
  State<AppFileBrowser> createState() => _AppFileBrowserState();
}

class _AppFileBrowserState extends State<AppFileBrowser> {
  final TextEditingController _searchController = TextEditingController();
  late final String _ctrlTag;
  late final AppFileController _ctrl;

  Widget _buildHomePage() {
    if (DeviceUtils.isMobile) {
      return const AppHomePage();
    }
    return PcHomePage();
  }

  @override
  void initState() {
    super.initState();
    _ctrlTag = 'app_file_${UniqueKey()}';
    _ctrl = Get.put(AppFileController(autoLoadRoot: false), tag: _ctrlTag);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ctrl.listDirectory(widget.initialPath ?? '', null);
    });
  }

  @override
  void dispose() {
    Get.delete<AppFileController>(tag: _ctrlTag, force: true);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GetBuilder<AppFileController>(
      tag: _ctrlTag,
      builder: (ctrl) {
        ctrl.onlyShowDir.value = false;

        int moduleIndex() {
          final m = ctrl.currentModule.value;
          if (m == 'favorites') return 1;
          if (m == 'recent') return 2;
          return 0;
        }

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

  Widget _buildScaffold(ThemeData theme, AppFileController ctrl) {
    int moduleIndex() {
      final m = ctrl.currentModule.value;
      if (m == 'favorites') return 1;
      if (m == 'recent') return 2;
      return 0;
    }

    final customColors = Theme.of(context).extension<CustomColors>();
    return Scaffold(
      backgroundColor: customColors?.mainContentBgColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 顶部操作栏
            Obx(
              () => AppFileTopActionsBar(
                title: (() {
                  final m = ctrl.currentModule.value;
                  if (!widget.isRootPage) {
                    final t = (widget.initFolderName ?? '').trim();
                    return t.isEmpty ? 'app_folder'.tr : t;
                  }
                  if (m == 'favorites') {
                    return 'favorites'.tr;
                  }
                  if (m == 'recent') {
                    return 'recent'.tr;
                  }
                  return 'app_folder'.tr;
                })(),
                onBackPressed: () {
                  if (ctrl.isMultiSelectMode.value) {
                    ctrl.exitMultiSelectMode();
                    return;
                  }
                  if (widget.isRootPage) {
                    if (Get.key.currentState?.canPop() ?? false) {
                      Get.back();
                      return;
                    }
                    Get.offAll(
                      _buildHomePage,
                      transition: Transition.leftToRight,
                    );
                    return;
                  }
                  Get.back();
                },
                onClosePressed: () {
                  if (widget.isRootPage) return;
                  var foundRoot = false;
                  Get.until((route) {
                    if (route.settings.name == AppRoutes.files) {
                      foundRoot = true;
                      return true;
                    }
                    return false;
                  });
                  if (!foundRoot) {
                    Get.offAllNamed(AppRoutes.files);
                  }
                },
                showClose: !widget.isRootPage,
                onCreatePressed: () => showAppFileCreateSheet(context, ctrl),
              ),
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
              onViewPressed: () {
                const modes = ['grid', 'large_grid', 'list'];
                final idx = modes.indexOf(ctrl.viewMode.value);
                ctrl.viewMode.value = modes[(idx + 1) % modes.length];
              },
            ),
            const CustomDivider(height: 1),
            Expanded(
              child: RefreshIndicator(
                onRefresh: ctrl.refreshPage,
                //主列表
                child: AppFileListBody(
                  ctrl: ctrl,
                  onOpenDir: (path, folderName) async {
                    await Get.to(
                      () => AppFileBrowser(
                        initialPath: path,
                        initFolderName: folderName,
                        isRootPage: false,
                      ),
                      preventDuplicates: false,
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
        if (!widget.isRootPage) return const SizedBox.shrink();
        return AppFileBottomNavBar(
          currentIndex: moduleIndex(),
          onIndexChanged: (idx) async {
            if (idx == 1) {
              await ctrl.listDirectory('', 'favorites');
              return;
            }
            if (idx == 2) {
              await ctrl.listDirectory('', 'recent');
              return;
            }
            await ctrl.listDirectory('', 'normal');
          },
        );
      }),
    );
  }
}
