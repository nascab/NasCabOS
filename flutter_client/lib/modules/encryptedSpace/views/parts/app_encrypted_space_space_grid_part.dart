part of '../encrypted_space_view.dart';

class AppEncryptedSpaceSpaceGrid extends StatelessWidget {
  const AppEncryptedSpaceSpaceGrid({
    super.key,
    required this.ctrl,
    required this.onOpen,
  });

  final EncryptedSpaceController ctrl;
  final void Function(Map<String, dynamic> space) onOpen;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (ctrl.isLoading.value && ctrl.spaces.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (ctrl.errorText.value.isNotEmpty) {
        return Center(child: Text(ctrl.errorText.value));
      }
      if (ctrl.spaces.isEmpty) {
        return const CustomNoData();
      }

      return LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          const desiredWidth = 320.0;
          final crossAxisCount = (maxWidth / desiredWidth).floor().clamp(1, 4);
          const spacing = 12.0;
          final totalSpacing = spacing * (crossAxisCount - 1);
          final itemWidth = ((maxWidth - totalSpacing) / crossAxisCount)
              .floorToDouble();
          const estimatedHeight = 190.0;
          final aspectRatio = itemWidth / estimatedHeight;

          return RefreshIndicator(
            onRefresh: () => ctrl.refreshList(showLoading: false),
            child: GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              itemCount: ctrl.spaces.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: spacing,
                crossAxisSpacing: spacing,
                childAspectRatio: aspectRatio,
              ),
              itemBuilder: (context, i) {
                final item = ctrl.spaces[i];
                return AppEncryptedSpaceGridCard(
                  key: ValueKey('app_encrypted_space_${item['id'] ?? i}'),
                  item: item,
                  onOpen: () => onOpen(item),
                  onExport: () => ctrl.exportSpaceFlow(context, item),
                  onRename: () => ctrl.renameSpaceFlow(item),
                  onDelete: () => ctrl.deleteSpaceFlow(item),
                );
              },
            ),
          );
        },
      );
    });
  }
}

class AppEncryptedSpaceGridCard extends StatelessWidget {
  const AppEncryptedSpaceGridCard({
    super.key,
    required this.item,
    required this.onOpen,
    required this.onExport,
    required this.onRename,
    required this.onDelete,
  });

  final Map<String, dynamic> item;
  final VoidCallback onOpen;
  final VoidCallback onExport;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (item['space_name'] ?? '').toString().trim();
    final id = int.tryParse('${item['id'] ?? ''}') ?? 0;

    final headerLeft = Row(
      children: [
        Flexible(
          child: Text(
            name.isEmpty ? 'name'.tr : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.white,
              shadows: [
                Shadow(
                  blurRadius: 6,
                  color: Colors.black54,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    final headerRight = IconButton(
      tooltip: 'more'.tr,
      onPressed: () {
        AppItemActionSheet.show(
          context,
          headerLeading: CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            child: const Icon(Icons.lock_outline),
          ),
          headerTitle: name.isNotEmpty ? name : 'name'.tr,
          headerSubtitle: id > 0 ? '#$id' : null,
          entries: [
            AppItemActionSheetAction(
              title: 'open'.tr,
              icon: const Icon(Icons.folder_open_outlined),
              onTap: onOpen,
            ),
            const AppItemActionSheetDivider(),
            AppItemActionSheetAction(
              title: 'encrypted_space_export'.tr,
              icon: const Icon(Icons.file_download_outlined),
              onTap: onExport,
            ),
            const AppItemActionSheetDivider(),
            AppItemActionSheetAction(
              title: 'rename'.tr,
              icon: const Icon(Icons.edit_outlined),
              onTap: onRename,
            ),
            const AppItemActionSheetDivider(),
            AppItemActionSheetAction(
              title: 'delete'.tr,
              titleColor: Colors.red,
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onTap: onDelete,
            ),
          ],
        );
      },
      icon: const Icon(Icons.more_vert, color: Colors.white),
    );

    final preview = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.secondaryContainer,
          ],
        ),
      ),
      child: const Center(
        child: Icon(Icons.lock_outline, size: 66, color: Colors.white),
      ),
    );

    return CustomAlbum(
      preview: preview,
      onTap: onOpen,
      headerLeft: headerLeft,
      headerRight: headerRight,
      headerHeight: 50,
      headerPosition: CustomAlbumHeaderPosition.bottom,
      hoverEnabled: false,
    );
  }
}
