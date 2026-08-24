part of '../photo_timeline_controller.dart';

class PhotoTimelineSourceFilterStorage {
  static const String _cacheKey = 'timeline_selected_source_paths';

  final CacheManager _cacheManager = CacheManager();

  Future<List<String>> restoreSelection({
    required Iterable<String> availablePaths,
  }) async {
    List<String> savedPaths;
    try {
      savedPaths = _normalizePaths(_cacheManager.getStringList(_cacheKey));
    } catch (_) {
      return const <String>[];
    }
    if (savedPaths.isEmpty) {
      return const <String>[];
    }
    final availablePathSet = _normalizePaths(availablePaths).toSet();
    final restoredPaths = savedPaths
        .where(availablePathSet.contains)
        .toList(growable: false);
    if (_samePaths(savedPaths, restoredPaths)) {
      return restoredPaths;
    }
    await saveSelection(restoredPaths);
    return restoredPaths;
  }

  Future<void> saveSelection(Iterable<String> paths) async {
    final normalizedPaths = _normalizePaths(paths);
    if (normalizedPaths.isEmpty) {
      try {
        await _cacheManager.remove(_cacheKey);
      } catch (_) {}
      return;
    }
    try {
      await _cacheManager.setStringList(_cacheKey, normalizedPaths);
    } catch (_) {}
  }

  List<String> _normalizePaths(Iterable<String>? paths) {
    if (paths == null) {
      return const <String>[];
    }
    final normalized = <String>[];
    final seen = <String>{};
    for (final rawPath in paths) {
      final path = rawPath.trim();
      if (path.isEmpty || !seen.add(path)) {
        continue;
      }
      normalized.add(path);
    }
    return normalized;
  }

  bool _samePaths(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }
}

/// 与时间戳换算相关的工具方法。
extension PhotoTimelineControllerUtils on PhotoTimelineController {
  /// 将 `yyyy-MM-dd` 转换为当天 00:00:00.000 的毫秒时间戳。
  int _getStartOfDayTimestamp(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
    } catch (_) {
      return 0;
    }
  }

  /// 将 `yyyy-MM-dd` 转换为当天 23:59:59.999 的毫秒时间戳。
  int _getEndOfDayTimestamp(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateTime(
        date.year,
        date.month,
        date.day,
        23,
        59,
        59,
        999,
      ).millisecondsSinceEpoch;
    } catch (_) {
      return 0;
    }
  }

  String _minDateStr(String a, String b) => a.compareTo(b) <= 0 ? a : b;

  String _maxDateStr(String a, String b) => a.compareTo(b) >= 0 ? a : b;

  ({int startTime, int endTime, int startIndex, int endIndex, int totalCount})?
  _buildFetchRangeByMinCount({
    required String anchorDate,
    required bool up,
    required bool includeAnchor,
    required int minCount,
  }) {
    if (dateList.isEmpty) return null;
    final anchorIndex = dateList.indexWhere(
      (e) => e.originalDate == anchorDate,
    );
    if (anchorIndex < 0) return null;

    if (up) {
      final from = anchorIndex - (includeAnchor ? 0 : 1);
      if (from < 0) return null;
      var total = 0;
      var startIndex = from;
      var endIndex = from;
      for (var i = from; i >= 0; i--) {
        total += dateList[i].count;
        startIndex = i;
        if (total >= minCount) break;
      }
      final startDate = dateList[startIndex].originalDate;
      final endDate = dateList[endIndex].originalDate;
      final minDate = _minDateStr(startDate, endDate);
      final maxDate = _maxDateStr(startDate, endDate);
      return (
        startTime: _getStartOfDayTimestamp(minDate),
        endTime: _getEndOfDayTimestamp(maxDate),
        startIndex: startIndex,
        endIndex: endIndex,
        totalCount: total,
      );
    } else {
      final from = anchorIndex + (includeAnchor ? 0 : 1);
      if (from >= dateList.length) return null;
      var total = 0;
      var startIndex = from;
      var endIndex = from;
      for (var i = from; i < dateList.length; i++) {
        total += dateList[i].count;
        endIndex = i;
        if (total >= minCount) break;
      }
      final startDate = dateList[startIndex].originalDate;
      final endDate = dateList[endIndex].originalDate;
      final minDate = _minDateStr(startDate, endDate);
      final maxDate = _maxDateStr(startDate, endDate);
      return (
        startTime: _getStartOfDayTimestamp(minDate),
        endTime: _getEndOfDayTimestamp(maxDate),
        startIndex: startIndex,
        endIndex: endIndex,
        totalCount: total,
      );
    }
  }

  /// 格式化日期时间
  String formatDateTime(int timestamp) {
    final format = DateFormat('yyyy-MM-dd HH:mm:ss');
    return format.format(DateTime.fromMillisecondsSinceEpoch(timestamp));
  }

  bool _sameSelectedPaths(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }
}
