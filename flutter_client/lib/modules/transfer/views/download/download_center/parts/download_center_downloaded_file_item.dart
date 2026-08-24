part of '../app_download_center_view.dart';

class _DownloadCenterDownloadedFileItem extends StatelessWidget {
  final DownloadedFileEntry entry;

  const _DownloadCenterDownloadedFileItem({required this.entry});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AppDownloadCenterController>();
    final theme = Theme.of(context);
    final missingColor = theme.colorScheme.error;

    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: entry.fileMissing
            ? null
            : () => controller.shareFile(context, entry),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              _DownloadCenterFileThumb(entry: entry),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (entry.fileMissing) ...[
                      const SizedBox(height: 4),
                      Text(
                        'download_record_file_deleted'.tr,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: missingColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      entry.remotePath,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.65,
                        ),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          entry.sizeText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.8,
                            ),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            entry.mtimeText,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              CustomBorderedIconButton(
                tooltip: 'delete'.tr,
                onTap: () async {
                  await controller.promptDeleteEntry(entry);
                },
                icon: Icons.delete_outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadCenterFileThumb extends StatelessWidget {
  final DownloadedFileEntry entry;

  const _DownloadCenterFileThumb({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(12);
    final bg = theme.colorScheme.surfaceContainerHighest;

    if (entry.fileMissing) {
      return ClipRRect(
        borderRadius: radius,
        child: Container(
          width: 56,
          height: 56,
          color: bg,
          child: Icon(
            Icons.insert_drive_file_outlined,
            color: theme.colorScheme.error.withValues(alpha: 0.8),
          ),
        ),
      );
    }

    Widget child;
    if (entry.isImage) {
      child = Image.file(
        File(entry.path),
        fit: BoxFit.cover,
        cacheWidth: 220,
        errorBuilder: (_, _, _) => const Icon(Icons.image_outlined),
      );
    } else if (entry.isVideo) {
      final controller = Get.find<AppDownloadCenterController>();
      child = FutureBuilder<File?>(
        future: controller.getVideoThumbFile(entry),
        builder: (context, snapshot) {
          final thumbFile = snapshot.data;
          if (thumbFile != null) {
            return Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  thumbFile,
                  fit: BoxFit.cover,
                  cacheWidth: 220,
                  errorBuilder: (_, _, _) => const Icon(Icons.movie_outlined),
                ),
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ],
            );
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              Container(color: bg, child: const Icon(Icons.movie_outlined)),
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          );
        },
      );
    } else {
      child = const Icon(Icons.insert_drive_file_outlined);
    }

    return ClipRRect(
      borderRadius: radius,
      child: Container(width: 56, height: 56, color: bg, child: child),
    );
  }
}
