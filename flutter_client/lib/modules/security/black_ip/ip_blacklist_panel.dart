import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/modules/base/components/custom_glass_card.dart';
import 'package:NasCabOS/modules/base/components/custom_no_data.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../security_center_controller.dart';

class IpBlacklistPanel extends StatelessWidget {
  final SecurityCenterController ctrl;
  final bool appMode;
  const IpBlacklistPanel({super.key, required this.ctrl, this.appMode = false});

  static final _timeFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  String _formatTime(dynamic v) {
    final ms = v is int ? v : int.tryParse(v?.toString() ?? '');
    if (ms == null || ms <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    return _timeFormat.format(dt);
  }

  Widget _infoRow(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    const edgePadding = EdgeInsets.all(12);

    if (appMode) {
      return Container(
        color: customColors?.mainContentBgColor,
        child: Obx(() {
          final items = ctrl.blacklist;
          if (items.isEmpty) {
            return Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: CustomNoData(text: 'no_data'.tr),
              ),
            );
          }
          return ListView.separated(
            padding: edgePadding,
            itemCount: items.length,
            separatorBuilder: (_, index) => index == items.length - 1
                ? const SizedBox.shrink()
                : const SizedBox(height: 12),
            itemBuilder: (context, index) => _buildItem(context, items[index]),
          );
        }),
      );
    }

    return Container(
      color: customColors?.mainContentBgColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: edgePadding.copyWith(bottom: 0),
            child: _buildHeader(context),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Obx(() {
              final items = ctrl.blacklist;
              if (items.isEmpty) {
                return CustomNoData(text: 'no_data'.tr);
              }
              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    sliver: SliverList.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, index) => index == items.length - 1
                          ? const SizedBox.shrink()
                          : const SizedBox(height: 12),
                      itemBuilder: (context, index) =>
                          _buildItem(context, items[index]),
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return CustomGlassCard(
      child: Row(
        children: [
          Expanded(
            child: Text(
              'security.ip_blacklist_title'.tr,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'refresh'.tr,
            onPressed: () => ctrl.loadBlacklist(showLoading: true),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'task_clear_all'.tr,
            onPressed: ctrl.clearBlacklist,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, Map<String, dynamic> it) {
    final theme = Theme.of(context);
    final ip = (it['ip'] ?? '').toString();
    final desc = (it['description'] ?? '').toString();
    final time = _formatTime(it['createTime']);
    return CustomGlassCard(
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.block,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ip,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _infoRow(
                  context,
                  label: 'security.description'.tr,
                  value: desc.isEmpty ? '—' : desc,
                ),
                const SizedBox(height: 6),
                _infoRow(
                  context,
                  label: 'security.record_time'.tr,
                  value: time.isEmpty ? '—' : time,
                ),
              ],
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: IconButton(
              tooltip: 'delete'.tr,
              onPressed: () => ctrl.deleteIp(ip),
              icon: Icon(Icons.delete_outline),
            ),
          ),
        ],
      ),
    );
  }
}
