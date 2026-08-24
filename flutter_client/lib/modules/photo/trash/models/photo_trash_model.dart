import '../../timeline/models/photo_timeline_model.dart';

/// 回收站照片列表结果
class TimelineTrashListResult {
  final List<TimelinePhotoItem> items;
  final int total;

  const TimelineTrashListResult({required this.items, required this.total});
}
