import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controller/music_list_controller.dart';
import '../../../../video/list/view/parts/video_list_badge.dart';
import '../../../../base/components/custom_hover_menu_anchor.dart';

class MusicListFilterMenu extends StatelessWidget {
  final MusicListController controller;
  const MusicListFilterMenu({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final artists = controller.availableArtists.toList();
      final albums = controller.availableAlbums.toList();
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

      List<Widget> artistOptions() {
        if (artists.isEmpty) {
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
            selected: controller.artists.isEmpty,
            onTap: () {
              controller.artists.clear();
              controller.refreshList(showLoading: true);
            },
          ),
          ...artists.map((a) {
            final selected = controller.artists.contains(a);
            return chip(
              text: a,
              selected: selected,
              onTap: () => controller.toggleArtist(a),
            );
          }),
        ];
      }

      List<Widget> albumOptions() {
        if (albums.isEmpty) {
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
            selected: controller.albums.isEmpty,
            onTap: () {
              controller.albums.clear();
              controller.refreshList(showLoading: true);
            },
          ),
          ...albums.map((a) {
            final selected = controller.albums.contains(a);
            return chip(
              text: a,
              selected: selected,
              onTap: () => controller.toggleAlbum(a),
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

      final count = controller.activeFilterCount;

      return CustomHoverMenuAnchor(
        menuChildren: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860, minWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  groupRow(
                    label: 'music_list_filter_artists'.tr,
                    options: artistOptions(),
                  ),
                  groupRow(
                    label: 'music_list_filter_albums'.tr,
                    options: albumOptions(),
                  ),
                  groupRow(
                    label: 'music_list_filter_genres'.tr,
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
            ),
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
