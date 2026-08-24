import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:math' as math;
import '../../controller/photo_timeline_controller.dart';
import '../../../../../utils/device_utils.dart';

class PhotoTimelineSidebar extends GetView<PhotoTimelineController> {
  final String? controllerTag;
  final bool compact;
  const PhotoTimelineSidebar({
    super.key,
    this.controllerTag,
    this.compact = false,
  });

  @override
  String? get tag => controllerTag;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      width: compact ? 132 : 40,
      child: Obx(() {
        if (controller.dateList.isEmpty) return const SizedBox();

        final desc = controller.sortOrder.value == 'desc';

        return AnimatedOpacity(
          opacity: controller.isTimelineVisible.value ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxHeight;
              if (height <= 0) return const SizedBox();

              // 1. 构建初始 buckets (按日期)
              var buckets = controller.dateList
                  .map((d) => _TimelineBucket.fromDate(d.originalDate, d.count))
                  .whereType<_TimelineBucket>()
                  .toList(growable: false);

              if (buckets.isEmpty) return const SizedBox();

              // 2. 根据数量进行抽稀逻辑 (参考旧项目)
              // 如果数量过多，按照 count 阈值过滤，保留 count 较大的日期
              if (buckets.length > 1000) {
                final filterRatio = buckets.length > 2000
                    ? 0.5
                    : (buckets.length > 1500 ? 0.3 : 0.2);
                final counts = buckets.map((b) => b.count).toList()..sort();
                final numToFilter = (buckets.length * filterRatio).floor();
                if (numToFilter > 0 && numToFilter < counts.length) {
                  final threshold = counts[numToFilter - 1];
                  buckets = buckets.where((b) => b.count >= threshold).toList();
                }
              }

              // 3. 计算每个 bucket 的高度
              // 旧项目逻辑：每个 item 基础高度 = (总高度 - 上下padding) / 总数量
              // 但旧项目是根据 totalPhotoCount 来分配高度的，这里我们简化一下，
              // 仍然使用之前的权重逻辑，或者直接均分，为了视觉效果，权重逻辑更好，
              // 但需要确保年份能显示出来。

              final minItemHeight = 8.0;
              final maxItems = math.max(1, (height / minItemHeight).floor());

              // 如果过滤后仍然超出最大显示数量，进行合并
              if (buckets.length > maxItems) {
                buckets = _mergeBucketsKeepingEnds(
                  buckets,
                  targetCount: maxItems,
                  desc: desc,
                );
              }

              final weights = buckets
                  .map((b) => math.sqrt(math.max(0, b.count).toDouble()) + 1)
                  .toList(growable: false);
              final totalWeight = weights.fold<double>(0, (p, e) => p + e);

              var baseH = minItemHeight;
              // 只有当高度非常小且只有一个 bucket 时才特殊处理
              if (buckets.length == 1 && height < minItemHeight) {
                baseH = height;
              }
              final variableH = math.max(0.0, height - baseH * buckets.length);

              final heights = <double>[];
              for (final w in weights) {
                heights.add(
                  baseH +
                      (totalWeight == 0 ? 0.0 : variableH * w / totalWeight),
                );
              }

              // 4. 标记年份显示 (优先显示年份)
              final showYear = List<bool>.filled(buckets.length, false);
              int? lastYear;

              // 遍历标记每年的第一个(或最后一个，取决于排序)
              // 旧项目逻辑：年份变化时显示
              for (var i = 0; i < buckets.length; i++) {
                final b = buckets[i];
                if (lastYear == null || b.year != lastYear) {
                  showYear[i] = true;
                  lastYear = b.year;
                } else if (i == buckets.length - 1) {
                  showYear[i] = true; // 最后一个总是显示
                } else {
                  // 如果该年照片数量特别多且高度足够，也可以显示？
                  // 旧项目：item.yearPhotoCount * itemHeight > 30
                  // 这里简化，只在年份变化点显示
                }
              }
              return _TimelineBody(
                controller: controller,
                buckets: buckets,
                heights: heights,
                showYear: showYear,
                totalHeight: height,
                compact: compact,
              );
            },
          ),
        );
      }),
    );
  }

  // ... (保留辅助方法)
  // _mergeBucketsKeepingEnds 需要保留
  // _dateForDy 需要修改以支持游标定位? 或者在 Body 中处理

  List<_TimelineBucket> _mergeBucketsKeepingEnds(
    List<_TimelineBucket> buckets, {
    required int targetCount,
    required bool desc,
  }) {
    if (targetCount <= 0) return const [];
    if (buckets.length <= targetCount) return buckets;

    final len = buckets.length;
    if (targetCount == 1) {
      var countSum = 0;
      for (final b in buckets) {
        countSum += b.count;
      }
      final repDate = desc
          ? buckets.first.representativeDate
          : buckets.last.representativeDate;
      final year = _extractYear(repDate) ?? buckets.first.year;
      return [
        _TimelineBucket(
          representativeDate: repDate,
          year: year,
          count: countSum,
        ),
      ];
    }

    if (targetCount == 2) {
      var firstCount = 0;
      for (var i = 0; i < len - 1; i++) {
        firstCount += buckets[i].count;
      }
      final firstDate = buckets.first.representativeDate;
      final firstYear = _extractYear(firstDate) ?? buckets.first.year;
      final last = buckets.last;
      return [
        _TimelineBucket(
          representativeDate: firstDate,
          year: firstYear,
          count: firstCount,
        ),
        last,
      ];
    }

    final merged = <_TimelineBucket>[];

    final first = buckets.first;
    final last = buckets.last;
    merged.add(first);

    final middleCount = targetCount - 2;
    final middleLen = len - 2;
    if (middleLen > 0) {
      for (var i = 0; i < middleCount; i++) {
        var start = 1 + (i * middleLen / middleCount).floor();
        var end = 1 + (((i + 1) * middleLen / middleCount).floor()) - 1;
        if (start < 1) start = 1;
        if (end < start) end = start;
        if (end > len - 2) end = len - 2;

        var countSum = 0;
        for (var j = start; j <= end; j++) {
          countSum += buckets[j].count;
        }
        final repDate = buckets[start].representativeDate;
        final year = _extractYear(repDate) ?? buckets[start].year;
        merged.add(
          _TimelineBucket(
            representativeDate: repDate,
            year: year,
            count: countSum,
          ),
        );
      }
    }

    merged.add(last);
    return merged;
  }

  int? _extractYear(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return date.year;
    } catch (_) {
      return null;
    }
  }

  // 不再需要 _buildBuckets，因为逻辑移到了 build 中且简化了
}

class _TimelineBody extends StatefulWidget {
  final PhotoTimelineController controller;
  final List<_TimelineBucket> buckets;
  final List<double> heights;
  final List<bool> showYear;
  final double totalHeight;
  final bool compact;

  const _TimelineBody({
    required this.controller,
    required this.buckets,
    required this.heights,
    required this.showYear,
    required this.totalHeight,
    required this.compact,
  });

  @override
  State<_TimelineBody> createState() => _TimelineBodyState();
}

class _TimelineBodyState extends State<_TimelineBody> {
  double? _cursorTop;
  double? _lastIdleTop;
  String _cursorRawDate = '';
  String _cursorDate = '';
  bool _dragging = false;
  VoidCallback? _scrollListener;

  @override
  void initState() {
    super.initState();
    _scrollListener = () {
      if (!mounted) return;
      if (_cursorRawDate.trim().isNotEmpty || _dragging) return;
      setState(() {});
    };
    widget.controller.scrollController.addListener(_scrollListener!);
  }

  @override
  void dispose() {
    final listener = _scrollListener;
    if (listener != null) {
      widget.controller.scrollController.removeListener(listener);
    }
    super.dispose();
  }

  double _dyFromGlobal(Offset globalPosition) {
    final box = context.findRenderObject();
    if (box is! RenderBox) return 0;
    return box.globalToLocal(globalPosition).dy;
  }

  double _idleTopForCurrentDate() {
    final date = widget.controller.currentTopDate();
    if (date == null || date.trim().isEmpty) {
      return _lastIdleTop ?? widget.totalHeight / 2;
    }

    var index = widget.buckets.indexWhere((b) => b.representativeDate == date);
    if (index == -1 && date.length >= 7) {
      final prefix = date.substring(0, 7);
      index = widget.buckets.indexWhere(
        (b) => b.representativeDate.startsWith(prefix),
      );
    }
    if (index < 0 || index >= widget.heights.length) {
      return _lastIdleTop ?? widget.totalHeight / 2;
    }

    var offset = 0.0;
    for (var i = 0; i < index; i++) {
      offset += widget.heights[i];
    }
    final top = (offset + widget.heights[index] / 2).clamp(
      0.0,
      widget.totalHeight,
    );
    _lastIdleTop = top;
    return top;
  }

  void _updateCursor(double dy) {
    setState(() {
      _cursorTop = dy.clamp(0, widget.totalHeight);
      final date = _dateForDy(dy);
      if (date != null) {
        _cursorRawDate = date;
        _cursorDate = date;
        if (date.length >= 10) {
          _cursorDate = date.substring(0, 10).replaceAll('-', '/');
        }
        widget.controller.setTimelineHoverDate(date);
        widget.controller.keepTimelineVisible();
      }
    });
  }

  void _showCurrentDate() {
    final date = widget.controller.currentTopDate();
    if (date == null || date.trim().isEmpty) return;
    setState(() {
      _cursorTop ??= _idleTopForCurrentDate();
      _cursorRawDate = date;
      _cursorDate = date;
      if (date.length >= 10) {
        _cursorDate = date.substring(0, 10).replaceAll('-', '/');
      }
      widget.controller.setTimelineHoverDate(date);
      widget.controller.keepTimelineVisible();
    });
  }

  void _clearCursor() {
    setState(() {
      _cursorTop = null;
      _cursorRawDate = '';
      _dragging = false;
    });
    widget.controller.setTimelineHoverDate(null);
    widget.controller.showTimeline();
  }

  String? _dateForDy(double dy) {
    if (widget.buckets.isEmpty || widget.heights.isEmpty) return null;
    final clampedDy = dy < 0 ? 0.0 : dy;
    var low = 0;
    var high = widget.heights.length - 1;
    var sum = 0.0;

    final prefix = List<double>.filled(
      widget.heights.length,
      0.0,
      growable: false,
    );
    for (var i = 0; i < widget.heights.length; i++) {
      sum += widget.heights[i];
      prefix[i] = sum;
    }

    final maxY = prefix.last;
    final target = clampedDy > maxY ? maxY : clampedDy;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (target < prefix[mid]) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    final index = low.clamp(0, widget.buckets.length - 1);
    return widget.buckets[index].representativeDate;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      const idleWidth = 35.0;
      const expandedWidth = 142.0;
      const handleHeight = 40.0;
      final active = _cursorRawDate.trim().isNotEmpty;
      final handleWidth = active ? expandedWidth : idleWidth;

      final effectiveTop = (_cursorTop ?? _idleTopForCurrentDate()).clamp(
        0.0,
        widget.totalHeight,
      );
      var handleTop = effectiveTop - handleHeight / 2;
      if (handleTop < 0) handleTop = 0;
      if (handleTop > widget.totalHeight - handleHeight) {
        handleTop = widget.totalHeight - handleHeight;
      }

      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: handleTop,
            right: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: (_) => _showCurrentDate(),
              onVerticalDragStart: (details) {
                setState(() => _dragging = true);
                _updateCursor(_dyFromGlobal(details.globalPosition));
              },
              onVerticalDragUpdate: (details) {
                _updateCursor(_dyFromGlobal(details.globalPosition));
              },
              onVerticalDragCancel: _clearCursor,
              onVerticalDragEnd: (_) {
                final date = _cursorRawDate.trim();
                if (date.isNotEmpty) {
                  widget.controller.jumpToDate(date);
                }
                _clearCursor();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                width: handleWidth,
                height: handleHeight,
                padding: EdgeInsets.symmetric(horizontal: active ? 12 : 0),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Get.theme.colorScheme.surface.withValues(
                    alpha: _dragging ? 0.95 : 0.86,
                  ),
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(handleHeight / 2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: active
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _cursorDate,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Get.theme.textTheme.bodyMedium?.color,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.chevron_left,
                            size: 18,
                            color: Get.theme.iconTheme.color?.withValues(
                              alpha: 0.75,
                            ),
                          ),
                        ],
                      )
                    : Icon(
                        Icons.unfold_more,
                        size: 18,
                        color: Get.theme.iconTheme.color?.withValues(
                          alpha: 0.7,
                        ),
                      ),
              ),
            ),
          ),
        ],
      );
    }

    // 预计算偏移量
    final offsets = <double>[];
    var currentOffset = 0.0;
    for (final h in widget.heights) {
      offsets.add(currentOffset);
      currentOffset += h;
    }

    // 收集年份标签，放置在顶层以避免被遮挡
    final yearLabels = <Widget>[];
    // 用于检测年份标签是否重叠
    final occupiedRanges = <(double, double)>[];

    for (var i = 0; i < widget.buckets.length; i++) {
      if (widget.showYear[i]) {
        const labelHeight = 16.0;
        // 垂直居中
        var top = offsets[i] + widget.heights[i] / 2 - labelHeight / 2;
        // 边界限制，防止溢出
        top = top.clamp(0.0, widget.totalHeight - labelHeight);

        // 检测重叠
        var isOverlap = false;
        final bottom = top + labelHeight;
        // 简单的重叠检测：检查是否与已放置的任何标签重叠
        // 实际上我们只需要检查上一个，因为是顺序添加的，
        // 但为了保险，还是保留完整检测逻辑或优化为只检测上一个
        // 由于我们希望“优先显示”，这里策略是：
        // 如果重叠，就隐藏当前这个？或者隐藏上一个？
        // 题目要求：如果高度不够把年份简化为白点
        // 所以如果重叠了，当前这个就变成白点。

        for (final range in occupiedRanges) {
          if (top < range.$2 && bottom > range.$1) {
            isOverlap = true;
            break;
          }
        }

        if (!isOverlap) {
          occupiedRanges.add((top, bottom));
          yearLabels.add(
            Positioned(
              top: top,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  height: labelHeight,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    widget.buckets[i].year.toString(),
                    style: TextStyle(
                      fontSize: 10,
                      color: Get.theme.textTheme.bodyMedium?.color,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
          );
        } else {
          // 重叠了，降级为白点
          // 我们需要把这个“降级”状态传递给下面的灰点渲染逻辑，
          // 或者直接在这里添加一个白点 Widget 到 yearLabels 列表里（因为它也是覆盖层）
          yearLabels.add(
            Positioned(
              top: offsets[i] + widget.heights[i] / 2 - 3, // 居中 6px 高度
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Get.theme.colorScheme.onSurface.withValues(
                      alpha: 0.6,
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          );
        }
      }
    }

    Widget content = Container(
      padding: EdgeInsets.zero,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanDown: (details) => _updateCursor(details.localPosition.dy),
        onPanUpdate: (details) => _updateCursor(details.localPosition.dy),
        onPanCancel: _clearCursor,
        onPanEnd: (_) => _clearCursor(),
        onTapUp: (details) {
          final date = _dateForDy(details.localPosition.dy);
          if (date != null) {
            widget.controller.jumpToDate(date);
          }
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              children: List<Widget>.generate(widget.buckets.length, (index) {
                final itemHeight = widget.heights[index];
                final isShowYear = widget.showYear[index];

                return SizedBox(
                  height: itemHeight,
                  width: double.infinity,
                  child: Align(
                    alignment: Alignment.center,
                    child: !isShowYear && itemHeight >= 3
                        ? Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                          )
                        : null,
                  ),
                );
              }),
            ),
            ...yearLabels,
            if (_cursorTop != null)
              Positioned(
                top: _cursorTop! - 15,
                right: 35,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _cursorDate,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.arrow_right,
                        color: Colors.white,
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    final enableHover =
        DeviceUtils.isDesktop ||
        (DeviceUtils.isWeb && DeviceUtils.isDesktopLayout(context));
    if (enableHover) {
      content = MouseRegion(
        onEnter: (_) => widget.controller.keepTimelineVisible(),
        onHover: (event) => _updateCursor(event.localPosition.dy),
        onExit: (_) => _clearCursor(),
        child: content,
      );
    }
    return content;
  }
}

class _TimelineBucket {
  final String representativeDate;
  final int year;
  final int count;

  const _TimelineBucket({
    required this.representativeDate,
    required this.year,
    required this.count,
  });

  static _TimelineBucket? fromDate(String dateStr, int count) {
    try {
      final date = DateTime.parse(dateStr);
      return _TimelineBucket(
        representativeDate: dateStr,
        year: date.year,
        count: count,
      );
    } catch (_) {
      return null;
    }
  }
}
