part of '../photo_album_list_view.dart';

Future<void> _confirmDelete(
  BuildContext context,
  PhotoAlbumController controller,
  PhotoAlbumItem album,
) async {
  final ok = await DialogUtil.showConfirmDialog(
    title: 'need_confirm'.tr,
    content: 'photo_album_delete_confirm'.trParams({'name': album.name}),
    confirmText: 'delete'.tr,
    cancelText: 'cancel'.tr,
    barrierDismissible: true,
  );
  if (ok == true) {
    await controller.deleteAlbum(album.id);
  }
}
