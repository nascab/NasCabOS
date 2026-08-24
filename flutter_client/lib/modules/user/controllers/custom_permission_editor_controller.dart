import 'package:get/get.dart';
import '../../../utils/toast_util.dart';

class CustomPermissionEditorController extends GetxController {
  final List<Map<String, dynamic>> initialPermissions;
  final Future<bool> Function(List<Map<String, dynamic>> permissions) onSave;
  final Future<void> Function(void Function(String path) onSelected)
  onPickDirectory;

  final items = <Map<String, dynamic>>[].obs;

  CustomPermissionEditorController({
    required this.initialPermissions,
    required this.onSave,
    required this.onPickDirectory,
  });

  @override
  void onInit() {
    super.onInit();
    _initializeItems();
  }

  void _initializeItems() {
    final Map<String, Map<String, dynamic>> grouped = {};
    for (final p in initialPermissions) {
      final resType = (p['res_type'] ?? 'file').toString();
      final resPath = (p['res_path'] ?? '').toString();
      final action = (p['action'] ?? '').toString();
      if (resPath.isEmpty || action.isEmpty) continue;
      final key = '$resType|$resPath';
      if (!grouped.containsKey(key)) {
        grouped[key] = {
          'res_type': resType,
          'res_path': resPath,
          'actions': <String>[action],
        };
      } else {
        final List<String> acts = List<String>.from(grouped[key]!['actions']);
        if (!acts.contains(action)) acts.add(action);
        grouped[key]!['actions'] = acts;
      }
    }
    items.assignAll(grouped.values.toList());
  }

  Future<void> autoSave() async {
    final List<Map<String, dynamic>> flattened = [];
    for (final it in items) {
      final List<String> acts = List<String>.from(it['actions'] ?? <String>[]);
      for (final a in acts) {
        flattened.add({
          'res_type': it['res_type'] ?? 'file',
          'res_path': it['res_path'] ?? '',
          'action': a,
        });
      }
    }

    final success = await onSave(flattened);
    if (success) {
      ToastUtil.show('user_mgmt_permission_saved'.tr);
    } else {
      // 保存失败，通知UI重新加载原始数据
      // 通过重新初始化items来恢复原始状态
      _initializeItems();
      update();
      ToastUtil.show('user_mgmt_permission_save_failed'.tr);
    }
  }

  void addPermission(String path) {
    final idx = items.indexWhere(
      (e) =>
          (e['res_type'] ?? 'file') == 'file' && (e['res_path'] ?? '') == path,
    );
    if (idx >= 0) {
      final List<String> acts = List<String>.from(
        items[idx]['actions'] ?? <String>[],
      );
      if (!acts.contains('view')) {
        acts.add('view');
        items[idx]['actions'] = acts;
      }
    } else {
      items.add({
        'res_type': 'file',
        'res_path': path,
        'actions': <String>['view'],
      });
    }
    update();
    autoSave();
  }

  void removePermission(int index) {
    items.removeAt(index);
    update();
    autoSave();
  }

  void toggleAction(int index, String action) {
    final it = items[index];
    final List<String> acts = List<String>.from(it['actions'] ?? <String>[]);
    if (acts.contains(action)) {
      acts.remove(action);
    } else {
      acts.add(action);
    }
    items[index]['actions'] = acts;
    update();
    autoSave();
  }

  Future<void> pickDirectory() async {
    await onPickDirectory((path) => addPermission(path));
  }
}
