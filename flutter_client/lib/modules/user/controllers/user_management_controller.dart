import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../service/user_api_service.dart';
import '../../transfer/models/file_operation_log.dart';
import '../../../utils/dialog_util.dart';
import '../../../utils/toast_util.dart';

class UserManagementController extends GetxController {
  final users = <Map<String, dynamic>>[].obs;
  final selectedIds = <int>{}.obs;
  final loading = false.obs;
  final keyword = ''.obs;
  final usersPage = 1.obs;
  final usersHasMore = true.obs;
  final usersLoadingMore = false.obs;
  final UserApiService _api = UserApiService();
  final loginRecords = <Map<String, dynamic>>[].obs;
  final loginRecordsPage = 1.obs;
  final loginRecordsHasMore = true.obs;
  final loginRecordsLoading = false.obs;

  final operationLogs = <FileOperationLog>[].obs;
  final operationLogsPage = 1.obs;
  final operationLogsHasMore = true.obs;
  final operationLogsLoading = false.obs;
  final operationLogsTotal = 0.obs;
  final operationLogsKeyword = ''.obs;
  final operationLogsTabActive = false.obs;
  Worker? _operationLogsSearchWorker;

  // 缓存每个用户的权限，避免窗口尺寸改变时重复调用API
  final userPermissions = <int, RxList<Map<String, dynamic>>>{}.obs;
  final userTwofaStatus = <int, Map<String, dynamic>>{}.obs;
  final userTwofaSetup = <int, Map<String, dynamic>>{}.obs;
  final userTwofaLoading = <int, bool>{};
  final _twofaBindCodeControllers = <int, TextEditingController>{};

  @override
  void onInit() {
    super.onInit();
    fetchUsers();

    // 监听selectedIds变化，当用户切换时清除旧用户的权限缓存
    ever(selectedIds, (ids) {
      // 清除所有权限缓存，确保切换用户时重新获取权限
      userPermissions.clear();
      userTwofaStatus.clear();
      userTwofaSetup.clear();

      operationLogs.clear();
      operationLogsTotal.value = 0;
      operationLogsPage.value = 1;
      operationLogsHasMore.value = true;
    });

    _operationLogsSearchWorker = debounce(operationLogsKeyword, (_) {
      if (!operationLogsTabActive.value) return;
      if (selectedIds.isEmpty) return;
      refreshOperationLogs(selectedIds.first);
    }, time: const Duration(milliseconds: 500));
  }

  TextEditingController twofaBindCodeController(int uid) {
    return _twofaBindCodeControllers.putIfAbsent(
      uid,
      () => TextEditingController(),
    );
  }

  Future<void> fetchUsers() async {
    loading.value = true;
    try {
      const limit = 20;
      usersPage.value = 1;
      usersHasMore.value = true;
      final list = await _api.fetchUsers(
        page: 1,
        limit: limit,
        keyword: keyword.value,
      );
      final casted = list.cast<Map<String, dynamic>>();
      users.assignAll(casted);
      usersHasMore.value = casted.length >= limit;
      usersPage.value = usersHasMore.value ? 2 : 1;
      // 清理权限缓存，因为用户列表可能已更新
      userPermissions.clear();
      if (users.isNotEmpty) {
        final firstId = (users.first['id'] as int?);
        if (firstId != null) {
          selectedIds
            ..clear()
            ..add(firstId);
          await refreshLoginRecords(firstId);
        }
      } else {
        selectedIds.clear();
        loginRecords.clear();
        loginRecordsPage.value = 1;
        loginRecordsHasMore.value = true;

        operationLogs.clear();
        operationLogsTotal.value = 0;
        operationLogsPage.value = 1;
        operationLogsHasMore.value = true;
      }
    } catch (e) {
      DialogUtil.showErrorDialog(message: 'user_mgmt_fetch_failed'.tr);
    } finally {
      loading.value = false;
    }
  }

  Future<void> loadMoreUsers() async {
    if (loading.value || usersLoadingMore.value || !usersHasMore.value) return;
    usersLoadingMore.value = true;
    try {
      const limit = 20;
      final page = usersPage.value;
      final list = await _api.fetchUsers(
        page: page,
        limit: limit,
        keyword: keyword.value,
      );
      final casted = list.cast<Map<String, dynamic>>();
      if (casted.isEmpty) {
        usersHasMore.value = false;
        return;
      }
      users.addAll(casted);
      usersHasMore.value = casted.length >= limit;
      if (usersHasMore.value) {
        usersPage.value = page + 1;
      }
    } finally {
      usersLoadingMore.value = false;
    }
  }

  void toggleSelect(int id) {
    if (selectedIds.contains(id)) {
      selectedIds.remove(id);
    } else {
      selectedIds.add(id);
    }
  }

  Future<bool> createUser(
    String username,
    String password, {
    String? userRemark,
    String? phone,
  }) async {
    final res = await _api.createUser(
      username: username,
      password: password,
      userRemark: userRemark,
      phone: phone,
    );
    await fetchUsers();
    final ok = res.success == true;
    if (!ok) {
      DialogUtil.showErrorDialog(
        message: res.message ?? 'user_mgmt_create_failed'.tr,
      );
    } else {
      ToastUtil.show('operation_success'.tr, title: 'operation_success'.tr);
    }
    return ok;
  }

  Future<bool> updateUser(
    int id, {
    String? username,
    String? password,
    bool? isActive,
    String? userRemark,
    String? phone,
  }) async {
    final res = await _api.updateUser(
      id: id,
      username: username,
      password: password,
      isActive: isActive,
      userRemark: userRemark,
      phone: phone,
    );
    await fetchUsers();
    if (!res.success) {
      DialogUtil.showErrorDialog(
        message: res.message ?? 'user_mgmt_update_failed'.tr,
      );
    } else {
      ToastUtil.show('operation_success'.tr, title: 'operation_success'.tr);
    }
    return res.success;
  }

  Future<bool> deleteSelected() async {
    if (selectedIds.isEmpty) return true;
    final res = await _api.deleteUsers(selectedIds.toList());
    if (res.success == true) {
      await fetchUsers();
      selectedIds.clear();
      ToastUtil.show('delete_success'.tr, title: 'operation_success'.tr);
    } else {
      DialogUtil.showErrorDialog(message: res.message ?? 'operation_failed'.tr);
    }
    return res.success;
  }

  Future<List<Map<String, dynamic>>> getPermissions(int uid) async {
    // 如果已有缓存，直接返回
    if (userPermissions.containsKey(uid)) {
      return userPermissions[uid]!.toList();
    }

    // 否则从API获取并缓存
    try {
      final list = await _api.getUserPermissions(uid);
      final permissions = list.cast<Map<String, dynamic>>();
      // 创建并缓存Rx列表
      userPermissions[uid] = permissions.obs;
      // 通知UI刷新
      update(['permissions_$uid']);
      return permissions;
    } catch (e) {
      DialogUtil.showErrorDialog(
        message: 'user_mgmt_permissions_fetch_failed'.tr,
      );
      // 缓存空列表，避免重复请求失败
      userPermissions[uid] = <Map<String, dynamic>>[].obs;
      // 通知UI刷新
      update(['permissions_$uid']);
      return <Map<String, dynamic>>[];
    }
  }

  Future<bool> setPermissions(
    int uid,
    List<Map<String, dynamic>> permissions,
  ) async {
    final res = await _api.setUserPermissions(uid, permissions);
    if (res.success) {
      // 权限更新成功后更新缓存
      userPermissions[uid] = permissions.obs;
      // 通知UI刷新
      update(['permissions_$uid']);
    } else {
      print("失败了！${res.message}");
      DialogUtil.showErrorDialog(message: res.message ?? 'operation_failed'.tr);
    }
    return res.success;
  }

  Future<void> refreshLoginRecords(int uid, {int limit = 20}) async {
    loginRecordsLoading.value = true;
    try {
      loginRecordsPage.value = 1;
      final res = await _api.getLoginRecords(uid: uid, page: 1, limit: limit);
      final list = res.cast<Map<String, dynamic>>();
      loginRecords.assignAll(list);
      loginRecordsHasMore.value = list.length >= limit;
      if (loginRecordsHasMore.value) {
        loginRecordsPage.value = 2;
      }
    } finally {
      loginRecordsLoading.value = false;
    }
  }

  Future<void> loadMoreLoginRecords({int limit = 20}) async {
    if (loginRecordsLoading.value || !loginRecordsHasMore.value) return;
    if (selectedIds.isEmpty) return;
    final uid = selectedIds.first;
    loginRecordsLoading.value = true;
    try {
      final page = loginRecordsPage.value;
      final res = await _api.getLoginRecords(
        uid: uid,
        page: page,
        limit: limit,
      );
      final list = res.cast<Map<String, dynamic>>();
      if (list.isEmpty) {
        loginRecordsHasMore.value = false;
        return;
      }
      loginRecords.addAll(list);
      loginRecordsHasMore.value = list.length >= limit;
      if (loginRecordsHasMore.value) {
        loginRecordsPage.value = page + 1;
      }
    } finally {
      loginRecordsLoading.value = false;
    }
  }

  Future<void> refreshOperationLogs(int uid, {int pageSize = 20}) async {
    operationLogsLoading.value = true;
    try {
      operationLogsPage.value = 1;
      final keyword = operationLogsKeyword.value.trim();
      final res = await _api.getUserFileLogs(
        uid: uid,
        page: 1,
        pageSize: pageSize,
        stateList: const ['SUCCESS'],
        keyword: keyword.isEmpty ? null : keyword,
      );

      if (!res.success || res.data == null) {
        operationLogs.clear();
        operationLogsTotal.value = 0;
        operationLogsHasMore.value = false;
        return;
      }

      final data = res.data!;
      operationLogsTotal.value = data.total;
      operationLogs.assignAll(data.list);
      operationLogsHasMore.value =
          operationLogs.length < operationLogsTotal.value;
      if (operationLogsHasMore.value) {
        operationLogsPage.value = 2;
      }
    } finally {
      operationLogsLoading.value = false;
    }
  }

  Future<void> loadMoreOperationLogs({int pageSize = 20}) async {
    if (operationLogsLoading.value || !operationLogsHasMore.value) return;
    if (selectedIds.isEmpty) return;
    final uid = selectedIds.first;

    operationLogsLoading.value = true;
    try {
      final page = operationLogsPage.value;
      final keyword = operationLogsKeyword.value.trim();
      final res = await _api.getUserFileLogs(
        uid: uid,
        page: page,
        pageSize: pageSize,
        stateList: const ['SUCCESS'],
        keyword: keyword.isEmpty ? null : keyword,
      );

      if (!res.success || res.data == null) {
        operationLogsHasMore.value = false;
        return;
      }

      final data = res.data!;
      operationLogsTotal.value = data.total;

      if (data.list.isEmpty) {
        operationLogsHasMore.value = false;
        return;
      }

      operationLogs.addAll(data.list);
      operationLogsHasMore.value =
          operationLogs.length < operationLogsTotal.value;
      if (operationLogsHasMore.value) {
        operationLogsPage.value = page + 1;
      }
    } finally {
      operationLogsLoading.value = false;
    }
  }

  void _setTwofaLoading(int uid, bool v) {
    userTwofaLoading[uid] = v;
    update(['twofa_$uid']);
  }

  Future<Map<String, dynamic>> getTwofaStatus(int uid) async {
    if (userTwofaStatus.containsKey(uid)) return userTwofaStatus[uid] ?? {};
    try {
      _setTwofaLoading(uid, true);
      final data = await _api.getUser2faStatus(uid: uid);
      userTwofaStatus[uid] = data;
      update(['twofa_$uid']);
      return data;
    } catch (e) {
      userTwofaStatus[uid] = {};
      update(['twofa_$uid']);
      return {};
    } finally {
      _setTwofaLoading(uid, false);
    }
  }

  Future<void> refreshTwofaStatus(int uid) async {
    try {
      _setTwofaLoading(uid, true);
      final data = await _api.getUser2faStatus(uid: uid);
      userTwofaStatus[uid] = data;
      update(['twofa_$uid']);
    } catch (e) {
      DialogUtil.showErrorDialog(message: 'operation_failed'.tr);
    } finally {
      _setTwofaLoading(uid, false);
    }
  }

  Future<Map<String, dynamic>?> setupTwofa(
    int uid, {
    String? issuer,
    String? accountName,
  }) async {
    try {
      _setTwofaLoading(uid, true);
      final data = await _api.setupUser2fa(
        uid: uid,
        issuer: issuer,
        accountName: accountName,
      );
      userTwofaSetup[uid] = data;
      await refreshTwofaStatus(uid);
      update(['twofa_$uid']);
      ToastUtil.show('operation_success'.tr, title: 'operation_success'.tr);
      return data;
    } catch (e) {
      DialogUtil.showErrorDialog(message: e.toString());
      return null;
    } finally {
      _setTwofaLoading(uid, false);
    }
  }

  Future<bool> enableTwofa(int uid, {required String code}) async {
    try {
      _setTwofaLoading(uid, true);
      final setup = userTwofaSetup[uid] ?? {};
      final secret = setup['secret'];
      final res = await _api.enableUser2fa(
        uid: uid,
        code: code,
        secret: secret is String ? secret : null,
      );
      if (!res.success) {
        DialogUtil.showErrorDialog(
          message: res.message ?? 'operation_failed'.tr,
        );
        return false;
      }
      userTwofaSetup[uid] = {...setup, if (res.data != null) ...res.data!};
      await refreshTwofaStatus(uid);
      ToastUtil.show('operation_success'.tr, title: 'operation_success'.tr);
      update(['twofa_$uid']);
      return true;
    } finally {
      _setTwofaLoading(uid, false);
    }
  }

  Future<bool> resetTwofa(int uid) async {
    _setTwofaLoading(uid, true);
    try {
      final res = await _api.resetUser2fa(uid: uid);
      if (res.success) {
        userTwofaSetup.remove(uid);
        await refreshTwofaStatus(uid);
        ToastUtil.show('operation_success'.tr, title: 'operation_success'.tr);
        update(['twofa_$uid']);
        return true;
      }
      DialogUtil.showErrorDialog(message: res.message ?? 'operation_failed'.tr);
      return false;
    } finally {
      _setTwofaLoading(uid, false);
    }
  }

  @override
  void onClose() {
    _operationLogsSearchWorker?.dispose();
    _operationLogsSearchWorker = null;
    for (final c in _twofaBindCodeControllers.values) {
      c.dispose();
    }
    _twofaBindCodeControllers.clear();
    super.onClose();
  }
}
