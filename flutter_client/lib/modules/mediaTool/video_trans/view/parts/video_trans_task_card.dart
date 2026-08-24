part of '../video_trans_view.dart';

class _VideoTransTaskCard extends StatelessWidget {
  final VideoTransController ctrl;
  final Map<String, dynamic> item;

  const _VideoTransTaskCard({required this.ctrl, required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final id = int.tryParse(item['id']?.toString() ?? '') ?? 0;
    final status = item['status']?.toString().trim().toLowerCase() ?? 'stopped';
    final sourcePath = item['source_path']?.toString() ?? '';
    final targetPath = item['target_path']?.toString() ?? '';
    final nonVideoPolicy = item['non_video_policy']?.toString() ?? 'skip';

    final config = _parseConfig(item['trans_config']);
    final outFormat = config['out_format']?.toString() ?? 'mp4';
    final vcodec = config['vcodec']?.toString() ?? 'h264';
    final resolution = config['resolution']?.toString() ?? 'source';
    final isAnimated = ['gif', 'webp'].contains(outFormat.trim().toLowerCase());

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

    String bitrateText(
      dynamic v, {
      required String unit,
      required String autoKey,
    }) {
      if (v == null) return autoKey.tr;
      final n = num.tryParse(v.toString());
      if (n == null || n <= 0) return autoKey.tr;
      final asInt = n % 1 == 0 ? n.toInt().toString() : n.toString();
      return '$asInt $unit';
    }

    String fpsText(dynamic v) {
      if (v == null) return 'auto'.tr;
      final n = num.tryParse(v.toString());
      if (n == null || n <= 0) return 'auto'.tr;
      final asInt = n % 1 == 0 ? n.toInt().toString() : n.toString();
      return asInt;
    }

    String resolutionText(String v) {
      final s = v.trim().toLowerCase();
      if (s == '8k') return 'media_tool_video_trans_resolution_8k'.tr;
      if (s == '4k') return 'media_tool_video_trans_resolution_4k'.tr;
      if (s == '1080p') return 'media_tool_video_trans_resolution_1080p'.tr;
      if (s == '720p') return 'media_tool_video_trans_resolution_720p'.tr;
      if (s == '480p') return 'media_tool_video_trans_resolution_480p'.tr;
      if (s == '320p') return 'media_tool_video_trans_resolution_320p'.tr;
      if (s == '240p') return 'media_tool_video_trans_resolution_240p'.tr;
      return 'media_tool_video_trans_resolution_source'.tr;
    }

    final vb = config['video_bitrate_mbps'];
    final ab = config['audio_bitrate_kbps'];
    final fps = config['fps'];
    final audioFormat = config['acodec']?.toString() ?? 'aac';
    final threadCount = int.tryParse(config['thread_count']?.toString() ?? '');
    final enableHwAccelRaw = config['enable_hw_accel'];
    final enableHwAccel = enableHwAccelRaw is bool
        ? enableHwAccelRaw
        : enableHwAccelRaw?.toString().trim().toLowerCase() != 'false';

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
                    isAnimated
                        ? '#$id · ${_formatText(outFormat)} · ${resolutionText(resolution)}'
                        : '#$id · ${_formatText(outFormat)} · ${_formatText(vcodec)} · ${resolutionText(resolution)}',
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
            pathRow(
              label: 'media_tool_video_trans_source'.tr,
              value: sourcePath,
            ),
            const SizedBox(height: 6),
            pathRow(
              label: 'media_tool_video_trans_target'.tr,
              value: targetPath,
            ),
            const SizedBox(height: 6),
            if (!isAnimated) ...[
              _KeyValueRow(
                label: 'media_tool_video_trans_video_bitrate'.tr,
                value: bitrateText(
                  vb,
                  unit: 'Mbps',
                  autoKey: 'auto',
                ),
                selectable: false,
              ),
              const SizedBox(height: 6),
              _KeyValueRow(
                label: 'media_tool_video_trans_audio_bitrate'.tr,
                value: bitrateText(
                  ab,
                  unit: 'Kbps',
                  autoKey: 'auto',
                ),
                selectable: false,
              ),
              const SizedBox(height: 6),
            ],
            if (!isAnimated) ...[
              _KeyValueRow(
                label: 'media_tool_video_trans_audio_format'.tr,
                value: _formatText(audioFormat),
                selectable: false,
              ),
              const SizedBox(height: 6),
            ],
            _KeyValueRow(
              label: 'media_tool_video_trans_fps'.tr,
              value: fpsText(fps),
              selectable: false,
            ),
            const SizedBox(height: 6),
            _KeyValueRow(
              label: 'media_tool_video_trans_enable_hw_accel'.tr,
              value: enableHwAccel
                  ? 'media_tool_video_trans_fast_start_on'.tr
                  : 'media_tool_video_trans_fast_start_off'.tr,
              selectable: false,
            ),
            const SizedBox(height: 6),
            _KeyValueRow(
              label: 'media_tool_video_trans_thread_count'.tr,
              value: threadCount == null || threadCount <= 0
                  ? '-'
                  : threadCount.toString(),
              selectable: false,
            ),
            const SizedBox(height: 6),
            _KeyValueRow(
              label: 'media_tool_video_trans_non_video'.tr,
              value: _nonVideoText(nonVideoPolicy),
              selectable: false,
            ),
            const SizedBox(height: 6),
            _KeyValueRow(
              label: 'media_tool_video_trans_progress'.tr,
              value: progressText,
              selectable: false,
            ),
            if (lastError.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              _KeyValueRow(
                label: 'media_tool_video_trans_last_error'.tr,
                value: lastErrorDisplay,
                selectable: false,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                valueStyle: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                onTap: () => _showTextDialog(
                  context,
                  'media_tool_video_trans_last_error'.tr,
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
                            builder: (_) =>
                                _VideoTransDialog(ctrl: ctrl, initial: item),
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
