import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../transfer/views/download/download_center/app_download_center_view.dart';
import '../../../../core/routes/app_routes.dart';

class AppMonitorCard extends StatelessWidget {
  const AppMonitorCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: _actionTile(
              context,
              icon: Image.asset(
                'assets/app/home/upload.png',
                width: 40,
                height: 40,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.upload_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 40,
                ),
              ),
              title: 'home_quick_upload'.tr,
              onTap: () => Get.toNamed(AppRoutes.appUploadCenter),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _actionTile(
              context,
              icon: Image.asset(
                'assets/app/home/download.png',
                width: 40,
                height: 40,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.download_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 40,
                ),
              ),
              title: 'home_download_center'.tr,
              onTap: () => Get.to(() => const AppDownloadCenterView()),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _actionTile(
              context,
              icon: Image.asset(
                'assets/app/home/album.png',
                width: 40,
                height: 40,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.photo_library_outlined,
                  color: Theme.of(context).colorScheme.primary,
                  size: 40,
                ),
              ),
              title: 'home_photo_backup'.tr,
              onTap: () => Get.toNamed(AppRoutes.appPhotoBackup),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionTile(
    BuildContext context, {
    required Widget icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 88),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 52, height: 52, child: Center(child: icon)),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
