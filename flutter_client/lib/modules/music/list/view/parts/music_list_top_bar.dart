import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../base/components/custom_bordered_icon_button.dart';
import '../../../../base/components/custom_expandable_search_bar.dart';
import '../../../../../../utils/popup_menu_util.dart';
import '../../controller/music_list_controller.dart';

class AppMusicListTopBar extends StatefulWidget {
  final MusicListController controller;
  const AppMusicListTopBar({super.key, required this.controller});

  @override
  State<AppMusicListTopBar> createState() => _AppMusicListTopBarState();
}

class _AppMusicListTopBarState extends State<AppMusicListTopBar> {
  final _sortKey = GlobalKey();
  final _sourceKey = GlobalKey();

  MusicListController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            Expanded(child: _AppMusicListSearchBar(controller: controller)),
            const SizedBox(width: 8),
            _buildSortButton(context, _sortKey, controller),
            const SizedBox(width: 8),
            _buildSourceButton(context, _sourceKey, controller, useSheet: true),
          ],
        ),
      ),
    );
  }
}

class MusicListTopBar extends StatefulWidget {
  final MusicListController controller;
  const MusicListTopBar({super.key, required this.controller});

  @override
  State<MusicListTopBar> createState() => _MusicListTopBarState();
}

class _MusicListTopBarState extends State<MusicListTopBar> {
  final _sortKey = GlobalKey();
  final _sourceKey = GlobalKey();

  MusicListController get controller => widget.controller;

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
            const SizedBox(width: 10),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: SizedBox(
                    width: double.infinity,
                    child: MusicListSearchBar(controller: controller),
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
  MusicListController controller,
) {
  return Obx(() {
    final sortBy = controller.sortBy.value;
    final sortOrder = controller.sortOrder.value;
    final isActive =
        sortBy != MusicListSortBy.mtime || sortOrder != MusicListSortOrder.desc;
    return CustomBorderedIconButton(
      key: sortKey,
      icon: Icons.sort_by_alpha,
      tooltip: 'sort'.tr,
      active: isActive,
      onTap: () async {
        final result = await PopupMenuUtil.showBelowButton<String>(
          context: context,
          buttonKey: sortKey,
          items: _buildMusicSortItems(controller, sortBy, sortOrder),
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
  MusicListController controller, {
  bool useSheet = false,
}) {
  return Obx(() {
    final count = controller.selectedPaths.length;
    return CustomBorderedIconButton(
      key: sourceKey,
      icon: Icons.source_outlined,
      tooltip: 'source'.tr,
      active: count > 0,
      onTap: () {
        if (useSheet) {
          showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            useSafeArea: true,
            builder: (ctx) {
              final theme = Theme.of(ctx);
              return Material(
                color: theme.colorScheme.surface,
                child: MusicListSourcePanel(controller: controller),
              );
            },
          );
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
                  child: MusicListSourcePanel(controller: controller),
                ),
              ),
            ],
          );
        }
      },
    );
  });
}

MusicListSortBy? _parseSortBy(String s) {
  switch (s) {
    case 'title':
      return MusicListSortBy.title;
    case 'year':
      return MusicListSortBy.year;
    case 'duration':
      return MusicListSortBy.duration;
    case 'ctime':
      return MusicListSortBy.ctime;
    case 'favoriteTime':
      return MusicListSortBy.favoriteTime;
    default:
      return null;
  }
}

MusicListSortOrder? _parseSortOrder(String s) {
  if (s == 'asc') return MusicListSortOrder.asc;
  if (s == 'desc') return MusicListSortOrder.desc;
  return null;
}

IconData _sortByIcon(MusicListSortBy by) {
  switch (by) {
    case MusicListSortBy.title:
      return Icons.sort_by_alpha_outlined;
    case MusicListSortBy.year:
      return Icons.calendar_today_outlined;
    case MusicListSortBy.duration:
      return Icons.timer_outlined;
    case MusicListSortBy.ctime:
      return Icons.access_time_outlined;
    case MusicListSortBy.favoriteTime:
      return Icons.favorite_outlined;
    default:
      return Icons.sort_by_alpha_outlined;
  }
}

List<PopupMenuEntry<String>> _buildMusicSortItems(
  MusicListController controller,
  MusicListSortBy currentBy,
  MusicListSortOrder currentOrder,
) {
  final items = <PopupMenuEntry<String>>[];

  void addItem(MusicListSortBy by, MusicListSortOrder order, String label) {
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
    MusicListSortBy.title,
    MusicListSortOrder.asc,
    'music_list_sort_title_asc'.tr,
  );
  addItem(
    MusicListSortBy.title,
    MusicListSortOrder.desc,
    'music_list_sort_title_desc'.tr,
  );

  items.add(const PopupMenuDivider());

  addItem(
    MusicListSortBy.year,
    MusicListSortOrder.desc,
    'music_list_sort_year_desc'.tr,
  );
  addItem(
    MusicListSortBy.year,
    MusicListSortOrder.asc,
    'music_list_sort_year_asc'.tr,
  );

  items.add(const PopupMenuDivider());

  addItem(
    MusicListSortBy.duration,
    MusicListSortOrder.desc,
    'music_list_sort_duration_desc'.tr,
  );
  addItem(
    MusicListSortBy.duration,
    MusicListSortOrder.asc,
    'music_list_sort_duration_asc'.tr,
  );

  items.add(const PopupMenuDivider());

  addItem(
    MusicListSortBy.ctime,
    MusicListSortOrder.desc,
    'create_time_desc'.tr,
  );
  addItem(MusicListSortBy.ctime, MusicListSortOrder.asc, 'create_time_asc'.tr);

  if (controller.isFavoriteList) {
    items.add(const PopupMenuDivider());
    addItem(
      MusicListSortBy.favoriteTime,
      MusicListSortOrder.desc,
      'music_list_sort_favorite_time_desc'.tr,
    );
    addItem(
      MusicListSortBy.favoriteTime,
      MusicListSortOrder.asc,
      'music_list_sort_favorite_time_asc'.tr,
    );
  }

  return items;
}

class MusicListSourcePanel extends StatelessWidget {
  final MusicListController controller;
  const MusicListSourcePanel({super.key, required this.controller});

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
                itemBuilder: (ctx, index) {
                  final item = controller.availablePaths[index];
                  final path = item.path;
                  return Obx(() {
                    final isSelected = controller.selectedPaths.contains(path);
                    return CheckboxListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(path, style: Get.textTheme.bodySmall),
                          ),
                          if (item.valid)
                            const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 16,
                            )
                          else
                            const Icon(
                              Icons.cancel,
                              color: Colors.red,
                              size: 16,
                            ),
                        ],
                      ),
                      value: isSelected,
                      onChanged: (val) {
                        if (val == true) {
                          controller.selectedPaths.add(path);
                        } else {
                          controller.selectedPaths.remove(path);
                        }
                        controller.refreshList(showLoading: false);
                      },
                    );
                  });
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}

class MusicListSearchBar extends StatefulWidget {
  final MusicListController controller;
  const MusicListSearchBar({super.key, required this.controller});

  @override
  State<MusicListSearchBar> createState() => _MusicListSearchBarState();
}

class _MusicListSearchBarState extends State<MusicListSearchBar> {
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
    return CustomExpandableSearchBar(
      controller: _ctrl,
      hintText: 'music_list_search_hint'.tr,
      onChanged: widget.controller.onSearchChanged,
      onClear: widget.controller.clearSearch,
    );
  }
}

class _AppMusicListSearchBar extends StatefulWidget {
  final MusicListController controller;
  const _AppMusicListSearchBar({required this.controller});

  @override
  State<_AppMusicListSearchBar> createState() => _AppMusicListSearchBarState();
}

class _AppMusicListSearchBarState extends State<_AppMusicListSearchBar> {
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
    return CustomExpandableSearchBar(
      controller: _ctrl,
      hintText: 'music_list_search_hint'.tr,
      onChanged: widget.controller.onSearchChanged,
      onClear: widget.controller.clearSearch,
      defaultExpanded: true,
    );
  }
}
