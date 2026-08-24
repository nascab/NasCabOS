import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../base/components/custom_button.dart';
import '../../../utils/popup_menu_util.dart';
import '../controllers/message_center_controller.dart';

class MessageCenterView extends StatefulWidget {
  const MessageCenterView({super.key, this.showAppBar = false});

  final bool showAppBar;

  @override
  State<MessageCenterView> createState() => _MessageCenterViewState();
}

class _MessageCenterViewState extends State<MessageCenterView> {
  static const String _controllerTag = 'message_center';
  late final MessageCenterController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(MessageCenterController(), tag: _controllerTag);
  }

  @override
  void dispose() {
    if (Get.isRegistered<MessageCenterController>(tag: _controllerTag)) {
      Get.delete<MessageCenterController>(tag: _controllerTag);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.cardColor,
      appBar: widget.showAppBar
          ? AppBar(
              title: Text('message_center'.tr),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Get.back(),
              ),
              actions: [
                _buildLevelFilterAction(controller, theme),
                Obx(() {
                  if (controller.messages.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return IconButton(
                    tooltip: 'clear'.tr,
                    icon: const Icon(Icons.delete_sweep),
                    onPressed: () {
                      Get.dialog(
                        AlertDialog(
                          title: Text('clear_messages'.tr),
                          content: Text('clear_messages_confirm'.tr),
                          actions: [
                            TextButton(
                              onPressed: () => Get.back(),
                              child: Text('cancel'.tr),
                            ),
                            TextButton(
                              onPressed: () {
                                Get.back();
                                controller.clearMessages();
                              },
                              child: Text('confirm'.tr),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                }),
              ],
            )
          : null,
      body: Column(
        children: [
          if (!widget.showAppBar) _buildHeader(context, controller, theme),
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value && controller.messages.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              if (controller.messages.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.notifications_none,
                        size: 64,
                        color: theme.colorScheme.onSurface.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'no_messages'.tr,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return NotificationListener<ScrollNotification>(
                onNotification: (scrollInfo) {
                  if (scrollInfo is ScrollEndNotification &&
                      scrollInfo.metrics.pixels >=
                          scrollInfo.metrics.maxScrollExtent - 200) {
                    controller.loadMore();
                  }
                  return false;
                },
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount:
                      controller.messages.length +
                      (controller.hasMore.value ? 1 : 0),
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    if (index < controller.messages.length) {
                      return _buildMessageItem(
                        context,
                        controller,
                        controller.messages[index],
                        theme,
                      );
                    } else {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      );
                    }
                  },
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    MessageCenterController controller,
    ThemeData theme,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.onSurface.withOpacity(0.12),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'message_center'.tr,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              // 未读角标：需要时用 Obx 包裹并监听 controller.unreadCount
              const SizedBox.shrink(),
              _buildLevelFilter(context, controller, theme),
              const Spacer(),
              _buildClearButton(context, controller, theme),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLevelFilter(
    BuildContext context,
    MessageCenterController controller,
    ThemeData theme,
  ) {
    return Obx(() {
      final current = controller.selectedLevel.value;
      final items = <PopupMenuEntry<int>>[
        PopupMenuItem<int>(
          value: -1,
          child: Row(
            children: [
              Icon(
                Icons.check,
                color: current == null
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text('all_levels'.tr),
            ],
          ),
        ),
        PopupMenuItem<int>(
          value: 0,
          child: Row(
            children: [
              Icon(
                Icons.check,
                color: current == 0
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text('normal'.tr),
            ],
          ),
        ),
        PopupMenuItem<int>(
          value: 1,
          child: Row(
            children: [
              Icon(
                Icons.check,
                color: current == 1
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text('important'.tr),
            ],
          ),
        ),
        PopupMenuItem<int>(
          value: 2,
          child: Row(
            children: [
              Icon(
                Icons.check,
                color: current == 2
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text('urgent'.tr),
            ],
          ),
        ),
      ];
      return Builder(
        builder: (ctx) => GestureDetector(
          onTap: () {
            final renderBox = ctx.findRenderObject() as RenderBox;
            final offset = renderBox.localToGlobal(Offset.zero);
            final size = renderBox.size;
            PopupMenuUtil.showBelowContent<int>(
              context: ctx,
              position: RelativeRect.fromLTRB(
                offset.dx,
                offset.dy + size.height + 4,
                offset.dx + size.width,
                offset.dy + size.height + 4,
              ),
              items: items,
            ).then((level) {
              if (level != null) {
                controller.filterByLevel(level == -1 ? null : level);
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(
                color: theme.colorScheme.onSurface.withOpacity(0.2),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  current == null
                      ? 'all_levels'.tr
                      : controller.getLevelText(current),
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down,
                  size: 20,
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildLevelFilterAction(
    MessageCenterController controller,
    ThemeData theme,
  ) {
    return Obx(() {
      final current = controller.selectedLevel.value;
      final items = <PopupMenuEntry<int>>[
        PopupMenuItem<int>(
          value: -1,
          child: Row(
            children: [
              Icon(
                Icons.check,
                color: current == null
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text('all_levels'.tr),
            ],
          ),
        ),
        PopupMenuItem<int>(
          value: 0,
          child: Row(
            children: [
              Icon(
                Icons.check,
                color: current == 0
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text('normal'.tr),
            ],
          ),
        ),
        PopupMenuItem<int>(
          value: 1,
          child: Row(
            children: [
              Icon(
                Icons.check,
                color: current == 1
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text('important'.tr),
            ],
          ),
        ),
        PopupMenuItem<int>(
          value: 2,
          child: Row(
            children: [
              Icon(
                Icons.check,
                color: current == 2
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text('urgent'.tr),
            ],
          ),
        ),
      ];
      return Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.filter_alt_outlined),
          tooltip: 'filter_by_level'.tr,
          onPressed: () {
            final renderBox = ctx.findRenderObject() as RenderBox;
            final offset = renderBox.localToGlobal(Offset.zero);
            final size = renderBox.size;
            PopupMenuUtil.showBelowContent<int>(
              context: ctx,
              position: RelativeRect.fromLTRB(
                offset.dx,
                offset.dy + size.height + 4,
                offset.dx + size.width,
                offset.dy + size.height + 4,
              ),
              items: items,
            ).then((level) {
              if (level != null) {
                controller.filterByLevel(level == -1 ? null : level);
              }
            });
          },
        ),
      );
    });
  }

  Widget _buildClearButton(
    BuildContext context,
    MessageCenterController controller,
    ThemeData theme,
  ) {
    return Obx(() {
      if (controller.messages.isEmpty) {
        return const SizedBox.shrink();
      }
      return CustomButton(
        text: 'clear'.tr,
        isPrimary: false,
        icon: const Icon(Icons.delete_sweep, size: 20),
        onPressed: () {
          Get.dialog(
            AlertDialog(
              title: Text('clear_messages'.tr),
              content: Text('clear_messages_confirm'.tr),
              actions: [
                TextButton(
                  onPressed: () => Get.back(),
                  child: Text('cancel'.tr),
                ),
                TextButton(
                  onPressed: () {
                    Get.back();
                    controller.clearMessages();
                  },
                  child: Text('confirm'.tr),
                ),
              ],
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.error,
          foregroundColor: Colors.white,
        ),
      );
    });
  }

  Widget _buildMessageItem(
    BuildContext context,
    MessageCenterController controller,
    MessageItem message,
    ThemeData theme,
  ) {
    final actionType = message.action?['type']?.toString().trim() ?? '';
    final actionable = actionType.isNotEmpty && actionType != 'none';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => controller.onMessageTap(message),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: message.readStatus == 0
                ? theme.colorScheme.primary.withOpacity(0.05)
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.onSurface.withOpacity(0.08),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLevelIndicator(message.level, theme),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: controller
                                .getLevelColor(message.level, theme)
                                .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            controller.getLevelText(message.level),
                            style: TextStyle(
                              color: controller.getLevelColor(
                                message.level,
                                theme,
                              ),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatLocalTime(message.createTime),
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                            fontSize: 12,
                          ),
                        ),
                        if (actionable) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.open_in_new,
                            size: 14,
                            color: theme.colorScheme.onSurface.withOpacity(
                              0.45,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (message.title.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        message.title.trim(),
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ] else ...[
                      const SizedBox(height: 8),
                    ],
                    Text(
                      message.message,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: message.readStatus == 0
                            ? FontWeight.w500
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildDeleteButton(context, controller, message, theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLevelIndicator(int level, ThemeData theme) {
    Color color;
    switch (level) {
      case 1:
        color = Colors.orange;
        break;
      case 2:
        color = Colors.red;
        break;
      default:
        color = theme.colorScheme.onSurface.withOpacity(0.3);
    }
    return Container(
      width: 4,
      height: 40,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildDeleteButton(
    BuildContext context,
    MessageCenterController controller,
    MessageItem message,
    ThemeData theme,
  ) {
    return IconButton(
      icon: Icon(
        Icons.close,
        size: 20,
        color: theme.colorScheme.onSurface.withOpacity(0.5),
      ),
      onPressed: () {
        Get.dialog(
          AlertDialog(
            title: Text('delete_message'.tr),
            content: Text('delete_message_confirm'.tr),
            actions: [
              TextButton(onPressed: () => Get.back(), child: Text('cancel'.tr)),
              TextButton(
                onPressed: () {
                  Get.back();
                  controller.deleteMessage(message.id);
                },
                child: Text('confirm'.tr),
              ),
            ],
          ),
        );
      },
      tooltip: 'delete'.tr,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }

  String _formatLocalTime(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';

    DateTime? dt;
    final n = int.tryParse(s);
    if (n != null) {
      final isMs = n > 10000000000;
      dt = DateTime.fromMillisecondsSinceEpoch(isMs ? n : n * 1000);
    } else {
      dt = DateTime.tryParse(s);
      if (dt == null && s.contains(' ') && !s.contains('T')) {
        dt = DateTime.tryParse(s.replaceFirst(' ', 'T'));
      }
    }

    if (dt == null) return s;

    final local = dt.toLocal();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}
