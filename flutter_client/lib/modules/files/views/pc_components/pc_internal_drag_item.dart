import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/pc_file_explorer_controller.dart';

/// PC 文件列表内部拖放（移动到文件夹）的拖拽数据
class PcInternalFileDragData {
  PcInternalFileDragData(this.paths);
  final List<String> paths;
}

/// 进程内全局拖拽态（用于临时屏蔽顶部 hover 菜单等）
class PcInternalDragSession {
  static final RxInt _activeDragCount = 0.obs;
  static bool get isDragging => _activeDragCount.value > 0;

  static void begin() {
    _activeDragCount.value += 1;
  }

  static void end() {
    if (_activeDragCount.value <= 0) {
      _activeDragCount.value = 0;
      return;
    }
    _activeDragCount.value -= 1;
  }
}

bool pcFileItemAllowsInternalDrag(Map<String, dynamic> item) {
  final vt = item['virtualType']?.toString() ?? '';
  if (vt == 'custom_add') return false;
  final path = item['path']?.toString() ?? '';
  return path.isNotEmpty;
}

bool pcFileItemIsDirectoryDropTarget(Map<String, dynamic> item) {
  if (!pcFileItemAllowsInternalDrag(item)) return false;
  return item['type']?.toString() == 'dir';
}

/// 仅图标区域可发起拖动，避免占用整条目导致难以框选
class PcInternalIconDragHandle extends StatelessWidget {
  const PcInternalIconDragHandle({
    super.key,
    required this.ctrl,
    required this.item,
    required this.child,
  });

  final PcFileExplorerController ctrl;
  final Map<String, dynamic> item;
  final Widget child;

  List<String> _pathsToDrag() {
    final filePath = item['path']?.toString() ?? '';
    if (filePath.isEmpty) return const [];
    if (ctrl.selected.contains(filePath) && ctrl.selected.isNotEmpty) {
      return ctrl.selected.toList();
    }
    return [filePath];
  }

  @override
  Widget build(BuildContext context) {
    if (!pcFileItemAllowsInternalDrag(item)) return child;

    return Obx(() {
      final paths = _pathsToDrag();
      if (paths.isEmpty) return child;

      final data = PcInternalFileDragData(paths);
      final theme = Theme.of(context);

      return Draggable<PcInternalFileDragData>(
        data: data,
        maxSimultaneousDrags: 1,
        onDragStarted: PcInternalDragSession.begin,
        onDragEnd: (_) => PcInternalDragSession.end(),
        feedback: Material(
          color: Colors.transparent,
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: Opacity(
            opacity: 0.82,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        paths.length > 1
                            ? Icons.layers_outlined
                            : Icons.label_outline,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          paths.length > 1
                              ? 'items_selected'.trParams({
                                  'count': paths.length.toString(),
                                })
                              : (item['name']?.toString() ?? ''),
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.45,
          child: child,
        ),
        child: child,
      );
    });
  }
}

/// 文件夹整行作为拖入目标；非文件夹则直接展示 [child]
class PcInternalFolderDropTarget extends StatelessWidget {
  const PcInternalFolderDropTarget({
    super.key,
    required this.ctrl,
    required this.item,
    required this.overlayBorderRadius,
    required this.child,
    /// 列表模式：将「移动」提示放在行左侧（与图标列对齐），更易辨认
    this.alignDropHintToListIconLeading = false,
  });

  final PcFileExplorerController ctrl;
  final Map<String, dynamic> item;
  final BorderRadius overlayBorderRadius;
  final Widget child;
  final bool alignDropHintToListIconLeading;

  static const Color _dropHintTextColor = Color(0xFFE8E8E8);

  @override
  Widget build(BuildContext context) {
    if (!pcFileItemIsDirectoryDropTarget(item)) return child;

    final filePath = item['path']?.toString() ?? '';
    if (filePath.isEmpty) return child;

    final theme = Theme.of(context);

    return DragTarget<PcInternalFileDragData>(
      onWillAcceptWithDetails: (details) {
        return ctrl.canAcceptInternalFileDrop(details.data.paths, filePath);
      },
      onAcceptWithDetails: (details) async {
        await ctrl.moveEntriesToFolderImmediate(
          details.data.paths,
          filePath,
        );
      },
      builder: (context, candidateData, _) {
        final showDrop = candidateData.isNotEmpty;
        // 必须保留至少一个非 Positioned 子节点以确定 Stack 尺寸；ListView 子项常带 maxH=Infinity，
        // 若全部为 Positioned.fill 会导致「无法布局」。
        return Stack(
          clipBehavior: Clip.hardEdge,
          fit: StackFit.passthrough,
          children: [
            child,
            if (showDrop)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: overlayBorderRadius,
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      border: Border.all(
                        color: theme.colorScheme.primary,
                        width: 2,
                      ),
                    ),
                    child: alignDropHintToListIconLeading
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 12),
                              child: Material(
                                color: theme.colorScheme.primaryContainer
                                    .withValues(alpha: 0.68),
                                borderRadius: BorderRadius.circular(6),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    'move'.tr,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: _dropHintTextColor,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Material(
                              color: theme.colorScheme.primaryContainer
                                  .withValues(alpha: 0.68),
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                child: Text(
                                  'move'.tr,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: _dropHintTextColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 当前目录路径作为拖入目标（多窗口，normal 且非根目录）
class PcInternalCurrentDirectoryDropTarget extends StatelessWidget {
  const PcInternalCurrentDirectoryDropTarget({
    super.key,
    required this.ctrl,
    required this.child,
  });

  final PcFileExplorerController ctrl;
  final Widget child;

  static const Color _hintColor = Color(0xFFE8E8E8);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final path = ctrl.currentPath.value?.trim() ?? '';
      if (path.isEmpty ||
          ctrl.currentModule.value != 'normal' ||
          ctrl.isRoot) {
        return child;
      }

      return DragTarget<PcInternalFileDragData>(
        onWillAcceptWithDetails: (details) {
          return ctrl.canAcceptInternalFileDrop(details.data.paths, path);
        },
        onAcceptWithDetails: (details) async {
          await ctrl.moveEntriesToFolderImmediate(
            details.data.paths,
            path,
          );
        },
        builder: (context, candidateData, _) {
          final showDrop = candidateData.isNotEmpty;
          return Stack(
            clipBehavior: Clip.hardEdge,
            fit: StackFit.passthrough,
            children: [
              child,
              if (showDrop)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        border: Border.all(
                          color: theme.colorScheme.primary,
                          width: 1.5,
                        ),
                      ),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Material(
                            color: theme.colorScheme.primaryContainer
                                .withValues(alpha: 0.68),
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: Text(
                                'move'.tr,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: _hintColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );
    });
  }
}

/// 面包屑某一段路径作为拖入目标（包裹原有的 [TextButton] 等）
class PcInternalPathSegmentDropTarget extends StatelessWidget {
  const PcInternalPathSegmentDropTarget({
    super.key,
    required this.ctrl,
    required this.segmentPath,
    required this.child,
  });

  final PcFileExplorerController ctrl;
  final String segmentPath;
  final Widget child;

  static const Color _hintColor = Color(0xFFE8E8E8);

  @override
  Widget build(BuildContext context) {
    final path = segmentPath.trim().replaceAll('\\', '/');
    if (path.isEmpty) return child;

    final theme = Theme.of(context);

    return DragTarget<PcInternalFileDragData>(
      onWillAcceptWithDetails: (details) {
        return ctrl.canAcceptInternalFileDrop(details.data.paths, path);
      },
      onAcceptWithDetails: (details) async {
        await ctrl.moveEntriesToFolderImmediate(
          details.data.paths,
          path,
        );
      },
      builder: (context, candidateData, _) {
        final showDrop = candidateData.isNotEmpty;
        return Stack(
          clipBehavior: Clip.hardEdge,
          fit: StackFit.passthrough,
          children: [
            child,
            if (showDrop)
              Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: Alignment.center,
                    child: Material(
                      elevation: 2,
                    color: theme.colorScheme.primaryContainer
                        .withValues(alpha: 0.68),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          'move'.tr,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: _hintColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
