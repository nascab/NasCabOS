import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/worker_process_item.dart';
import '../process_list_controller.dart';

/// Worker 进程列表；在 [State.dispose] 时注销 [ProcessListController]，无残留定时轮询。
class ProcessListView extends StatefulWidget {
  const ProcessListView({super.key});

  @override
  State<ProcessListView> createState() => _ProcessListViewState();
}

class _ProcessListViewState extends State<ProcessListView> {
  late final String _tag;
  late final ProcessListController _controller;

  @override
  void initState() {
    super.initState();
    _tag = 'process_list_${identityHashCode(this)}';
    _controller = Get.put(ProcessListController(), tag: _tag);
  }

  @override
  void dispose() {
    Get.delete<ProcessListController>(tag: _tag, force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ColoredBox(
      color: Colors.transparent,
      child: Obx(() {
        if (_controller.isInitialLoading.value) {
          return Center(child: CircularProgressIndicator(color: cs.primary));
        }
        // 勿在此处订阅 workers：轮询会整页重建，导致 Tooltip 无法完成悬停。
        return _ProcessListLoadedView(controller: _controller);
      }),
    );
  }
}

/// 帮助按钮与副标题的 [Obx] 并列：图标不随 workers 轮询重建，避免 Tooltip 失效。
class _ProcessListLoadedView extends StatelessWidget {
  final ProcessListController controller;

  const _ProcessListLoadedView({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'process.title'.tr,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Obx(() {
                final items = controller.workers;
                final countStr = 'process.countSummary'.trParams({
                  'count': '${items.length}',
                });
                return Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    countStr,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                );
              }),
              Obx(() {
                final err = controller.loadError.value;
                if (err == null || err.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 10),
                    Material(
                      color: cs.errorContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.cloud_off_outlined,
                              size: 18,
                              color: cs.error,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                err,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
        Expanded(
          child: Obx(() {
            final items = controller.workers;
            if (items.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.view_list_outlined,
                        size: 48,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'process.empty'.tr,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: _ProcessCard(item: items[index]),
                      );
                    }, childCount: items.length),
                  ),
                ),
              ],
            );
          }),
        ),
      ],
    );
  }
}

const _kProcessUnknownNameKey = 'process.worker.unknown.name';

String _formatProcessDisplayName(WorkerProcessItem item) {
  final base = item.nameKey.tr;
  if (item.nameKey == _kProcessUnknownNameKey) {
    final raw = item.workerPath.trim().isNotEmpty
        ? item.workerPath.trim()
        : item.role.trim();
    if (raw.isNotEmpty) {
      return '$base（$raw）';
    }
  }
  return base;
}

class _ProcessCard extends StatelessWidget {
  final WorkerProcessItem item;

  const _ProcessCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final name = _formatProcessDisplayName(item);
    final purpose = item.purposeKey.tr;

    final purposeStyle = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
      height: 1.35,
    );

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              purpose,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: purposeStyle,
            ),
          ],
        ),
      ),
    );
  }
}
