import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/theme/custom_colors.dart';
import '../../../base/components/custom_extended_image.dart';
import '../../../base/components/custom_bordered_icon_button.dart';
import '../../../base/components/custom_expandable_search_bar.dart';
import '../../../../../core/api/api_controller.dart';
import '../models/photo_timeline_model.dart';
import '../service/photo_timeline_api_service.dart';
import '../controller/photo_timeline_controller.dart';
import 'package:flutter/services.dart';
import 'parts/photo_timeline_list.dart';
import 'parts/photo_timeline_sidebar.dart';
import 'parts/app_photo_timeline_multiselect_bar.dart';

/// 与照片主页悬浮模式栏（`bottom: 10` + `height: 45`）对齐，避免挡住年份网格最后一行。
const double _kYearGridBottomPadForFloatingModeBar = 10 + 45 + 12;

class AppPhotoTimelineYearPage extends StatefulWidget {
  const AppPhotoTimelineYearPage({super.key});

  @override
  State<AppPhotoTimelineYearPage> createState() =>
      _AppPhotoTimelineYearPageState();
}

class _AppPhotoTimelineYearPageState extends State<AppPhotoTimelineYearPage> {
  final PhotoTimelineApiService _api = PhotoTimelineApiService();
  final RxBool _loading = true.obs;
  final RxList<TimelineYearItem> _items = <TimelineYearItem>[].obs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _loading.value = true;
    try {
      final res = await _api.getTimelineYearList();
      if (res.success && res.data != null) {
        _items.assignAll(res.data!.items);
      } else {
        _items.clear();
      }
    } finally {
      _loading.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      Widget child;
      if (_loading.value) {
        child = ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(
            bottom: _kYearGridBottomPadForFloatingModeBar,
          ),
          children: const [
            SizedBox(height: 120),
            Center(child: CircularProgressIndicator()),
          ],
        );
      } else if (_items.isEmpty) {
        child = ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(
            bottom: _kYearGridBottomPadForFloatingModeBar,
          ),
          children: [
            const SizedBox(height: 120),
            Center(child: Text('no_photo'.tr)),
          ],
        );
      } else {
        child = Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: GridView.builder(
            padding: const EdgeInsets.only(
              bottom: _kYearGridBottomPadForFloatingModeBar,
            ),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: _items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.2,
            ),
            itemBuilder: (context, index) {
              final item = _items[index];
              return _YearCard(
                item: item,
                onTap: () => Get.to(
                  () => AppPhotoTimelineYearDetailPage(year: item.year),
                ),
              );
            },
          ),
        );
      }

      return RefreshIndicator(onRefresh: _load, child: child);
    });
  }
}

class AppPhotoTimelineYearDetailPage extends StatefulWidget {
  final int year;
  const AppPhotoTimelineYearDetailPage({super.key, required this.year});

  @override
  State<AppPhotoTimelineYearDetailPage> createState() =>
      _AppPhotoTimelineYearDetailPageState();
}

class _AppPhotoTimelineYearDetailPageState
    extends State<AppPhotoTimelineYearDetailPage> {
  late final String _tag;
  late final PhotoTimelineController _ctrl;

  @override
  void initState() {
    super.initState();
    _tag = 'app_photo_timeline_year_${widget.year}_${UniqueKey()}';
    Get.put(
      PhotoTimelineController(
        initialListType: 'timeline',
        initialYear: widget.year,
      ),
      tag: _tag,
    );
    _ctrl = Get.find<PhotoTimelineController>(tag: _tag);
    _ctrl.layoutCrossAxisSpacing = 1;
    _ctrl.layoutMainAxisSpacing = 1;
    _ctrl.layoutLeftPadding = 6;
    _ctrl.layoutRightPadding = 6;
    _ctrl.layoutHeaderExtent = 54;
    _ctrl.layoutTopLoadingExtent = 56;
  }

  @override
  void dispose() {
    Get.delete<PhotoTimelineController>(tag: _tag, force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    final bg =
        customColors?.mainContentBgColor ?? theme.scaffoldBackgroundColor;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor:
            theme.appBarTheme.backgroundColor ?? theme.colorScheme.primary,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor:
            theme.appBarTheme.backgroundColor ?? theme.colorScheme.primary,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor:
            theme.appBarTheme.backgroundColor ?? theme.colorScheme.primary,
      ),
      child: Obx(() {
        final isMulti = _ctrl.isMultiSelectMode.value;
        return PopScope(
          canPop: !isMulti,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && isMulti) _ctrl.exitMultiSelectMode();
          },
          child: Scaffold(
            backgroundColor: bg,
            body: _YearTimelineDetailView(
              controllerTag: _tag,
              year: widget.year,
            ),
            bottomNavigationBar: AppPhotoTimelineMultiSelectBottomBar(
              controllerTag: _tag,
            ),
          ),
        );
      }),
    );
  }
}

class _YearCard extends StatelessWidget {
  final TimelineYearItem item;
  final VoidCallback onTap;
  const _YearCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageUrl = ApiController.instance.getTinyUrl(item.cover.fullpath);
    final countText = 'folder_status_total'.trParams({
      'total': item.count.toString(),
    });
    final yearText = 'photo_timeline_year_title'.trParams({
      'year': item.year.toString(),
    });

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomExtendedImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              borderRadius: 0,
            ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xAA000000), Color(0x00000000)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    yearText,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                      shadows: const [
                        Shadow(
                          offset: Offset(0, 2),
                          blurRadius: 10,
                          color: Colors.black,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    countText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w600,
                      shadows: const [
                        Shadow(
                          offset: Offset(0, 2),
                          blurRadius: 10,
                          color: Colors.black,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _YearTimelineDetailView extends StatefulWidget {
  final String controllerTag;
  final int year;
  const _YearTimelineDetailView({
    required this.controllerTag,
    required this.year,
  });

  @override
  State<_YearTimelineDetailView> createState() =>
      _YearTimelineDetailViewState();
}

class _YearTimelineDetailViewState extends State<_YearTimelineDetailView> {
  late final PhotoTimelineController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = Get.find<PhotoTimelineController>(tag: widget.controllerTag);
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

  Widget _buildTopBar() {
    final theme = Theme.of(context);
    final barColor =
        theme.appBarTheme.backgroundColor ?? theme.colorScheme.primary;
    final fgColor = theme.appBarTheme.foregroundColor ?? Colors.white;
    return Container(
      color: barColor,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Obx(() {
              final isMulti = _ctrl.isMultiSelectMode.value;
              if (isMulti) {
                return Row(
                  children: [
                    IconButton(
                      tooltip: 'cancel'.tr,
                      onPressed: _ctrl.exitMultiSelectMode,
                      icon: Icon(Icons.close, color: fgColor),
                    ),
                    Expanded(
                      child: Text(
                        '${_ctrl.selectedItems.length} ${'selected'.tr}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: fgColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  IconButton(
                    tooltip: 'back'.tr,
                    onPressed: () => Get.back(),
                    icon: Icon(Icons.arrow_back_ios_new, color: fgColor),
                  ),
                  Expanded(
                    child: Text(
                      'photo_timeline_year_title'.trParams({
                        'year': widget.year.toString(),
                      }),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: fgColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Obx(() {
      if (_ctrl.isMultiSelectMode.value) return const SizedBox.shrink();
      final isDesc = _ctrl.sortOrder.value == 'desc';
      return SizedBox(
        height: 52,
        child: Row(
          children: [
            const SizedBox(width: 10),
            CustomBorderedIconButton(
              icon: isDesc ? Icons.rotate_left : Icons.rotate_right,
              tooltip: isDesc
                  ? 'photo_timeline_sort_desc'.tr
                  : 'photo_timeline_sort_asc'.tr,
              onTap: _ctrl.toggleSortOrder,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: CustomExpandableSearchBar(
                hintText: 'photo_timeline_search_hint'.tr,
                controller: _ctrl.searchController,
                onChanged: _ctrl.onSearchChanged,
                onClear: _ctrl.clearSearch,
                defaultExpanded: true,
              ),
            ),
            const SizedBox(width: 8),

            CustomBorderedIconButton(
              icon: Icons.check_box_outlined,
              tooltip: 'multi_select'.tr,
              onTap: _ctrl.toggleMultiSelectMode,
            ),
            const SizedBox(width: 8),
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
            const SizedBox(width: 10),
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
          _buildTopBar(),
          _buildToolbar(),
          Expanded(
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
        ],
      ),
    );
  }
}
