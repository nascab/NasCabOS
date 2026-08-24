import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/api/api_controller.dart';
import '../../../base/components/app_custom_search_dialog.dart';
import '../../../base/components/custom_extended_image.dart';
import '../../../base/components/custom_no_data.dart';
import '../../../../utils/dialog_util.dart';
import '../../timeline/view/app_photo_album_timeline_page.dart';
import '../controller/photo_album_controller.dart';
import '../models/photo_album_model.dart';
import 'dialogs/photo_album_create_edit_dialog.dart';

class AppPhotoAlbumListPage extends StatefulWidget {
  final String type;
  final bool selectionMode;
  final bool autoOpenCreate;
  const AppPhotoAlbumListPage({
    super.key,
    this.type = 'all',
    this.selectionMode = false,
    this.autoOpenCreate = false,
  });

  @override
  State<AppPhotoAlbumListPage> createState() => _AppPhotoAlbumListPageState();
}

class _AppPhotoAlbumListPageState extends State<AppPhotoAlbumListPage> {
  late final String _tag;
  bool _didAutoOpenCreate = false;
  int? _selectedAlbumId;

  @override
  void initState() {
    super.initState();
    _tag = 'app_photo_album_list_${widget.type}_${UniqueKey()}';
  }

  Future<void> _showMobileFilterSortSheet(PhotoAlbumController ctrl) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        var type = ctrl.typeFilter.value;
        var sortField = ctrl.sortField.value;
        var sortOrder = ctrl.sortOrder.value;
        return StatefulBuilder(
          builder: (context, setState) {
            Widget item({
              required String title,
              required bool selected,
              required VoidCallback onTap,
            }) {
              return ListTile(
                title: Text(title),
                trailing: selected ? const Icon(Icons.check, size: 18) : null,
                onTap: onTap,
              );
            }

            return SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'filter'.tr,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ),
                    item(
                      title: 'photo_album_filter_all'.tr,
                      selected: type == 'all',
                      onTap: () => setState(() => type = 'all'),
                    ),
                    item(
                      title: 'photo_album_filter_my_shared'.tr,
                      selected: type == 'my_shared',
                      onTap: () => setState(() => type = 'my_shared'),
                    ),
                    item(
                      title: 'photo_album_filter_shared_to_me'.tr,
                      selected: type == 'shared_to_me',
                      onTap: () => setState(() => type = 'shared_to_me'),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'sort'.tr,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ),
                    item(
                      title: 'photo_album_sort_name_asc'.tr,
                      selected: sortField == 'name' && sortOrder == 'asc',
                      onTap: () => setState(() {
                        sortField = 'name';
                        sortOrder = 'asc';
                      }),
                    ),
                    item(
                      title: 'photo_album_sort_name_desc'.tr,
                      selected: sortField == 'name' && sortOrder == 'desc',
                      onTap: () => setState(() {
                        sortField = 'name';
                        sortOrder = 'desc';
                      }),
                    ),
                    item(
                      title: 'photo_album_sort_create_time_asc'.tr,
                      selected:
                          sortField == 'create_time' && sortOrder == 'asc',
                      onTap: () => setState(() {
                        sortField = 'create_time';
                        sortOrder = 'asc';
                      }),
                    ),
                    item(
                      title: 'photo_album_sort_create_time_desc'.tr,
                      selected:
                          sortField == 'create_time' && sortOrder == 'desc',
                      onTap: () => setState(() {
                        sortField = 'create_time';
                        sortOrder = 'desc';
                      }),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            ctrl.setTypeFilter(type);
                            ctrl.setSort(field: sortField, order: sortOrder);
                          },
                          child: Text('ok'.tr),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAlbumActions(
    PhotoAlbumController ctrl,
    PhotoAlbumItem album,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: Text('open'.tr),
                onTap: () {
                  Navigator.of(ctx).pop();
                  if (widget.selectionMode) {
                    Navigator.of(context).pop(album);
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AppPhotoAlbumTimelinePage(
                        type: AppPhotoAlbumTimelineType.album,
                        id: album.id,
                        name: album.name,
                      ),
                    ),
                  );
                },
              ),
              if (!album.isOwner)
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text('info'.tr),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    final content = 'photo_album_creator_with_name'.trParams({
                      'name': album.ownerUsername ?? '',
                    });
                    DialogUtil.showInfoDialog(
                      title: 'info'.tr,
                      content: content,
                    );
                  },
                ),
              if (!widget.selectionMode)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text('edit'.tr),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await showPhotoAlbumEditDialog(context, ctrl, album);
                  },
                ),
              if (!widget.selectionMode)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text('delete'.tr),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final ok = await DialogUtil.showConfirmDialog(
                      title: 'tip'.tr,
                      content: '${'delete'.tr} "${album.name}" ?',
                    );
                    if (ok != true) return;
                    await ctrl.deleteAlbum(album.id);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<PhotoAlbumController>(
      init: PhotoAlbumController(type: widget.type),
      tag: _tag,
      dispose: (_) => Get.delete<PhotoAlbumController>(tag: _tag),
      builder: (ctrl) {
        if (widget.autoOpenCreate && !_didAutoOpenCreate) {
          _didAutoOpenCreate = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (widget.selectionMode) return;
            showPhotoAlbumCreateDialog(context, ctrl);
          });
        }

        final content = Obx(() {
          if (ctrl.isLoading.value && ctrl.items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (ctrl.items.isEmpty) {
            if (widget.selectionMode) {
              return Center(
                child: FilledButton.icon(
                  onPressed: () => showPhotoAlbumCreateDialog(context, ctrl),
                  icon: const Icon(Icons.add),
                  label: Text('create'.tr),
                ),
              );
            }
            return CustomNoData(text: 'no_data'.tr);
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = width <= 750
                  ? 1
                  : (width / 340).floor().clamp(2, 6);
              return CustomScrollView(
                controller: ctrl.scrollController,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(12),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: crossAxisCount == 1 ? 2.3 : 1.25,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final album = ctrl.items[index];
                        final selected =
                            widget.selectionMode &&
                            _selectedAlbumId == album.id;
                        return _AlbumCard(
                          album: album,
                          selectionMode: widget.selectionMode,
                          selected: selected,
                          onSelect: () {
                            setState(() {
                              if (_selectedAlbumId == album.id) {
                                _selectedAlbumId = null;
                              } else {
                                _selectedAlbumId = album.id;
                              }
                            });
                          },
                          onTap: () {
                            if (widget.selectionMode) {
                              setState(() {
                                if (_selectedAlbumId == album.id) {
                                  _selectedAlbumId = null;
                                } else {
                                  _selectedAlbumId = album.id;
                                }
                              });
                              return;
                            }
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => AppPhotoAlbumTimelinePage(
                                  type: AppPhotoAlbumTimelineType.album,
                                  id: album.id,
                                  name: album.name,
                                ),
                              ),
                            );
                          },
                          onMore: widget.selectionMode
                              ? null
                              : () => _showAlbumActions(ctrl, album),
                        );
                      }, childCount: ctrl.items.length),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Center(
                        child: ctrl.isLoading.value
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : (!ctrl.hasMore.value
                                  ? Text(
                                      'no_more'.tr,
                                      style: Get.textTheme.bodySmall,
                                    )
                                  : OutlinedButton(
                                      onPressed: ctrl.loadMore,
                                      child: Text('load_more'.tr),
                                    )),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        });

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: Text('photo_menu_album_normal'.tr),
            actions: [
              Obx(() {
                final hasKeyword = ctrl.keyword.value.isNotEmpty;
                return IconButton(
                  tooltip: 'search'.tr,
                  onPressed: () => AppCustomSearchDialog.show(
                    context: context,
                    hintText: 'search'.tr,
                    controller: ctrl.searchController,
                    onChanged: ctrl.onSearchChanged,
                    onClear: ctrl.clearSearch,
                  ),
                  icon: hasKeyword
                      ? Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(Icons.search),
                            Positioned(
                              top: -2,
                              right: -2,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        )
                      : const Icon(Icons.search),
                );
              }),
              IconButton(
                tooltip: 'sort'.tr,
                onPressed: () => _showMobileFilterSortSheet(ctrl),
                icon: const Icon(Icons.sort_by_alpha),
              ),
              if (widget.selectionMode)
                IconButton(
                  tooltip: 'ok'.tr,
                  onPressed: _selectedAlbumId == null
                      ? null
                      : () {
                          PhotoAlbumItem? selectedAlbum;
                          for (final a in ctrl.items) {
                            if (a.id == _selectedAlbumId) {
                              selectedAlbum = a;
                              break;
                            }
                          }
                          if (selectedAlbum == null) return;
                          Navigator.of(context).pop(selectedAlbum);
                        },
                  icon: const Icon(Icons.check),
                )
              else
                IconButton(
                  tooltip: 'create'.tr,
                  onPressed: () => showPhotoAlbumCreateDialog(context, ctrl),
                  icon: const Icon(Icons.add),
                ),
            ],
          ),
          body: RefreshIndicator(onRefresh: ctrl.refreshAlbums, child: content),
        );
      },
    );
  }
}

class _PreviewImage extends StatelessWidget {
  final String url;
  const _PreviewImage({required this.url});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.colorScheme.surfaceContainerHighest;
    if (url.isEmpty) {
      return Container(
        color: bg,
        alignment: Alignment.center,
        child: Image.asset(
          'assets/icons/no_data.png',
          width: 54,
          height: 54,
          fit: BoxFit.contain,
        ),
      );
    }
    return CustomExtendedImage(
      imageUrl: url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      borderRadius: 0,
      showLoading: false,
    );
  }
}

class _AlbumCard extends StatelessWidget {
  final PhotoAlbumItem album;
  final VoidCallback onTap;
  final VoidCallback? onMore;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onSelect;
  const _AlbumCard({
    required this.album,
    required this.onTap,
    required this.onMore,
    required this.selectionMode,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = album.previews.isNotEmpty ? album.previews.first : null;
    final url = cover == null
        ? ''
        : ApiController.instance.getTinyUrl(cover.fullpath);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Positioned.fill(child: _PreviewImage(url: url)),
            if (selectionMode)
              Positioned(
                left: 6,
                top: 6,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    onTap: onSelect,
                    borderRadius: BorderRadius.circular(18),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        selected
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: 64,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xCC000000), Color(0x00000000)],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Row(
                children: [
                  Icon(
                    album.isPublic ? Icons.public : Icons.lock_outline,
                    size: 16,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      album.name,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (onMore != null)
              Positioned(
                right: 6,
                top: 6,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    onTap: onMore,
                    borderRadius: BorderRadius.circular(18),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.more_horiz,
                        color: Colors.white,
                        size: 18,
                      ),
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
