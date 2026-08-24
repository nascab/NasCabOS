part of '../photo_collection_list_view.dart';

Future<void> _showCreateDialog(
  BuildContext context,
  PhotoCollectionController controller,
) async {
  await showPhotoCollectionCreateDialog(context, controller);
}

Future<void> _showEditDialog(
  BuildContext context,
  PhotoCollectionController controller,
  PhotoCollectionItem collection,
) async {
  await showPhotoCollectionEditDialog(context, controller, collection);
}

/// 确认删除集合
Future<void> _confirmDelete(
  BuildContext context,
  PhotoCollectionController controller,
  PhotoCollectionItem collection,
) async {
  await confirmDeletePhotoCollection(context, controller, collection);
}
