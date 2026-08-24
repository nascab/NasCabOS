part of '../audio_trans_view.dart';

class _AudioTransTaskCard extends StatelessWidget {
  final AudioTransController ctrl;
  final Map<String, dynamic> item;

  const _AudioTransTaskCard({required this.ctrl, required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final id = int.tryParse(item['id']?.toString() ?? '') ?? 0;
    final status = item['status']?.toString().trim().toLowerCase() ?? 'stopped';
    final sourcePath = item['source_path']?.toString() ?? '';
    final targetPath = item['target_path']?.toString() ?? '';
    final nonAudioPolicy = item['non_audio_policy']?.toString() ?? 'skip';

    final config = _parseConfig(item['trans_config']);
    final outFormat = config['out_format']?.toString() ?? 'mp3';
    final sampleRate = config['sample_rate']?.toString() ?? 'source';
    final channels = config['channels']?.toString() ?? 'source';

    final totalFiles = int.tryParse(item['total_files']?.toString() ?? '') ?? 0;
    final doneFiles = int.tryParse(item['done_files']?.toString() ?? '') ?? 0;
    final lastError = item['last_error']?.toString() ?? '';
    final lastErrorDisplay = _lastErrorDisplayText(lastError);

    final opLoading = ctrl.opLoadingById[id] == true;

    final canStop = status == 'running';
    final canStart = status != 'running';
    final canEdit = status != 'running' && !opLoading;

    final ab = config['audio_bitrate_kbps'];
    final threadCount = int.tryParse(config['thread_count']?.toString() ?? '');

    final runtimeProgress = item['progress']?.toString().trim() ?? '';
    final baseProgress = totalFiles > 0 ? '$doneFiles/$totalFiles' : '';
    final progressText = runtimeProgress.isEmpty
        ? (baseProgress.isEmpty ? '-' : baseProgress)
        : RegExp(r'^\d+/\d+$').hasMatch(runtimeProgress)
        ? runtimeProgress
        : (baseProgress.isEmpty
              ? runtimeProgress
              : '$baseProgress · $runtimeProgress');

    final accentColor = _statusColor(theme, status);

    String bitrateText(dynamic v) {
      if (v == null) return 'auto'.tr;
      final n = num.tryParse(v.toString());
      if (n == null || n <= 0) return 'auto'.tr;
      final asInt = n % 1 == 0 ? n.toInt().toString() : n.toString();
      return '$asInt Kbps';
    }

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

    return CustomGlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '#$id · ${_formatText(outFormat)}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  _statusText(status),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            pathRow(
              label: 'media_tool_audio_trans_source'.tr,
              value: sourcePath,
            ),
            const SizedBox(height: 6),
            pathRow(
              label: 'media_tool_audio_trans_target'.tr,
              value: targetPath,
            ),
            const SizedBox(height: 8),
            _KeyValueRow(
              label: 'media_tool_audio_trans_sample_rate'.tr,
              value: _sampleRateText(sampleRate),
              selectable: false,
            ),
            const SizedBox(height: 6),
            _KeyValueRow(
              label: 'media_tool_audio_trans_channels'.tr,
              value: _channelsText(channels),
              selectable: false,
            ),
            const SizedBox(height: 6),
            _KeyValueRow(
              label: 'media_tool_audio_trans_audio_bitrate'.tr,
              value: bitrateText(ab),
              selectable: false,
            ),
            const SizedBox(height: 6),
            _KeyValueRow(
              label: 'media_tool_audio_trans_thread_count'.tr,
              value: threadCount == null || threadCount <= 0
                  ? '-'
                  : threadCount.toString(),
              selectable: false,
            ),
            const SizedBox(height: 6),
            _KeyValueRow(
              label: 'media_tool_audio_trans_non_audio'.tr,
              value: _nonAudioText(nonAudioPolicy),
              selectable: false,
            ),
            const SizedBox(height: 6),
            _KeyValueRow(
              label: 'media_tool_audio_trans_progress'.tr,
              value: progressText,
              selectable: false,
            ),
            if (lastError.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              _KeyValueRow(
                label: 'media_tool_audio_trans_last_error'.tr,
                value: lastErrorDisplay,
                selectable: false,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                valueStyle: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                onTap: () => _showTextDialog(
                  context,
                  'media_tool_audio_trans_last_error'.tr,
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
                            builder: (_) => _AudioTransDialog(
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
          ],
        ),
    );
  }
}
