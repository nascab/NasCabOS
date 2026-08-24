import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/modules/base/components/custom_glass_card.dart';
import 'package:NasCabOS/modules/base/components/custom_no_data.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../security_center_controller.dart';

class DeviceManagePanel extends StatelessWidget {
  final SecurityCenterController ctrl;
  final bool appMode;
  const DeviceManagePanel({
    super.key,
    required this.ctrl,
    this.appMode = false,
  });

  static final _timeFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  /// 格式化时间。若服务器返回的是当地时间（无 Z 的字符串），则直接展示不再做 toLocal 转换，避免重复加时区偏移。
  String _formatTime(dynamic v) {
    if (v == null) return '';
    if (v is int) {
      if (v <= 0) return '';
      final dt = DateTime.fromMillisecondsSinceEpoch(v, isUtc: true).toLocal();
      return _timeFormat.format(dt);
    }
    final s = v.toString().trim();
    if (s.isEmpty) return '';
    final parsed = DateTime.tryParse(s);
    if (parsed != null) {
      final dt = parsed.isUtc ? parsed.toLocal() : parsed;
      return _timeFormat.format(dt);
    }
    return s;
  }

  IconData _deviceIcon(Map<String, dynamic> item) {
    final raw =
        (item['device_type'] ??
                item['platform'] ??
                item['os'] ??
                item['client_type'] ??
                item['client_name'] ??
                item['device_name'] ??
                '')
            .toString()
            .toLowerCase();
    if (raw.contains('android')) return Icons.phone_android;
    if (raw.contains('iphone') || raw.contains('ios')) {
      return Icons.phone_iphone;
    }
    if (raw.contains('ipad') || raw.contains('tablet')) {
      return Icons.tablet_mac;
    }
    if (raw.contains('mac') || raw.contains('darwin')) {
      return Icons.laptop_mac;
    }
    if (raw.contains('windows') || raw.contains('win')) {
      return Icons.laptop_windows;
    }
    if (raw.contains('linux')) return Icons.laptop;
    if (raw.contains('web') || raw.contains('browser')) {
      return Icons.public;
    }
    if (raw.contains('tv')) return Icons.tv;
    return Icons.devices_outlined;
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

  Widget _buildItem(BuildContext context, Map<String, dynamic> it) {
    final theme = Theme.of(context);
    final name = (it['device_name'] ?? it['device_id'] ?? '').toString();
    final deviceId = (it['device_id'] ?? '').toString();
    final firstSeen = _formatTime(it['first_seen_at']);
    final lastSeen = _formatTime(it['last_seen_at']);
    final osVersion = (it['os_version'] ?? '').toString();
    final trusted =
        it['trusted_flag'] == true || it['trusted_flag'] == 1;
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
                      _deviceIcon(it),
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
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
                  label: 'security.device_id'.tr,
                  value: deviceId,
                ),
                const SizedBox(height: 6),
                _infoRow(
                  context,
                  label: 'security.device_first_seen'.tr,
                  value: firstSeen,
                ),
                const SizedBox(height: 6),
                _infoRow(
                  context,
                  label: 'security.device_last_seen'.tr,
                  value: lastSeen,
                ),
                const SizedBox(height: 6),
                _infoRow(
                  context,
                  label: 'security.device_os_version'.tr,
                  value: osVersion,
                ),
                const SizedBox(height: 6),
                _infoRow(
                  context,
                  label: 'security.device_trusted'.tr,
                  value: trusted ? 'yes'.tr : 'no'.tr,
                ),
              ],
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: IconButton(
              tooltip: 'security.device_kick'.tr,
              onPressed: deviceId.isEmpty
                  ? null
                  : () => ctrl.kickDevice(deviceId),
              icon: Icon(
                Icons.logout,
                color: theme.colorScheme.error,
              ),
            ),
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
              'security.devices_title'.tr,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'refresh'.tr,
            onPressed: () => ctrl.loadDevices(showLoading: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customColors = Theme.of(context).extension<CustomColors>();
    const edgePadding = EdgeInsets.all(12);

    if (appMode) {
      return Container(
        color: customColors?.mainContentBgColor,
        child: Obx(() {
          final items = ctrl.devices;
          if (items.isEmpty) {
            return const CustomNoData();
          }
          return ListView.separated(
            padding: edgePadding,
            itemCount: items.length,
            separatorBuilder: (_, index) => index == items.length - 1
                ? const SizedBox.shrink()
                : const SizedBox(height: 12),
            itemBuilder: (_, index) => _buildItem(context, items[index]),
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
              final items = ctrl.devices;
              if (items.isEmpty) {
                return const CustomNoData();
              }
              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    sliver: SliverList.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, index) =>
                          index == items.length - 1
                              ? const SizedBox.shrink()
                              : const SizedBox(height: 12),
                      itemBuilder: (_, index) =>
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
}
