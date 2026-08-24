part of '../img_batch_compress_view.dart';

class _ImgBatchCompressTaskCard extends StatelessWidget {
  final ImgBatchCompressController ctrl;
  final Map<String, dynamic> item;

  const _ImgBatchCompressTaskCard({required this.ctrl, required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final id = int.tryParse(item['id']?.toString() ?? '') ?? 0;
    final status = item['status']?.toString().trim().toLowerCase() ?? 'stopped';
    final sourcePath = item['source_path']?.toString() ?? '';
    final targetPath = item['target_path']?.toString() ?? '';
    final outFormat = item['out_format']?.toString() ?? 'jpeg';
    final quality = int.tryParse(item['quality']?.toString() ?? '') ?? 80;
    final outSize = item['out_size'];
    final nonImagePolicy = item['non_image_policy']?.toString() ?? 'skip';
    final progress = item['progress']?.toString() ?? '';
    final lastError = item['last_error']?.toString() ?? '';
    final lastErrorDisplay = _lastErrorDisplayText(lastError);
    final totalFiles = int.tryParse(item['total_files']?.toString() ?? '') ?? 0;
    final doneFiles = int.tryParse(item['done_files']?.toString() ?? '') ?? 0;
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
                    onTap: () => _openFolderInFileBrowser(text),
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

    return CustomGlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '#$id · ${_formatText(outFormat)} · ${'media_tool_quality'.tr} ${quality.clamp(1, 100)}',
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
            pathRow(label: 'media_tool_img_batch_source'.tr, value: sourcePath),
            const SizedBox(height: 6),
            pathRow(label: 'media_tool_img_batch_target'.tr, value: targetPath),
            const SizedBox(height: 6),
            _KeyValueRow(
              label: 'media_tool_out_size'.tr,
              value: _sizeText(outSize),
            ),
            const SizedBox(height: 6),
            _KeyValueRow(
              label: 'media_tool_img_batch_non_image'.tr,
              value: _nonImageText(nonImagePolicy),
            ),
            const SizedBox(height: 6),
            _KeyValueRow(
              label: 'media_tool_img_batch_progress'.tr,
              value: totalFiles > 0
                  ? '$doneFiles/$totalFiles '
                  : (progress.trim().isEmpty ? '-' : progress.trim()),
              selectable: false,
            ),
            if (lastError.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              _KeyValueRow(
                label: 'media_tool_img_batch_last_error'.tr,
                value: lastErrorDisplay,
                selectable: false,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                valueStyle: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                onTap: () => _showTextDialog(
                  context,
                  'media_tool_img_batch_last_error'.tr,
                  lastErrorDisplay,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                CustomButton(
                  text: canStop
                      ? 'file_backup_stop'.tr
                      : 'file_backup_start'.tr,
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
                            builder: (_) => _ImgBatchCompressDialog(
                              ctrl: ctrl,
                              initial: item,
                            ),
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
                  onPressed: id > 0 ? () => ctrl.remove(id: id) : null,
                  isPrimary: false,
                  isDisabled: id <= 0,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 2),
          ],
        ),
    );
  }
}
