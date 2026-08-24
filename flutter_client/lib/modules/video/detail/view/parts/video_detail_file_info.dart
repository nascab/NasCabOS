import 'package:flutter/material.dart';
import '../../controller/video_detail_controller.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import '../../../../home/views/pc_home_controller.dart';
import '../../../../../core/routes/app_routes.dart';
import '../../../../../utils/device_utils.dart';

// 文件信息模块
class VideoDetailFileInfoSection extends StatelessWidget {
  final VideoDetailController ctrl;

  const VideoDetailFileInfoSection({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = ctrl.item;
    if (m == null) return const SizedBox.shrink();
    final filename = (m['filename']?.toString() ?? '').trim();
    final fullPath = (m['full_path']?.toString() ?? '').trim();
    final posterPath = (m['poster_path']?.toString() ?? '').trim();
    final mediaType = (m['media_type']?.toString() ?? '').trim().toLowerCase();
    final basePath = (m['path']?.toString() ?? '').trim();

    if (filename.isEmpty && fullPath.isEmpty) {
      return const SizedBox.shrink();
    }

    String resolveBrowsePath() {
      if (mediaType == 'movie' || mediaType == 'bdmv' || mediaType == 'video_ts') {
        if (fullPath.isNotEmpty) return p.dirname(fullPath);
        if (basePath.isNotEmpty && filename.isNotEmpty) {
          return p.dirname(p.join(basePath, filename));
        }
      }
      if (mediaType == 'tv' || mediaType == 'season') {
        if (fullPath.isNotEmpty) return fullPath;
      }
      if (basePath.isNotEmpty) return basePath;
      if (fullPath.isNotEmpty) return p.dirname(fullPath);
      return '';
    }

    Future<void> openFileBrowser() async {
      final target = resolveBrowsePath();
      if (target.isEmpty) return;
      if (DeviceUtils.isDesktop && Get.isRegistered<PcHomeController>()) {
        PcHomeController.instance.openFolderAt(target);
        return;
      }
      AppRoutes.toFiles(initialPath: target);
    }

    Widget row({required String label, required String value}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 56,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: IgnorePointer(
                child: SelectableText(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('fileinfo'.tr, style: theme.textTheme.titleMedium),
        const SizedBox(height: 10),
        InkWell(
          onTap: openFileBrowser,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (filename.isNotEmpty) row(label: 'name'.tr, value: filename),
                if (fullPath.isNotEmpty) row(label: 'path'.tr, value: fullPath),
                if (posterPath.isNotEmpty)
                  row(label: 'poster'.tr, value: posterPath),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
