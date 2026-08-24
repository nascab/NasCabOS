import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../utils/device_utils.dart';
import '../service/message_api_service.dart';
import '../../home/views/app_home_controller.dart';
import '../../home/views/pc_home_controller.dart';

class MessageItem {
  final int id;
  final int uid;
  final String title;
  final String message;
  final Map<String, dynamic>? action;
  final int readStatus;
  final int level;
  final int isPublic;
  final String createTime;

  MessageItem({
    required this.id,
    required this.uid,
    required this.title,
    required this.message,
    required this.action,
    required this.readStatus,
    required this.level,
    required this.isPublic,
    required this.createTime,
  });

  factory MessageItem.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    String toStr(dynamic v) {
      if (v == null) return '';
      return v.toString();
    }

    Map<String, dynamic>? parsedAction;
    final rawAction = json['action'];
    if (rawAction is Map) {
      parsedAction = Map<String, dynamic>.from(rawAction);
    } else if (rawAction is String) {
      final s = rawAction.trim();
      if (s.isNotEmpty) {
        try {
          final decoded = jsonDecode(s);
          if (decoded is Map) {
            parsedAction = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
      }
    }

    return MessageItem(
      id: toInt(json['id']),
      uid: toInt(json['uid']),
      title: toStr(json['title']),
      message: toStr(json['message']),
      action: parsedAction,
      readStatus: toInt(json['read_status']),
      level: toInt(json['level']),
      isPublic: toInt(json['is_public']) == 0 ? 0 : 1,
      createTime: toStr(json['create_time']),
    );
  }
}

class MessageCenterController extends GetxController {
  final MessageApiService _api = MessageApiService.instance;

  final RxList<MessageItem> messages = <MessageItem>[].obs;
  final RxInt currentPage = 1.obs;
  final RxInt pageSize = 20.obs;
  final RxInt total = 0.obs;
  final RxInt totalPages = 0.obs;
  final RxInt unreadCount = 0.obs;
  final RxnInt selectedLevel = RxnInt(null);
  final RxString searchKeyword = ''.obs;
  final RxBool isLoading = false.obs;
  final RxBool hasMore = true.obs;

  @override
  void onInit() {
    super.onInit();
    loadMessages();
    loadUnreadCount();
  }

  Future<void> loadMessages({bool refresh = false}) async {
    if (isLoading.value) return;

    if (refresh) {
      currentPage.value = 1;
      messages.clear();
      hasMore.value = true;
    }

    if (!hasMore.value && !refresh) return;

    isLoading.value = true;

    try {
      final result = await _api.getMessages(
        page: currentPage.value,
        pageSize: pageSize.value,
        level: selectedLevel.value,
        keyword: searchKeyword.value.isEmpty ? null : searchKeyword.value,
      );

      final items = (result['items'] as List? ?? []).map((e) {
        if (e is Map<String, dynamic>) return MessageItem.fromJson(e);
        if (e is Map) return MessageItem.fromJson(Map<String, dynamic>.from(e));
        return MessageItem.fromJson(const {});
      }).toList();

      if (refresh) {
        messages.assignAll(items);
      } else {
        messages.addAll(items);
      }

      total.value = int.tryParse('${result['total'] ?? 0}') ?? 0;
      totalPages.value = int.tryParse('${result['totalPages'] ?? 0}') ?? 0;

      if (currentPage.value >= totalPages.value ||
          items.length < pageSize.value) {
        hasMore.value = false;
      }
    } catch (e) {
      print('加载消息失败: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoading.value || !hasMore.value) return;
    currentPage.value++;
    await loadMessages();
  }

  Future<void> refreshMessages() async {
    await loadMessages(refresh: true);
    await loadUnreadCount();
  }

  Future<void> loadUnreadCount() async {
    try {
      final result = await _api.getUnreadCount();
      unreadCount.value = result['count'] as int? ?? 0;
    } catch (e) {
      print('加载未读数量失败: $e');
    }
  }

  Future<void> markAsRead(int messageId) async {
    try {
      await _api.markAsRead(messageId: messageId);

      final index = messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        messages[index] = MessageItem(
          id: messages[index].id,
          uid: messages[index].uid,
          title: messages[index].title,
          message: messages[index].message,
          action: messages[index].action,
          readStatus: 1,
          level: messages[index].level,
          isPublic: messages[index].isPublic,
          createTime: messages[index].createTime,
        );
      }

      await loadUnreadCount();
    } catch (e) {
      print('标记已读失败: $e');
    }
  }

  Future<void> markAllAsRead() async {
    try {
      await _api.markAsRead();
      messages.refresh();
      await loadUnreadCount();
    } catch (e) {
      print('标记全部已读失败: $e');
    }
  }

  Future<void> deleteMessage(int messageId) async {
    try {
      await _api.deleteMessage(messageId: messageId);
      messages.removeWhere((m) => m.id == messageId);
      total.value = messages.length;
      await loadUnreadCount();
    } catch (e) {
      print('删除消息失败: $e');
    }
  }

  Future<void> clearMessages() async {
    try {
      await _api.clearMessages(level: selectedLevel.value);
      messages.clear();
      total.value = 0;
      await loadUnreadCount();
    } catch (e) {
      print('清空消息失败: $e');
    }
  }

  void filterByLevel(int? level) {
    selectedLevel.value = level;
    refreshMessages();
  }

  void searchMessages(String keyword) {
    searchKeyword.value = keyword;
    refreshMessages();
  }

  Future<void> onMessageTap(MessageItem item) async {
    if (item.readStatus == 0) {
      await markAsRead(item.id);
    }
    await _handleAction(item.action);
  }

  Future<void> _handleAction(Map<String, dynamic>? action) async {
    if (action == null) return;
    final type = action['type']?.toString().trim() ?? '';
    if (type.isEmpty || type == 'none') return;

    if (type == 'openUrl') {
      final url = action['url']?.toString().trim() ?? '';
      if (url.isEmpty) return;
      final uri = Uri.tryParse(url);
      if (uri == null) return;
      if (DeviceUtils.isWeb) {
        await launchUrl(uri, webOnlyWindowName: '_blank');
        return;
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    if (type == 'openApp') {
      final app = action['app']?.toString().trim() ?? '';
      if (app.isEmpty) return;

      if (DeviceUtils.isDesktop && Get.isRegistered<PcHomeController>()) {
        final home = PcHomeController.instance;
        home.openApp(
          windowId: app,
          viewBuilder: home.builtinAppViewBuilder(app),
          title: ('app_$app').tr,
          icon: home.buildAppIcon(app),
        );
        return;
      }

      if (Get.isRegistered<AppHomeController>()) {
        AppHomeController.instance.openApp(app);
      }
      return;
    }
  }

  String getLevelText(int level) {
    switch (level) {
      case 1:
        return 'important'.tr;
      case 2:
        return 'urgent'.tr;
      default:
        return 'normal'.tr;
    }
  }

  Color getLevelColor(int level, ThemeData theme) {
    switch (level) {
      case 1:
        return Colors.orange;
      case 2:
        return Colors.red;
      default:
        return theme.colorScheme.onSurface.withOpacity(0.6);
    }
  }
}
