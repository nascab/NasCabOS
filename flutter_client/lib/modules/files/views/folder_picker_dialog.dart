import 'package:NasCabOS/core/api/api_controller.dart';
import 'package:NasCabOS/modules/base/components/custom_divider.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../utils/dialog_util.dart';
import '../controllers/file_controller.dart';

import 'picker_components/folder_picker_confirm_bar.dart';
import 'picker_components/folder_picker_file_system_tab.dart';
import 'picker_components/folder_picker_recent_tab.dart';
import 'picker_components/folder_picker_tab_bar.dart';
import 'picker_components/folder_picker_top_bar.dart';

Future<List<String>?> showFolderPickerBottomSheet(
  BuildContext context, {
  bool multiSelect = true, // 默认支持多选
  bool allowFileSelect = false, // 默认不允许选择文件
  List<String>? allowedExtensions, // 允许选择的文件后缀（不含点，如 torrent）
  String? initialPath, // 默认初始路径为空
  String? sourceType,
  String? serverId, // 按服务器区分最近文件夹；为空时从 ApiController 获取
}) {
  final String? effectiveServerId =
      serverId ??
      (Get.isRegistered<ApiController>()
          ? Get.find<ApiController>().state.serverId
          : null);
  final ScrollController crumbController = ScrollController();
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FolderPickerDialog(
      crumbController: crumbController,
      multiSelect: multiSelect,
      allowFileSelect: allowFileSelect,
      allowedExtensions: allowedExtensions,
      initialPath: initialPath,
      sourceType: sourceType,
      serverId: effectiveServerId ?? '',
    ),
  ).whenComplete(() {
    crumbController.dispose();
  });
}

class FolderPickerDialog extends StatefulWidget {
  final ScrollController crumbController;
  final bool multiSelect;
  final bool allowFileSelect;
  final List<String>? allowedExtensions;
  final String? initialPath;
  final String? sourceType;

  /// 当前服务器 ID，用于按服务器分别保存最近选择的文件夹
  final String serverId;

  const FolderPickerDialog({
    super.key,
    required this.crumbController,
    this.multiSelect = true,
    this.allowFileSelect = false,
    this.allowedExtensions,
    this.initialPath,
    this.sourceType,
    this.serverId = '',
  });

  @override
  State<FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<FolderPickerDialog>
    with TickerProviderStateMixin {
  final RxInt _currentTab = 1.obs; // 0: 最近选择, 1: 文件系统
  final RxList<String> _recentFolders = <String>[].obs;
  static const String _recentFoldersKeyPrefix = 'recent_folders';
  late final TabController _tabController;

  String get _recentFoldersKey => widget.serverId.trim().isEmpty
      ? _recentFoldersKeyPrefix
      : '${_recentFoldersKeyPrefix}_${widget.serverId}';
  bool _didInitController = false;

  static const double _topBarHeight = 50;
  static const double _crumbBarHeight = 45;
  static const double _tabBarHeight = 45;

  @override
  void initState() {
    super.initState();
    // 初始化tab控制器
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: _currentTab.value,
    );
    // 加载最近选择的文件夹
    if (widget.sourceType == null || widget.sourceType!.isEmpty) {
      _loadRecentFolders();
    }
  }

  // 加载最近选择的文件夹（按 serverId 区分）
  Future<void> _loadRecentFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final recent = prefs.getStringList(_recentFoldersKey) ?? [];
    _recentFolders.value = List<String>.from(recent);
  }

  // 保存最近选择的文件夹（按 serverId 区分）
  Future<void> _saveRecentFolder(String folder) async {
    final prefs = await SharedPreferences.getInstance();
    final recent = List<String>.from(
      prefs.getStringList(_recentFoldersKey) ?? [],
    );
    recent.remove(folder);
    recent.insert(0, folder);
    if (recent.length > 10) {
      recent.removeLast();
    }
    await prefs.setStringList(_recentFoldersKey, recent);
    _recentFolders.value = recent;
  }

  /// 创建文件夹成功后询问是否选择新文件夹，若用户确认则关闭并返回该路径
  Future<void> _onFolderCreated(
    BuildContext context,
    String newFolderPath,
  ) async {
    final name = newFolderPath.split(RegExp(r'[/\\]')).last;
    final confirm = await DialogUtil.showConfirmDialog(
      title: 'folder_picker_confirm'.tr,
      content: 'folder_picker_confirm_select_new_folder'.trParams({
        'name': name,
      }),
      confirmText: 'yes'.tr,
      cancelText: 'no'.tr,
    );
    if (confirm == true && context.mounted) {
      await _saveRecentFolder(newFolderPath);
      if (!context.mounted) return;
      Navigator.pop(context, <String>[newFolderPath]);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<FileController>(
      // 这里统一关闭 autoLoadRoot，避免在 onInit 中自动加载根目录，
      // 防止与下面 postFrameCallback 中根据 initialPath 手动调用 listDirectory 产生重复请求
      init: FileController(autoLoadRoot: false),
      builder: (ctrl) {
        final disableRecent =
            widget.sourceType != null && widget.sourceType!.isNotEmpty;
        if (!_didInitController) {
          _didInitController = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // 在 build 结束后再修改响应式变量，避免 build 中触发 Obx 导致异常
            ctrl.onlyShowDir.value = !widget.allowFileSelect;
            ctrl.selected.clear();
            final start = widget.initialPath;
            if (start != null && start.isNotEmpty) {
              ctrl.listDirectory(start, null, sourceType: widget.sourceType);
            } else {
              ctrl.listDirectory('', null, sourceType: widget.sourceType);
            }
          });
        }
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              SizedBox(
                height: _topBarHeight,
                child: FolderPickerTopBar(
                  ctrl: ctrl,
                  onClose: () => Navigator.pop(context, null),
                ),
              ),
              const CustomDivider(height: 1),
              if (!disableRecent) ...[
                SizedBox(
                  height: _tabBarHeight,
                  child: FolderPickerTabBar(
                    currentTab: _currentTab,
                    tabController: _tabController,
                  ),
                ),
                const CustomDivider(height: 1),
              ],
              Expanded(
                child: disableRecent
                    ? FolderPickerFileSystemTab(
                        ctrl: ctrl,
                        crumbController: widget.crumbController,
                        multiSelect: widget.multiSelect,
                        crumbBarHeight: _crumbBarHeight,
                        onFolderCreated: (path) =>
                            _onFolderCreated(context, path),
                      )
                    : Obx(() {
                        if (_currentTab.value == 0) {
                          return FolderPickerRecentTab(
                            ctrl: ctrl,
                            recentFolders: _recentFolders,
                            multiSelect: widget.multiSelect,
                          );
                        } else {
                          return FolderPickerFileSystemTab(
                            ctrl: ctrl,
                            crumbController: widget.crumbController,
                            multiSelect: widget.multiSelect,
                            crumbBarHeight: _crumbBarHeight,
                            onFolderCreated: (path) =>
                                _onFolderCreated(context, path),
                          );
                        }
                      }),
              ),
              FolderPickerConfirmBar(
                ctrl: ctrl,
                allowFileSelect: widget.allowFileSelect,
                allowedExtensions: widget.allowedExtensions,
                onSaveRecentFolder: disableRecent
                    ? (_) async {}
                    : _saveRecentFolder,
              ),
            ],
          ),
        );
      },
    );
  }
}
