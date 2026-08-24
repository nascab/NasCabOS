import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/photo_timeline_controller.dart';
import 'parts/photo_timeline_list.dart';
import 'parts/photo_timeline_sidebar.dart';
import 'parts/app_photo_timeline_multiselect_bar.dart';
import '../../../../core/theme/custom_colors.dart';
import '../../photo_main/view/app_photo_main_view.dart';
import '../../../base/components/custom_bordered_icon_button.dart';
import '../../../base/components/custom_expandable_search_bar.dart';

class AppPhotoTimelineView extends StatefulWidget {
  final String controllerTag;
  final bool showSearchAction;
  const AppPhotoTimelineView({
    super.key,
    required this.controllerTag,
    this.showSearchAction = false,
  });

  @override
  State<AppPhotoTimelineView> createState() => _AppPhotoTimelineViewState();
}

class _AppPhotoTimelineViewState extends State<AppPhotoTimelineView> {
  late final PhotoTimelineController _ctrl;
  final Map<int, Offset> _activePointers = <int, Offset>{};
  double? _pinchStartDistance;
  double? _pinchStartItemSize;
  double _lastAppliedItemSize = 0;
  bool _pinchDirty = false;

  @override
  void initState() {
    super.initState();
    _ctrl = Get.find<PhotoTimelineController>(tag: widget.controllerTag);
    _ctrl.layoutCrossAxisSpacing = 1;
    _ctrl.layoutMainAxisSpacing = 1;
    _ctrl.layoutLeftPadding = 6;
    _ctrl.layoutRightPadding = 6;
    _ctrl.layoutHeaderExtent = 54;
    _ctrl.layoutTopLoadingExtent = 56;
  }

  void _onPointerDown(PointerDownEvent e) {
    _activePointers[e.pointer] = e.position;
    if (_activePointers.length == 2) {
      final pts = _activePointers.values.toList(growable: false);
      _pinchStartDistance = (pts[0] - pts[1]).distance;
      _pinchStartItemSize = _ctrl.itemSize.value;
      _lastAppliedItemSize = _ctrl.itemSize.value;
      _pinchDirty = false;
    } else if (_activePointers.length > 2) {
      _pinchStartDistance = null;
      _pinchStartItemSize = null;
      _pinchDirty = false;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_activePointers.containsKey(e.pointer)) return;
    _activePointers[e.pointer] = e.position;
    if (_activePointers.length != 2) return;
    final startDistance = _pinchStartDistance;
    final startItemSize = _pinchStartItemSize;
    if (startDistance == null || startDistance <= 0 || startItemSize == null) {
      return;
    }

    final pts = _activePointers.values.toList(growable: false);
    final currentDistance = (pts[0] - pts[1]).distance;
    if (currentDistance <= 0) return;

    final scale = currentDistance / startDistance;
    final nextSize = (startItemSize * scale).clamp(
      _ctrl.minItemSize.toDouble(),
      _ctrl.maxItemSize.toDouble(),
    );
    if ((nextSize - _lastAppliedItemSize).abs() < 2) return;

    _lastAppliedItemSize = nextSize;
    _pinchDirty = true;
    _ctrl.setItemSize(nextSize, save: false);
  }

  void _onPointerEnd(int pointer) {
    _activePointers.remove(pointer);
    if (_activePointers.length >= 2) return;
    if (_pinchDirty) {
      _ctrl.setItemSize(_ctrl.itemSize.value, save: true);
    }
    _pinchStartDistance = null;
    _pinchStartItemSize = null;
    _pinchDirty = false;
  }

  Future<void> _showFilterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(maxHeight: Get.height * 0.75),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'filter'.tr,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          _ctrl.clearSourcePathSelection(refresh: false);
                          _ctrl.setFileType('all');
                          Get.back();
                        },
                        child: Text('reset'.tr),
                      ),
                      CustomBorderedIconButton(
                        icon: Icons.close,
                        onTap: () => Get.back(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: Text(
                          'photo_timeline_filter_file_type'.tr,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      Obx(
                        () => Column(
                          children: [
                            RadioListTile<String>(
                              value: 'all',
                              groupValue: _ctrl.fileType.value,
                              onChanged: (v) {
                                if (v == null) return;
                                _ctrl.setFileType(v);
                                _ctrl.refreshTimeline();
                              },
                              title: Text('all'.tr),
                              dense: true,
                            ),
                            RadioListTile<String>(
                              value: 'photo',
                              groupValue: _ctrl.fileType.value,
                              onChanged: (v) {
                                if (v == null) return;
                                _ctrl.setFileType(v);
                                _ctrl.refreshTimeline();
                              },
                              title: Text('timeline_photos'.tr),
                              dense: true,
                            ),
                            RadioListTile<String>(
                              value: 'video',
                              groupValue: _ctrl.fileType.value,
                              onChanged: (v) {
                                if (v == null) return;
                                _ctrl.setFileType(v);
                                _ctrl.refreshTimeline();
                              },
                              title: Text('timeline_videos'.tr),
                              dense: true,
                            ),
                            RadioListTile<String>(
                              value: 'livephoto',
                              groupValue: _ctrl.fileType.value,
                              onChanged: (v) {
                                if (v == null) return;
                                _ctrl.setFileType(v);
                                _ctrl.refreshTimeline();
                              },
                              title: Text('timeline_live_photos'.tr),
                              dense: true,
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: Text(
                          'photo_timeline_filter_source'.tr,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      Obx(() {
                        if (_ctrl.availablePaths.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                            child: Text('no_path'.tr),
                          );
                        }
                        return Column(
                          children: _ctrl.availablePaths
                              .map((p) {
                                return Obx(() {
                                  final selected = _ctrl.selectedPaths.contains(
                                    p.path,
                                  );
                                  return CheckboxListTile(
                                    value: selected,
                                    onChanged: (v) {
                                      _ctrl.setSourcePathSelected(
                                        p.path,
                                        v == true,
                                      );
                                    },
                                    title: Text(
                                      p.path,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    dense: true,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                  );
                                });
                              })
                              .toList(growable: false),
                        );
                      }),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNearbyRangePicker(ThemeData theme) {
    return Obx(() {
      if (_ctrl.baseGeohash.value.isEmpty) {
        return const SizedBox.shrink();
      }
      final value = _ctrl.nearbyRangeKm.value;
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: PopupMenuButton<int>(
          initialValue: value,
          onSelected: _ctrl.setNearbyRangeKm,
          itemBuilder: (context) => const [
            PopupMenuItem(value: 2, child: Text('2km')),
            PopupMenuItem(value: 5, child: Text('5km')),
            PopupMenuItem(value: 10, child: Text('10km')),
            PopupMenuItem(value: 50, child: Text('50km')),
            PopupMenuItem(value: 80, child: Text('80km')),
          ],
          child: CustomBorderedIconButton(
            icon: Icons.place_outlined,
            active: value != 2,
            tooltip: '${value}km',
          ),
        ),
      );
    });
  }

  Widget _buildToolbar() {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    final barColor =
        customColors?.oprationBarBgColor ?? theme.colorScheme.surface;
    return Obx(() {
      if (_ctrl.isMultiSelectMode.value) return const SizedBox.shrink();
      final isDesc = _ctrl.sortOrder.value == 'desc';
      return Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        color: barColor,
        child: Row(
          children: [
            CustomBorderedIconButton(
              icon: isDesc ? Icons.rotate_left : Icons.rotate_right,
              tooltip: isDesc
                  ? 'photo_timeline_sort_desc'.tr
                  : 'photo_timeline_sort_asc'.tr,
              onTap: _ctrl.toggleSortOrder,
            ),
            const SizedBox(width: 8),
            if (widget.showSearchAction) ...[
              Expanded(
                child: CustomExpandableSearchBar(
                  hintText: 'photo_timeline_search_hint'.tr,
                  controller: _ctrl.searchController,
                  onChanged: _ctrl.onSearchChanged,
                  onClear: _ctrl.clearSearch,
                  defaultExpanded: true,
                ),
              ),
            ] else ...[
              const Spacer(),
              CustomBorderedIconButton(
                icon: Icons.check_box_outlined,
                tooltip: 'multi_select'.tr,
                onTap: _ctrl.toggleMultiSelectMode,
              ),
            ],
            _buildNearbyRangePicker(theme),
            const SizedBox(width: 8),
            if (_ctrl.baseGeohash.value.isEmpty) ...[
              Obx(() {
                final isMin = _ctrl.itemSize.value <= _ctrl.minItemSize;
                return CustomBorderedIconButton(
                  icon: Icons.zoom_out,
                  tooltip: 'zoom_out'.tr,
                  onTap: isMin ? null : () => _ctrl.changeItemSize(-20),
                  enabled: !isMin,
                );
              }),
              const SizedBox(width: 8),
              Obx(() {
                final isMax = _ctrl.itemSize.value >= _ctrl.maxItemSize;
                return CustomBorderedIconButton(
                  icon: Icons.zoom_in,
                  tooltip: 'zoom_in'.tr,
                  onTap: isMax ? null : () => _ctrl.changeItemSize(20),
                  enabled: !isMax,
                );
              }),
              const SizedBox(width: 8),
            ],

            Obx(() {
              final active =
                  _ctrl.selectedPaths.isNotEmpty ||
                  _ctrl.fileType.value != 'all';
              return CustomBorderedIconButton(
                icon: active ? Icons.filter_alt : Icons.filter_alt_outlined,
                tooltip: 'filter'.tr,
                active: active,
                onTap: _showFilterSheet,
              );
            }),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    return Container(
      color: customColors?.mainContentBgColor ?? theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          _buildToolbar(),
          Expanded(
            child: Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: (e) => _onPointerEnd(e.pointer),
              onPointerCancel: (e) => _onPointerEnd(e.pointer),
              child: RefreshIndicator(
                onRefresh: _ctrl.refreshTimeline,
                child: Stack(
                  children: [
                    PhotoTimelineList(controllerTag: widget.controllerTag),
                    PhotoTimelineSidebar(
                      controllerTag: widget.controllerTag,
                      compact: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppPhotoTimelinePage extends StatelessWidget {
  const AppPhotoTimelinePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppPhotoMainView();
  }
}

class AppPhotoTimelineRoutePage extends StatelessWidget {
  final String title;
  final String listType;
  final int? albumId;
  final int? collectionId;
  final int? smartAlbumId;
  final int? faceId;
  final String? placeName;
  final bool loadTheDay;
  final String? geohash;
  final int? year;

  const AppPhotoTimelineRoutePage({
    super.key,
    required this.title,
    this.listType = 'timeline',
    this.albumId,
    this.collectionId,
    this.smartAlbumId,
    this.faceId,
    this.placeName,
    this.loadTheDay = false,
    this.geohash,
    this.year,
  });

  String get _controllerTag {
    final base = loadTheDay ? '${listType}_the_day' : listType;
    var t = 'mobile_$base';
    if (albumId != null) t = '${t}_album_$albumId';
    if (collectionId != null) t = '${t}_collection_$collectionId';
    if (smartAlbumId != null) t = '${t}_smart_album_$smartAlbumId';
    if (faceId != null) t = '${t}_face_$faceId';
    if (placeName != null && placeName!.trim().isNotEmpty) {
      t = '${t}_place_name_${placeName!.trim()}';
    }
    if (geohash != null && geohash!.trim().isNotEmpty) {
      t = '${t}_geo_${geohash!.trim()}';
    }
    if (year != null) t = '${t}_year_$year';
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final customColors = Theme.of(context).extension<CustomColors>();
    final controllerTag = _controllerTag;
    return GetBuilder<PhotoTimelineController>(
      init: PhotoTimelineController(
        initialListType: listType,
        initialAlbumId: albumId,
        initialCollectionId: collectionId,
        initialSmartAlbumId: smartAlbumId,
        initialFaceId: faceId,
        initialPlaceName: placeName,
        initialLoadTheDay: loadTheDay,
        initialGeohash: geohash,
        initialYear: year,
      ),
      tag: controllerTag,
      dispose: (_) => Get.delete<PhotoTimelineController>(tag: controllerTag),
      builder: (_) {
        return Scaffold(
          backgroundColor:
              customColors?.mainContentBgColor ?? Theme.of(context).canvasColor,
          appBar: AppBar(title: Text(title)),
          body: AppPhotoTimelineView(
            controllerTag: controllerTag,
            showSearchAction: true,
          ),
          bottomNavigationBar: AppPhotoTimelineMultiSelectBottomBar(
            controllerTag: controllerTag,
          ),
        );
      },
    );
  }
}
