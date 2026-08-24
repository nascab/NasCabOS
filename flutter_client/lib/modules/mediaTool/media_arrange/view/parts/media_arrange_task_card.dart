part of '../media_arrange_view.dart';

class _MediaArrangeTaskCard extends StatelessWidget {
  final MediaArrangeController ctrl;
  final Map<String, dynamic> item;

  const _MediaArrangeTaskCard({required this.ctrl, required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final id = int.tryParse(item['id']?.toString() ?? '') ?? 0;
    final status = item['status']?.toString().trim().toLowerCase() ?? 'stopped';
    final sourcePath = item['source_path']?.toString() ?? '';
    final targetPath = item['target_path']?.toString() ?? '';
    final arrangeType = item['arrange_type']?.toString() ?? 'day';

    final totalFiles = int.tryParse(item['total_files']?.toString() ?? '') ?? 0;
    final doneFiles = int.tryParse(item['done_files']?.toString() ?? '') ?? 0;
    final lastError = item['last_error']?.toString() ?? '';
    final lastErrorDisplay = _lastErrorDisplayText(lastError);

    final opLoading = ctrl.opLoadingById[id] == true;

    final canStop = status == 'running';
    final canStart = status != 'running';
    final canEdit = status != 'running' && !opLoading;

    Widget pathRow({required String label, required String value}) {
      final text = value.trim().isEmpty ? '-' : value.trim();
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (text != '-') ...[
                  InkWell(
                    onTap: () => _openPathInFileBrowser(text),
                    child: Text(
                      '[${'perm_view'.tr}]',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final runtimeProgress = item['progress']?.toString().trim() ?? '';
    final baseProgress = totalFiles > 0 ? '$doneFiles/$totalFiles' : '';
    final progressText = runtimeProgress.isEmpty
        ? (baseProgress.isEmpty ? '-' : baseProgress)
        : RegExp(r'^\d+/\d+$').hasMatch(runtimeProgress)
        ? runtimeProgress
        : (baseProgress.isEmpty
              ? runtimeProgress
              : '$baseProgress · $runtimeProgress');

    return CustomGlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '#$id · ${_arrangeTypeText(arrangeType)}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                _statusText(status),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _statusColor(theme, status),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          pathRow(label: 'media_tool_arrange_source'.tr, value: sourcePath),
          const SizedBox(height: 6),
          pathRow(label: 'media_tool_arrange_target'.tr, value: targetPath),
          const SizedBox(height: 6),
          _KeyValueRow(
            label: 'media_tool_arrange_progress'.tr,
            value: progressText,
            selectable: true,
          ),
          if (lastErrorDisplay.isNotEmpty) ...[
            const SizedBox(height: 6),
            _KeyValueRow(
              label: 'media_tool_arrange_last_error'.tr,
              value: lastErrorDisplay,
              selectable: false,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              valueStyle: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
              onTap: () {
                DialogUtil.showInfoDialog(
                  title: 'media_tool_arrange_last_error'.tr,
                  content: lastErrorDisplay,
                );
              },
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              CustomButton(
                text: canStop
                    ? 'media_tool_arrange_stop'.tr
                    : 'media_tool_arrange_start'.tr,
                onPressed: opLoading
                    ? null
                    : () {
                        if (canStop) {
                          ctrl.stop(id: id);
                        } else if (canStart) {
                          ctrl.start(id: id);
                        }
                      },
                isDisabled: opLoading,
                icon: opLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        canStop
                            ? Icons.stop_circle_outlined
                            : Icons.play_circle_outline,
                      ),
              ),
              const SizedBox(width: 8),
              CustomButton(
                text: 'edit'.tr,
                onPressed: canEdit
                    ? () async {
                        await showDialog<bool>(
                          context: context,
                          builder: (_) =>
                              _MediaArrangeDialog(ctrl: ctrl, initial: item),
                        );
                        ctrl.refreshList(
                          showLoading: false,
                          clearOnFail: false,
                          waitIfBusy: true,
                        );
                      }
                    : null,
                isPrimary: false,
                isDisabled: !canEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              const SizedBox(width: 8),
              CustomButton(
                text: 'delete'.tr,
                onPressed: id > 0 && status != 'running' && !opLoading
                    ? () => ctrl.remove(id: id)
                    : null,
                isPrimary: false,
                isDisabled: id <= 0 || status == 'running' || opLoading,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
