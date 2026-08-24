import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controller/video_list_controller.dart';
import 'video_list_badge.dart';
import '../../../../base/components/custom_hover_menu_anchor.dart';

class VideoListFilterPanel extends StatelessWidget {
  final VideoListController controller;
  final bool showMediaTypeFilter;
  final EdgeInsets contentPadding;
  const VideoListFilterPanel({
    super.key,
    required this.controller,
    this.showMediaTypeFilter = false,
    this.contentPadding = const EdgeInsets.fromLTRB(14, 12, 14, 12),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final yearGroups = controller.getYearGroups();
      final regions = controller.availableRegions.toList();
      final genres = controller.availableGenres.toList();

      Widget chip({
        required String text,
        required bool selected,
        required VoidCallback onTap,
      }) {
        final fg = selected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface;
        final bg = selected
            ? theme.colorScheme.primary.withValues(alpha: 0.14)
            : Colors.transparent;
        return Material(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(color: fg),
              ),
            ),
          ),
        );
      }

      Widget groupRow({required String label, required List<Widget> options}) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 92,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Wrap(spacing: 10, runSpacing: 10, children: options),
              ),
            ],
          ),
        );
      }

      List<Widget> yearOptions() {
        if (yearGroups.isEmpty) {
          return [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
              child: Text('no_data'.tr, style: theme.textTheme.bodyMedium),
            ),
          ];
        }
        return [
          chip(
            text: 'all'.tr,
            selected: controller.selectedYears.isEmpty,
            onTap: () {
              controller.selectedYears.clear();
              controller.refreshList(showLoading: true);
            },
          ),
          ...yearGroups.map((g) {
            final selected = g.single
                ? controller.selectedYears.length == 1 &&
                      controller.selectedYears.contains(g.years.first)
                : g.years.every(controller.selectedYears.contains);
            return chip(
              text: g.label,
              selected: selected,
              onTap: () {
                if (g.single) {
                  controller.toggleYear(g.years.first);
                } else {
                  controller.toggleYearGroup(g.years);
                }
              },
            );
          }),
        ];
      }

      List<Widget> regionOptions() {
        if (regions.isEmpty) {
          return [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
              child: Text('no_data'.tr, style: theme.textTheme.bodyMedium),
            ),
          ];
        }
        return [
          chip(
            text: 'all'.tr,
            selected: controller.regions.isEmpty,
            onTap: () {
              controller.regions.clear();
              controller.refreshList(showLoading: true);
            },
          ),
          ...regions.map((r) {
            final selected = controller.regions.contains(r);
            return chip(
              text: r,
              selected: selected,
              onTap: () => controller.toggleRegion(r),
            );
          }),
        ];
      }

      List<Widget> genreOptions() {
        if (genres.isEmpty) {
          return [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
              child: Text('no_data'.tr, style: theme.textTheme.bodyMedium),
            ),
          ];
        }
        return [
          chip(
            text: 'all'.tr,
            selected: controller.genres.isEmpty,
            onTap: () {
              controller.genres.clear();
              controller.refreshList(showLoading: true);
            },
          ),
          ...genres.map((g) {
            final selected = controller.genres.contains(g);
            return chip(
              text: g,
              selected: selected,
              onTap: () => controller.toggleGenre(g),
            );
          }),
        ];
      }

      List<Widget> mediaTypeOptions() {
        final hasFixedType = controller.initialMediaType.trim().isNotEmpty;
        if (hasFixedType) return const <Widget>[];
        return [
          chip(
            text: 'all'.tr,
            selected: controller.mediaType.value.trim().isEmpty,
            onTap: () => controller.setMediaType(''),
          ),
          chip(
            text: 'video_home_type_movie'.tr,
            selected: controller.mediaType.value.trim() == 'movie',
            onTap: () => controller.setMediaType('movie'),
          ),
          chip(
            text: 'video_home_type_tv'.tr,
            selected: controller.mediaType.value.trim() == 'tv',
            onTap: () => controller.setMediaType('tv'),
          ),
        ];
      }

      return Padding(
        padding: contentPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showMediaTypeFilter &&
                controller.initialMediaType.trim().isEmpty)
              groupRow(label: 'type'.tr, options: mediaTypeOptions()),
            groupRow(
              label: 'video_list_filter_years'.tr,
              options: yearOptions(),
            ),
            groupRow(
              label: 'video_list_filter_regions'.tr,
              options: regionOptions(),
            ),
            groupRow(
              label: 'video_list_filter_genres'.tr,
              options: genreOptions(),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Spacer(),
                TextButton.icon(
                  onPressed: controller.resetFilter,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text('reset'.tr),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }
}

class VideoListFilterMenu extends StatelessWidget {
  final VideoListController controller;
  const VideoListFilterMenu({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final count = controller.activeFilterCount;

      return CustomHoverMenuAnchor(
        menuChildren: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860, minWidth: 560),
            child: VideoListFilterPanel(controller: controller),
          ),
        ],
        child: VideoListBadge(
          count: count,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.filter_alt_outlined, size: 18),
              const SizedBox(width: 6),
              Text('filter'.tr),
            ],
          ),
        ),
      );
    });
  }
}
