import 'package:get/get.dart';
import 'package:flutter/services.dart';
import 'dart:ui' show Offset, Rect;
import '../../../../utils/cache_manager.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/toast_util.dart';
import '../../../../core/user/current_user_controller.dart';
import 'file_controller.dart';
export 'file_controller.dart';
import '../service/file_api_service.dart';

part 'parts/pc_lifecycle.dart';
part 'parts/pc_layout.dart';
part 'parts/pc_view.dart';
part 'parts/pc_drag_select.dart';

/// 文件浏览器控制器（基于GetX）
/// 负责业务状态与交互逻辑，视图仅包含UI代码
class PcFileExplorerController extends FileController {
  /// 列表视图每行高度
  static const kListViewRowHeight = 45.0;

  PcFileExplorerController({
    super.autoLoadRoot = true,
    super.initialSourceType,
    super.listApiPath = '/api/file/list',
    super.searchApiPath = '/api/file/search',
    super.showRootCustomPathEntry = true,
  });
  final rightPanel = 'files'.obs;

  final indexEnabled = false.obs;
  final indexIntervalHours = 72.obs;
  final indexConfigLoading = false.obs;
  final indexConfigSaving = false.obs;

  /// 左侧树形菜单宽度（可拖动调整），限制最小120，最大300
  final leftWidth = 150.0.obs;

  /// 列表视图标题栏各列宽度（可拖动调整）
  final columnWidths = <String, double>{
    'select': 60,
    'name': 300,
    'mtime': 150,
    'size': 100,
    'type': 100,
  }.obs;

  /// 框选拖拽选择矩形（为空表示未拖拽）
  final selectionRect = Rxn<Rect>();

  /// 内容坐标系下的选择矩形（随滚动保持绝对位置）
  final selectionRectContent = Rxn<Rect>();
  Offset? _dragStartViewport;
  double _dragStartScrollOffset = 0;
  Set<String>? _dragSelectionBaseline;
  final pointerInView = false.obs;

  @override
  void onInit() {
    super.onInit();
    PcFileExplorerLifecycle(this)._onControllerInit();
  }

  @override
  void onClose() {
    PcFileExplorerLifecycle(this)._onControllerClose();
    super.onClose();
  }

  void openFilePanel() {
    rightPanel.value = 'files';
  }

  Future<void> openIndexSettings() async {
    if (!CurrentUserController.instance.isAdmin) return;
    rightPanel.value = 'index_settings';
    await loadIndexConfig(showLoading: false);
  }

  Future<void> trySetSearchScope(String scope) async {
    final next = scope == 'global'
        ? 'global'
        : scope == 'subtree'
        ? 'subtree'
        : 'current';
    if (next == searchScope.value) return;
    if (next == 'current') {
      setSearchScope('current');
      return;
    }

    await loadIndexConfig(showLoading: false);
    if (indexEnabled.value == true) {
      setSearchScope(next);
      return;
    }

    if (CurrentUserController.instance.isAdmin) {
      final go = await DialogUtil.showConfirmDialog(
        title: 'file_global_search_disabled_title'.tr,
        content: 'file_global_search_disabled_content'.tr,
        confirmText: 'file_global_search_disabled_go_view'.tr,
        cancelText: 'cancel'.tr,
      );
      if (go == true) {
        await openIndexSettings();
      }
      return;
    }

    ToastUtil.show('file_global_search_disabled_title'.tr);
  }

  Future<void> loadIndexConfig({required bool showLoading}) async {
    if (indexConfigLoading.value) return;
    indexConfigLoading.value = true;
    try {
      final res = await FileApiService.instance.getIndexSettings(
        showLoading: showLoading,
      );
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      final data = (res.data ?? {}).cast<String, dynamic>();
      indexEnabled.value = data['enabled'] == true;
      final v = int.tryParse(data['intervalHours']?.toString() ?? '');
      indexIntervalHours.value = v != null && v > 0 ? v : 72;
    } finally {
      indexConfigLoading.value = false;
    }
  }

  Future<bool> saveIndexConfig({
    required bool enabled,
    required int intervalHours,
  }) async {
    if (indexConfigSaving.value) return false;
    indexConfigSaving.value = true;
    try {
      final res = await FileApiService.instance.saveIndexSettings(
        enabled: enabled,
        intervalHours: intervalHours,
        showLoading: true,
      );
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return false;
      }
      final data = (res.data ?? {}).cast<String, dynamic>();
      indexEnabled.value = data['enabled'] == true;
      final v = int.tryParse(data['intervalHours']?.toString() ?? '');
      indexIntervalHours.value = v != null && v > 0 ? v : intervalHours;
      ToastUtil.show('operation_success'.tr);
      return true;
    } finally {
      indexConfigSaving.value = false;
    }
  }

  Future<bool> resetIndex() async {
    final res = await FileApiService.instance.resetIndex(showLoading: true);
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return false;
    }
    ToastUtil.show('operation_success'.tr);
    await loadIndexConfig(showLoading: false);
    return true;
  }

  bool get allowExternalUploadDrop => true;
}
