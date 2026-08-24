import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'dart:math';
import 'package:NasCabOS/modules/base/components.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../base/components/custom_expandable_search_bar.dart';
import '../../../../base/components/custom_extended_image.dart';
import '../../controller/music_sub_list_controller.dart';
import 'music_sub_list_sort_menu.dart';

class MusicSubListHeader extends StatelessWidget {
  final MusicSubListController controller;
  final VoidCallback onClose;
  final String? coverCenterAsset;
  final double coverCenterAssetSize;

  const MusicSubListHeader({
    super.key,
    required this.controller,
    required this.onClose,
    this.coverCenterAsset,
    this.coverCenterAssetSize = 42,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cover(context),
            const SizedBox(width: 16),
            Expanded(child: _meta(context)),
          ],
        ),
      ),
    );
  }

  Widget _cover(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 100,
        height: 100,
        color: theme.colorScheme.surfaceVariant.withValues(alpha: 0.4),
        child: Obx(() {
          final url = controller.headerCoverUrl.trim();
          final cover = url.isEmpty
              ? Image.asset(
                  'assets/music/icons/default_cover.jpg',
                  fit: BoxFit.cover,
                )
              : CustomExtendedImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  showLoading: false,
                  borderRadius: 0,
                  errorBuilder: (context, error, stackTrace) => Image.asset(
                    'assets/music/icons/default_cover.jpg',
                    fit: BoxFit.cover,
                  ),
                );

          final asset = (coverCenterAsset ?? '').trim();
          if (asset.isEmpty) return cover;
          return Stack(
            fit: StackFit.expand,
            children: [
              cover,
              Center(
                child: Image.asset(
                  asset,
                  width: coverCenterAssetSize,
                  height: coverCenterAssetSize,
                  fit: BoxFit.contain,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _meta(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 40,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (!controller.isFavorite && !controller.isHistory)
                IconButton(
                  tooltip: 'back'.tr,
                  onPressed: onClose,
                  icon: Icon(Icons.arrow_back_ios_outlined),
                ),
              if (!controller.isFavorite && !controller.isHistory)
                const SizedBox(width: 6),
              Expanded(
                child: Text(
                  controller.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final searchWidth = (c.maxWidth * 0.33)
                .clamp(110.0, 200.0)
                .toDouble();
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Obx(() {
                          final disabled = controller.items.isEmpty;
                          return CustomButton(
                            text:
                                "${'play'.tr}(${max(0, controller.total.value)})",
                            onPressed: disabled
                                ? () {}
                                : () => controller.playAll(),
                            isPrimary: true,
                            height: 35,
                            icon: const Icon(Icons.play_arrow),
                            style: ElevatedButton.styleFrom(
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                            ),
                          );
                        }),
                        const SizedBox(width: 10),
                        if (!controller.isHistory)
                          MusicSubListSortMenu(controller: controller),
                        if (!controller.isHistory) const SizedBox(width: 10),
                        Obx(() {
                          final disabled = controller.items.isEmpty;
                          return CustomIconButton(
                            tooltip: 'multi_select'.tr,
                            onPressed: disabled
                                ? null
                                : () => controller.toggleMultiSelectMode(),
                            icon: Icons.select_all,
                            borderSide: BorderSide(color: theme.dividerColor),
                            borderRadius: 999,
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: searchWidth,
                  child: MusicSubListSearchBar(
                    controller: controller,
                    height: 40,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class MusicSubListMobileHeader extends StatelessWidget {
  final MusicSubListController controller;
  final VoidCallback onClose;
  final String? coverCenterAsset;
  final double coverCenterAssetSize;
  final bool showTitle;
  final bool showBackButton;

  const MusicSubListMobileHeader({
    super.key,
    required this.controller,
    required this.onClose,
    this.coverCenterAsset,
    this.coverCenterAssetSize = 42,
    this.showTitle = true,
    this.showBackButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coverSize = 80.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cover(context, coverSize: coverSize),
          const SizedBox(width: 12),
          Expanded(child: _meta(context)),
        ],
      ),
    );
  }

  Widget _cover(BuildContext context, {required double coverSize}) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: coverSize,
        height: coverSize,
        color: theme.colorScheme.surfaceVariant.withValues(alpha: 0.4),
        child: Obx(() {
          final url = controller.headerCoverUrl.trim();
          final cover = url.isEmpty
              ? Image.asset(
                  'assets/music/icons/default_cover.jpg',
                  fit: BoxFit.cover,
                )
              : CustomExtendedImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  showLoading: false,
                  borderRadius: 0,
                  errorBuilder: (context, error, stackTrace) => Image.asset(
                    'assets/music/icons/default_cover.jpg',
                    fit: BoxFit.cover,
                  ),
                );

          final asset = (coverCenterAsset ?? '').trim();
          if (asset.isEmpty) return cover;
          final centerSize = coverCenterAssetSize * 0.8;
          return Stack(
            fit: StackFit.expand,
            children: [
              cover,
              Center(
                child: Image.asset(
                  asset,
                  width: centerSize,
                  height: centerSize,
                  fit: BoxFit.contain,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _meta(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle) ...[
          SizedBox(
            height: 38,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (showBackButton &&
                    !controller.isFavorite &&
                    !controller.isHistory)
                  IconButton(
                    tooltip: 'back'.tr,
                    onPressed: onClose,
                    icon: const Icon(Icons.arrow_back_ios_outlined, size: 18),
                  ),
                if (showBackButton &&
                    !controller.isFavorite &&
                    !controller.isHistory)
                  const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    controller.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Obx(() {
              final disabled = controller.items.isEmpty;
              return CustomIconButton(
                tooltip: 'play'.tr,
                onPressed: disabled ? null : controller.playAll,
                icon: Icons.play_arrow,
                iconColor: theme.colorScheme.onPrimary,
                backgroundColor: theme.colorScheme.primary,
                borderRadius: 999,
                buttonSize: 36,
                iconSize: 20,
              );
            }),
            const SizedBox(width: 10),
            if (!controller.isHistory)
              MusicSubListSortMenu(controller: controller),
            const Spacer(),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: MusicSubListMobileSearchBar(controller: controller),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class MusicSubListMobilePageHeader extends StatelessWidget {
  final MusicSubListController controller;

  const MusicSubListMobilePageHeader({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    final barColor =
        customColors?.oprationBarBgColor ?? theme.colorScheme.surface;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: barColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Obx(() {
            final disabled = controller.items.isEmpty;
            return CustomIconButton(
              tooltip: 'play'.tr,
              icon: Icons.play_arrow,
              iconColor: theme.colorScheme.onPrimary,
              backgroundColor: theme.colorScheme.primary,
              borderRadius: 999,
              buttonSize: 36,
              iconSize: 20,
              onPressed: disabled ? () {} : controller.playAll,
            );
          }),
          const SizedBox(width: 8),
          Expanded(child: MusicSubListMobileSearchBar(controller: controller)),
          if (!controller.isHistory) SizedBox(width: 8),
          if (!controller.isHistory) _SortButton(controller: controller),
        ],
      ),
    );
  }
}

class MusicSubListSearchBar extends StatefulWidget {
  final MusicSubListController controller;
  final double height;
  const MusicSubListSearchBar({
    super.key,
    required this.controller,
    this.height = 32,
  });

  @override
  State<MusicSubListSearchBar> createState() => _MusicSubListSearchBarState();
}

class _MusicSubListSearchBarState extends State<MusicSubListSearchBar> {
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
      // isPill: true,
      hintText: 'music_list_search_hint'.tr,
      onChanged: widget.controller.onSearchChanged,
      onClear: widget.controller.clearSearch,
    );
  }
}

class MusicSubListMobileSearchBar extends StatefulWidget {
  final MusicSubListController controller;
  final double height;
  const MusicSubListMobileSearchBar({
    super.key,
    required this.controller,
    this.height = 36,
  });

  @override
  State<MusicSubListMobileSearchBar> createState() =>
      _MusicSubListMobileSearchBarState();
}

class _MusicSubListMobileSearchBarState
    extends State<MusicSubListMobileSearchBar> {
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
    return Row(
      children: [
        Expanded(
          child: CustomExpandableSearchBar(
            controller: _ctrl,
            // isPill: true,
            hintText: 'music_list_search_hint'.tr,
            onChanged: widget.controller.onSearchChanged,
            onClear: widget.controller.clearSearch,
            defaultExpanded: true,
          ),
        ),
      ],
    );
  }
}

class _SortButton extends StatelessWidget {
  final MusicSubListController controller;
  const _SortButton({required this.controller});

  List<_MusicSortEntry> _sortEntries(MusicSubListController c) {
    final base = <_MusicSortEntry>[];
    if (c.isFavorite) {
      base.addAll([
        _MusicSortEntry(
          by: MusicSubListSortBy.favoriteTime,
          order: MusicSubListSortOrder.desc,
          labelKey: 'music_list_sort_favorite_time_desc',
        ),
        _MusicSortEntry(
          by: MusicSubListSortBy.favoriteTime,
          order: MusicSubListSortOrder.asc,
          labelKey: 'music_list_sort_favorite_time_asc',
        ),
      ]);
    }
    base.addAll([
      _MusicSortEntry(
        by: MusicSubListSortBy.filename,
        order: MusicSubListSortOrder.asc,
        labelKey: 'music_list_sort_filename_asc',
      ),
      _MusicSortEntry(
        by: MusicSubListSortBy.filename,
        order: MusicSubListSortOrder.desc,
        labelKey: 'music_list_sort_filename_desc',
      ),
      _MusicSortEntry(
        by: MusicSubListSortBy.title,
        order: MusicSubListSortOrder.asc,
        labelKey: 'music_list_sort_title_asc',
      ),
      _MusicSortEntry(
        by: MusicSubListSortBy.title,
        order: MusicSubListSortOrder.desc,
        labelKey: 'music_list_sort_title_desc',
      ),
      _MusicSortEntry(
        by: MusicSubListSortBy.duration,
        order: MusicSubListSortOrder.desc,
        labelKey: 'music_list_sort_duration_desc',
      ),
      _MusicSortEntry(
        by: MusicSubListSortBy.duration,
        order: MusicSubListSortOrder.asc,
        labelKey: 'music_list_sort_duration_asc',
      ),
      _MusicSortEntry(
        by: MusicSubListSortBy.ctime,
        order: MusicSubListSortOrder.desc,
        labelKey: 'create_time_desc',
      ),
      _MusicSortEntry(
        by: MusicSubListSortBy.ctime,
        order: MusicSubListSortOrder.asc,
        labelKey: 'create_time_asc',
      ),
    ]);
    return base;
  }

  Future<void> _openSortSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final entries = _sortEntries(controller);
        return Material(
          color: theme.colorScheme.surface,
          child: Obx(() {
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              children: [
                for (final e in entries)
                  ListTile(
                    dense: true,
                    leading:
                        controller.sortBy.value == e.by &&
                            controller.sortOrder.value == e.order
                        ? Icon(Icons.check, color: theme.colorScheme.primary)
                        : const SizedBox(width: 24),
                    title: Text(e.labelKey.tr),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      controller.setSort(e.by, e.order);
                    },
                  ),
              ],
            );
          }),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (controller.isHistory) {
      return CustomBorderedIconButton(
        tooltip: 'sort'.tr,
        icon: Icons.sort_by_alpha,
        borderRadius: 999,
        enabled: false,
      );
    }

    return CustomBorderedIconButton(
      icon: Icons.sort_by_alpha,
      tooltip: 'sort'.tr,
      onTap: () => _openSortSheet(context),
    );
  }
}

class _MusicSortEntry {
  final MusicSubListSortBy by;
  final MusicSubListSortOrder order;
  final String labelKey;
  const _MusicSortEntry({
    required this.by,
    required this.order,
    required this.labelKey,
  });
}
