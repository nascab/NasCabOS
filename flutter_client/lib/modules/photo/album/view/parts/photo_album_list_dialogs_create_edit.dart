part of '../photo_album_list_view.dart';

Future<void> _showCreateDialog(
  BuildContext context,
  PhotoAlbumController controller,
) async {
  await showPhotoAlbumCreateDialog(context, controller);
}

Future<void> _showEditDialog(
  BuildContext context,
  PhotoAlbumController controller,
  PhotoAlbumItem album,
) async {
  await showPhotoAlbumEditDialog(context, controller, album);
}
