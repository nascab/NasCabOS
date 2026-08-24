import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../base/components/custom_bordered_icon_button.dart';
import '../../../../base/components/custom_expandable_search_bar.dart';
import '../../../../../../utils/device_utils.dart';
import '../../../../../../utils/popup_menu_util.dart';
import '../../controller/album_artist_list_controller.dart';

class AppAlbumArtistListTopBar extends StatefulWidget {
  final AlbumArtistListController controller;
  const AppAlbumArtistListTopBar({super.key, required this.controller});

  @override
  State<AppAlbumArtistListTopBar> createState() =>
      _AppAlbumArtistListTopBarState();
}

class _AppAlbumArtistListTopBarState extends State<AppAlbumArtistListTopBar> {
  final _sortKey = GlobalKey();
  final _sourceKey = GlobalKey();

  AlbumArtistListController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            Expanded(
              child: _AppAlbumArtistListSearchBar(controller: controller),
            ),
            const SizedBox(width: 10),
            _buildSortButton(context, _sortKey, controller),
            const SizedBox(width: 10),
            _buildSourceButton(context, _sourceKey, controller),
          ],
        ),
      ),
    );
  }
}

class AlbumArtistListTopBar extends StatefulWidget {
  final AlbumArtistListController controller;
  const AlbumArtistListTopBar({super.key, required this.controller});

  @override
  State<AlbumArtistListTopBar> createState() => _AlbumArtistListTopBarState();
}

class _AlbumArtistListTopBarState extends State<AlbumArtistListTopBar> {
  final _sortKey = GlobalKey();
  final _sourceKey = GlobalKey();

  AlbumArtistListController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            _buildSourceButton(context, _sourceKey, controller),
            const SizedBox(width: 4),
            _buildSortButton(context, _sortKey, controller),
            const SizedBox(width: 4),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: SizedBox(
                    width: double.infinity,
                    child: AlbumArtistListSearchBar(controller: controller),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildSortButton(
  BuildContext context,
  GlobalKey sortKey,
  AlbumArtistListController controller,
) {
  return Obx(() {
    final sortBy = controller.sortBy.value;
    final sortOrder = controller.sortOrder.value;
    final isActive =
        sortBy != AlbumArtistListSortBy.count ||
        sortOrder != AlbumArtistListSortOrder.desc;
    return CustomBorderedIconButton(
      key: sortKey,
      icon: Icons.sort_by_alpha,
      tooltip: 'sort'.tr,
      active: isActive,
      onTap: () async {
        final result = await PopupMenuUtil.showBelowButton<String>(
          context: context,
          buttonKey: sortKey,
          items: _buildSortItems(controller, sortBy, sortOrder),
        );
        if (result != null) {
          final parts = result.split(':');
          if (parts.length == 2) {
            final by = _parseSortBy(parts[0]);
            final order = _parseSortOrder(parts[1]);
            if (by != null && order != null) {
              controller.setSort(by, order);
            }
          }
        }
      },
    );
  });
}

Widget _buildSourceButton(
  BuildContext context,
  GlobalKey sourceKey,
  AlbumArtistListController controller,
) {
  return Obx(() {
    final count = controller.selectedPaths.length;
    return CustomBorderedIconButton(
      key: sourceKey,
      icon: Icons.source_outlined,
      tooltip: 'source'.tr,
      active: count > 0,
      onTap: () {
        if (DeviceUtils.isMobile) {
          _openSourceSheet(context, controller);
        } else {
          PopupMenuUtil.showBelowButton<void>(
            context: context,
            buttonKey: sourceKey,
            items: [
              PopupMenuItem(
                enabled: false,
                padding: EdgeInsets.zero,
                child: SizedBox(
                  width: 350,
                  child: AlbumArtistListSourcePanel(controller: controller),
                ),
              ),
            ],
          );
        }
      },
    );
  });
}

Future<void> _openSourceSheet(
  BuildContext context,
  AlbumArtistListController controller,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      return DraggableScrollableSheet(
        initialChildSize: 0.45,
        minChildSize: 0.25,
        maxChildSize: 0.75,
        expand: false,
        builder: (context, scrollController) {
          return Material(
            color: Theme.of(context).colorScheme.surface,
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: AlbumArtistListSourcePanel(controller: controller),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

AlbumArtistListSortBy? _parseSortBy(String s) {
  switch (s) {
    case 'count':
      return AlbumArtistListSortBy.count;
    case 'name':
      return AlbumArtistListSortBy.name;
    default:
      return null;
  }
}

AlbumArtistListSortOrder? _parseSortOrder(String s) {
  if (s == 'asc') return AlbumArtistListSortOrder.asc;
  if (s == 'desc') return AlbumArtistListSortOrder.desc;
  return null;
}

IconData _sortByIcon(AlbumArtistListSortBy by) {
  switch (by) {
    case AlbumArtistListSortBy.count:
      return Icons.tag;
    case AlbumArtistListSortBy.name:
      return Icons.sort_by_alpha;
  }
}

List<PopupMenuEntry<String>> _buildSortItems(
  AlbumArtistListController controller,
  AlbumArtistListSortBy currentBy,
  AlbumArtistListSortOrder currentOrder,
) {
  final items = <PopupMenuEntry<String>>[];

  void addItem(
    AlbumArtistListSortBy by,
    AlbumArtistListSortOrder order,
    String label,
  ) {
    final selected = by == currentBy && order == currentOrder;
    items.add(
      PopupMenuItem<String>(
        value: '${by.name}:${order.name}',
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: selected ? const Icon(Icons.check, size: 18) : null,
            ),
            Icon(_sortByIcon(by), size: 18),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      ),
    );
  }

  addItem(
    AlbumArtistListSortBy.count,
    AlbumArtistListSortOrder.desc,
    'music_key_list_sort_count_desc'.tr,
  );
  addItem(
    AlbumArtistListSortBy.count,
    AlbumArtistListSortOrder.asc,
    'music_key_list_sort_count_asc'.tr,
  );

  items.add(const PopupMenuDivider());

  addItem(
    AlbumArtistListSortBy.name,
    AlbumArtistListSortOrder.asc,
    'name_asc'.tr,
  );
  addItem(
    AlbumArtistListSortBy.name,
    AlbumArtistListSortOrder.desc,
    'name_desc'.tr,
  );

  return items;
}

class AlbumArtistListSourcePanel extends StatelessWidget {
  final AlbumArtistListController controller;
  const AlbumArtistListSourcePanel({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 500),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('source'.tr, style: Get.textTheme.titleSmall),
                TextButton(
                  onPressed: () {
                    controller.selectedPaths.clear();
                    controller.refreshList(showLoading: false);
                  },
                  child: Text('reset'.tr),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 150,
            child: Obx(() {
              if (controller.availablePaths.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('no_path'.tr),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: controller.availablePaths.length,
                itemBuilder: (context, idx) {
                  final p = controller.availablePaths[idx];
                  final selected = controller.selectedPaths.contains(p.path);
                  return CheckboxListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: selected,
                    onChanged: (v) {
                      if (v == true) {
                        if (!controller.selectedPaths.contains(p.path)) {
                          controller.selectedPaths.add(p.path);
                        }
                      } else {
                        controller.selectedPaths.remove(p.path);
                      }
                      controller.refreshList(showLoading: false);
                    },
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(p.path, style: Get.textTheme.bodySmall),
                        ),
                        if (p.valid)
                          const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 16,
                          )
                        else
                          const Icon(Icons.cancel, color: Colors.red, size: 16),
                      ],
                    ),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}

class AlbumArtistListSearchBar extends StatefulWidget {
  final AlbumArtistListController controller;
  const AlbumArtistListSearchBar({super.key, required this.controller});

  @override
  State<AlbumArtistListSearchBar> createState() =>
      _AlbumArtistListSearchBarState();
}

class _AlbumArtistListSearchBarState extends State<AlbumArtistListSearchBar> {
  late final TextEditingController _ctrl;
  late final Worker _syncWorker;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.controller.searchText.value);
    _syncWorker = ever<String>(widget.controller.searchText, (v) {
      if (!mounted) return;
      if (_ctrl.text == v) return;
      _ctrl.value = _ctrl.value.copyWith(
        text: v,
        selection: TextSelection.collapsed(offset: v.length),
        composing: TextRange.empty,
      );
    });
  }

  @override
  void dispose() {
    _syncWorker.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.controller.keyType.trim().toLowerCase();
    final hintKey = type == 'artist'
        ? 'music_artist_list_search_hint'
        : 'music_album_list_search_hint';
    return CustomExpandableSearchBar(
      controller: _ctrl,
      hintText: hintKey.tr,
      onChanged: widget.controller.onSearchChanged,
      onClear: widget.controller.clearSearch,
    );
  }
}

class _AppAlbumArtistListSearchBar extends StatefulWidget {
  final AlbumArtistListController controller;
  const _AppAlbumArtistListSearchBar({required this.controller});

  @override
  State<_AppAlbumArtistListSearchBar> createState() =>
      _AppAlbumArtistListSearchBarState();
}

class _AppAlbumArtistListSearchBarState
    extends State<_AppAlbumArtistListSearchBar> {
  late final TextEditingController _ctrl;
  late final Worker _syncWorker;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.controller.searchText.value);
    _syncWorker = ever<String>(widget.controller.searchText, (v) {
      if (!mounted) return;
      if (_ctrl.text == v) return;
      _ctrl.value = _ctrl.value.copyWith(
        text: v,
        selection: TextSelection.collapsed(offset: v.length),
        composing: TextRange.empty,
      );
    });
  }

  @override
  void dispose() {
    _syncWorker.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.controller.keyType.trim().toLowerCase();
    final hintKey = type == 'artist'
        ? 'music_artist_list_search_hint'
        : 'music_album_list_search_hint';
    return CustomExpandableSearchBar(
      controller: _ctrl,
      hintText: hintKey.tr,
      onChanged: widget.controller.onSearchChanged,
      onClear: widget.controller.clearSearch,
      defaultExpanded: true,
    );
  }
}
