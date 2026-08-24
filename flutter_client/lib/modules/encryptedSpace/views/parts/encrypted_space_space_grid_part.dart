part of '../encrypted_space_view.dart';

class _EncryptedSpaceSpaceGrid extends StatelessWidget {
  final EncryptedSpaceController ctrl;
  final void Function(Map<String, dynamic> space) onOpen;

  const _EncryptedSpaceSpaceGrid({required this.ctrl, required this.onOpen});

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
          const desiredWidth = 260.0;
          final crossAxisCount = (maxWidth / desiredWidth).floor().clamp(1, 6);
          const spacing = 12.0;
          final totalSpacing = spacing * (crossAxisCount - 1);
          final itemWidth = ((maxWidth - totalSpacing) / crossAxisCount)
              .floorToDouble();
          const estimatedHeight = 200.0;
          final aspectRatio = itemWidth / estimatedHeight;

          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            itemCount: ctrl.spaces.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              childAspectRatio: aspectRatio,
            ),
            itemBuilder: (context, i) {
              final item = ctrl.spaces[i];
              return _EncryptedSpaceGridCard(
                key: ValueKey('encrypted_space_${item['id'] ?? i}'),
                item: item,
                onOpen: () => onOpen(item),
                onExport: () => ctrl.exportSpaceFlow(context, item),
                onRename: () => ctrl.renameSpaceFlow(item),
                onDelete: () => ctrl.deleteSpaceFlow(item),
              );
            },
          );
        },
      );
    });
  }
}
