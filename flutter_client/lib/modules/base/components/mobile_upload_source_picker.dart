import 'package:flutter/material.dart';
import 'package:get/get.dart';

enum MobileUploadSourceType { media, files }

Future<MobileUploadSourceType?> showMobileUploadSourcePicker(
  BuildContext context,
) {
  final theme = Theme.of(context);
  return showModalBottomSheet<MobileUploadSourceType>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.photo_library_outlined,
                color: theme.colorScheme.primary,
              ),
              title: Text('upload_center_pick_media'.tr),
              onTap: () =>
                  Navigator.of(ctx).pop(MobileUploadSourceType.media),
            ),
            ListTile(
              leading: Icon(
                Icons.upload_file,
                color: theme.colorScheme.primary,
              ),
              title: Text('folder_upload_file'.tr),
              onTap: () =>
                  Navigator.of(ctx).pop(MobileUploadSourceType.files),
            ),
            const SizedBox(height: 6),
          ],
        ),
      );
    },
  );
}
