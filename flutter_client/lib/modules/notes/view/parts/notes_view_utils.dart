import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

String displayNotesTitle(String title) {
  final value = title.trim();
  return value.isEmpty ? 'notes_untitled'.tr : value;
}

String displayNotesGroupName({
  required String groupId,
  required String groupName,
}) {
  final normalizedGroupId = groupId.trim();
  final normalizedGroupName = groupName.trim().toLowerCase();
  if (normalizedGroupId == 'all' ||
      normalizedGroupName == 'all' ||
      groupName.trim() == '全部') {
    return 'all'.tr;
  }
  return groupName.trim();
}

String formatNotesTime(String iso) {
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return '';
  final now = DateTime.now();
  if (now.year == dt.year && now.month == dt.month && now.day == dt.day) {
    return '${'notes_today'.tr} ${DateFormat('HH:mm').format(dt)}';
  }
  return DateFormat('yyyy-MM-dd HH:mm').format(dt);
}

Color? parseNotesHexColor(String hex) {
  final value = hex.trim();
  if (value.isEmpty) return null;
  final normalized = value.replaceFirst('#', '');
  if (normalized.length != 6) return null;
  return Color(int.parse('FF$normalized', radix: 16));
}
