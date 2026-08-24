import 'package:get/get.dart';

class VideoSmartAlbumTooltipUtil {
  static String? buildTooltip(Map<String, dynamic> filterContent) {
    if (filterContent.isEmpty) return null;

    final logic = (filterContent['logic'] ?? 'and').toString().toLowerCase();
    final joiner = logic == 'or'
        ? 'smart_album_join_or'.tr
        : 'smart_album_join_and'.tr;
    final raw = filterContent['conditions'];
    if (raw is! List) return null;

    final parts = <String>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final m = e.cast<String, dynamic>();
      final field = (m['field'] ?? '').toString();
      final op = (m['operator'] ?? '').toString();
      final value = m['value'];
      final text = _formatConditionItem(
        field: field,
        operator: op,
        value: value,
      );
      if (text != null && text.trim().isNotEmpty) parts.add(text);
    }
    if (parts.isEmpty) return null;
    return parts.join(joiner);
  }

  static String _fieldLabel(String field) {
    switch (field.trim()) {
      case 'name':
        return 'smart_album_field_name'.tr;
      case 'nfo_name':
        return 'smart_album_field_nfo_name'.tr;
      case 'nfo_actor':
        return 'smart_album_field_nfo_actor'.tr;
      case 'nfo_director':
        return 'smart_album_field_nfo_director'.tr;
      case 'nfo_genres':
        return 'smart_album_field_nfo_genres'.tr;
      case 'nfo_regions':
        return 'smart_album_field_nfo_regions'.tr;
      case 'filename':
        return 'filename'.tr;
      case 'path':
        return 'path'.tr;
      case 'year':
        return 'smart_album_field_year'.tr;
      case 'score':
        return 'smart_album_field_score'.tr;
      case 'duration_min':
        return 'smart_album_field_duration'.tr;
      default:
        return field.trim();
    }
  }

  static String? _formatConditionItem({
    required String field,
    required String operator,
    required dynamic value,
  }) {
    final f = field.trim();
    if (f.isEmpty) return null;
    final op = operator.trim();
    if (op.isEmpty) return null;

    if (op == 'contains') {
      final s = value?.toString() ?? '';
      if (s.trim().isEmpty) return null;
      return 'smart_album_tooltip_contains'.trParams({
        'field': _fieldLabel(f),
        'value': s,
      });
    }

    if (op != 'gt' && op != 'eq' && op != 'lt') return null;
    final n = num.tryParse(value?.toString() ?? '');
    if (n == null) return null;

    final opText = switch (op) {
      'gt' => 'smart_album_cmp_gt'.tr,
      'lt' => 'smart_album_cmp_lt'.tr,
      _ => 'smart_album_cmp_eq'.tr,
    };

    final v = n % 1 == 0 ? n.toInt().toString() : n.toString();
    if (f == 'duration_min') {
      return 'smart_album_tooltip_compare'.trParams({
        'field': _fieldLabel(f),
        'op': opText,
        'value': v,
        'unit': 'smart_album_unit_min'.tr,
      });
    }

    return 'smart_album_tooltip_compare_no_unit'.trParams({
      'field': _fieldLabel(f),
      'op': opText,
      'value': v,
    });
  }
}
