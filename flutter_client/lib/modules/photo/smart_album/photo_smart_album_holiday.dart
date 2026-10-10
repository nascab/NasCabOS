import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/api/api_controller.dart';
import '../../../utils/server_version_util.dart';

/// 智能相册「节假日」模式所需的最低服务端版本
const int kSmartAlbumHolidayMinServerVersion = 12;

class PhotoSmartAlbumHoliday {
  /// 与服务端 photoSmartAlbumHolidayUtil.js 中 HOLIDAY_DEFS 的 key 保持一致
  final String key;

  const PhotoSmartAlbumHoliday(this.key);

  String get name => 'smart_album_holiday_$key'.tr;

  String? get description {
    final k = 'smart_album_holiday_${key}_desc';
    final text = k.tr;
    return text == k ? null : text;
  }
}

/// 预设节假日（展示顺序即选择器顺序）
const List<PhotoSmartAlbumHoliday> kPhotoSmartAlbumHolidays = [
  PhotoSmartAlbumHoliday('new_year'),
  PhotoSmartAlbumHoliday('spring_festival'),
  PhotoSmartAlbumHoliday('qingming'),
  PhotoSmartAlbumHoliday('labor_day'),
  PhotoSmartAlbumHoliday('dragon_boat'),
  PhotoSmartAlbumHoliday('mid_autumn'),
  PhotoSmartAlbumHoliday('national_day'),
  PhotoSmartAlbumHoliday('women_day'),
  PhotoSmartAlbumHoliday('youth_day'),
  PhotoSmartAlbumHoliday('children_day'),
  PhotoSmartAlbumHoliday('army_day'),
  PhotoSmartAlbumHoliday('christmas'),
  PhotoSmartAlbumHoliday('easter'),
];

bool isSmartAlbumHolidaySupported() {
  return ServerVersionUtil.isAtLeast(
    ApiController.instance.serverVersion,
    kSmartAlbumHolidayMinServerVersion,
  );
}

bool isValidSmartAlbumHolidayKey(String? key) {
  if (key == null || key.isEmpty) return false;
  return kPhotoSmartAlbumHolidays.any((e) => e.key == key);
}

String smartAlbumHolidayName(String? key) {
  for (final h in kPhotoSmartAlbumHolidays) {
    if (h.key == key) return h.name;
  }
  return key ?? '';
}

String? smartAlbumHolidayDescription(String? key) {
  for (final h in kPhotoSmartAlbumHolidays) {
    if (h.key == key) return h.description;
  }
  return null;
}

/// 节假日选择器（PC/移动端两套弹窗共用）
class SmartAlbumHolidayField extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const SmartAlbumHolidayField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final items = <DropdownMenuItem<String>>[
      for (final h in kPhotoSmartAlbumHolidays)
        DropdownMenuItem<String>(value: h.key, child: Text(h.name)),
    ];
    // 兼容服务端存在但客户端暂不识别的节假日 key，避免 DropdownButton 断言
    final effectiveValue = isValidSmartAlbumHolidayKey(value)
        ? value
        : kPhotoSmartAlbumHolidays.first.key;
    if (effectiveValue != value && value.isNotEmpty) {
      items.add(DropdownMenuItem<String>(value: value, child: Text(value)));
    }

    final desc = smartAlbumHolidayDescription(effectiveValue);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          value: effectiveValue,
          decoration: InputDecoration(
            labelText: 'smart_album_holiday_label'.tr,
            border: const OutlineInputBorder(),
          ),
          items: items,
          onChanged: (v) {
            if (v == null) return;
            onChanged(v);
          },
        ),
        if (desc != null && desc.isNotEmpty) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              desc,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }
}
