import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../controller/photo_timeline_controller.dart';
import '../../../../base/components/custom_checkbox.dart';
import '../../../../../utils/dialog_util.dart';
import '../../../../../utils/device_utils.dart';

/// 照片时间线项日期组件
class PhotoTimelineItemDate extends StatelessWidget {
  final TimelineListDateHeader item;
  final String? controllerTag;

  const PhotoTimelineItemDate({
    super.key,
    required this.item,
    this.controllerTag,
  });

  /// 根据日期字符串解析并返回本地化星期几，解析失败返回 null
  String? _weekdayFromDate(String dateStr) {
    final parsed = DateTime.tryParse(dateStr.trim());
    if (parsed == null) return null;
    final locale = Get.locale;
    final localeStr = locale != null
        ? (locale.countryCode != null && locale.countryCode!.isNotEmpty
              ? '${locale.languageCode}_${locale.countryCode}'
              : locale.languageCode)
        : 'en_US';
    return DateFormat.EEEE(localeStr).format(parsed);
  }

  static Widget _dateInfoDialogRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  static void _showDateGeoCameraDialog(
    BuildContext context, {
    required String dateStr,
    required String geo,
    required String camera,
  }) {
    final locationLabel = 'timeline_date_location'.tr;
    final cameraLabel = 'timeline_date_camera'.tr;
    final geoTrim = geo.trim();
    final cameraTrim = camera.trim();
    final rows = <Widget>[];
    if (geoTrim.isNotEmpty) {
      rows.add(_dateInfoDialogRow(locationLabel, geoTrim));
    }
    if (cameraTrim.isNotEmpty) {
      rows.add(_dateInfoDialogRow(cameraLabel, cameraTrim));
    }
    if (rows.isEmpty) {
      rows.add(Text('no_data'.tr));
    }
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return DialogUtil.createAlertDialog(
          title: Text(dateStr),
          constraints: const BoxConstraints(maxWidth: 480, minWidth: 280),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: rows,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('confirm'.tr),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<PhotoTimelineController>(tag: controllerTag);
    final weekday = _weekdayFromDate(item.date);
    return Padding(
      key: ValueKey('header_${item.date}'),
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Obx(() {
            final isSelected = controller.isDateSelected(item.date);
            return CustomCheckbox(
              value: isSelected,
              onChanged: (_) => controller.toggleDateSelection(item.date),
              isCircle: true,
              side: BorderSide(
                color: Get.theme.colorScheme.onSurface,
                width: 2.0,
              ),
            );
          }),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 第一行：日期 + 星期几
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        item.date,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (weekday != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        weekday,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: Get.theme.colorScheme.onSurface.withOpacity(
                            0.75,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                // 第二行：地点、拍摄设备（单行不换行，溢出省略）
                Obx(() {
                  final info = controller.dateInfoMap[item.date];
                  final geo = info?.geo.trim() ?? '';
                  final camera = info?.camera.trim() ?? '';
                  final color = Get.theme.colorScheme.onSurface.withOpacity(
                    0.6,
                  );
                  final locationLabel = 'timeline_date_location'.tr;
                  final cameraLabel = 'timeline_date_camera'.tr;
                  final textStyle = TextStyle(fontSize: 12, color: color);
                  void onTapSubtitle() {
                    _showDateGeoCameraDialog(
                      context,
                      dateStr: item.date,
                      geo: geo,
                      camera: camera,
                    );
                  }
                  if (geo.isEmpty && camera.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  final subtitle = Text.rich(
                    TextSpan(
                      style: textStyle,
                      children: [
                        if (geo.isNotEmpty) ...[
                          TextSpan(text: '$locationLabel: '),
                          TextSpan(text: geo),
                        ],
                        if (geo.isNotEmpty && camera.isNotEmpty)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: const SizedBox(width: 15),
                          ),
                        if (camera.isNotEmpty) ...[
                          TextSpan(text: '$cameraLabel: '),
                          TextSpan(text: camera),
                        ],
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  );
                  final tappable = GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: onTapSubtitle,
                    child: subtitle,
                  );
                  final enableHover =
                      DeviceUtils.isDesktop ||
                      (DeviceUtils.isWeb &&
                          DeviceUtils.isDesktopLayout(context));
                  if (enableHover) {
                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: tappable,
                    );
                  }
                  return tappable;
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
