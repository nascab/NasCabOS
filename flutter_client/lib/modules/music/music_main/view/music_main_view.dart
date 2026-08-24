import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:NasCabOS/core/theme/custom_colors.dart';
import '../controller/music_main_controller.dart';
import 'home_parts/music_left_menu.dart';
import '../../source_setting/view/music_source_settings_view.dart';
import '../../list/view/music_list_page.dart';
import '../../list/controller/music_list_controller.dart';
import '../../album_artist_list/view/album_artist_list_page.dart';
import '../../album_artist_list/controller/album_artist_list_controller.dart';
import '../../playlist/view/play_list_list_view.dart';
import '../../collection/view/music_collection_list_view.dart';
import '../../play_service/play_ctrl_bottom/music_play_ctrl_bottom_bar.dart';
import '../../play_service/play_ctrl_fullscreen/music_play_ctrl_fullscreen_sheet.dart';
import '../../sub_list/view/music_sub_list_overlay.dart';
import '../../cache_setting/view/music_cache_settings_view.dart';
import '../../../folder_view/folder_view_module_type.dart';
import '../../../folder_view/view/pc_folder_view_page.dart';

class MusicMainView extends StatelessWidget {
  const MusicMainView({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<MusicMainController>(
      init: MusicMainController(),
      builder: (ctrl) {
        return Obx(() {
          final collapsed = ctrl.sidebarCollapsed.value;
          final leftWidth = collapsed ? 64.0 : ctrl.leftWidth.value;

          return Stack(
            children: [
              Positioned.fill(
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      width: leftWidth,
                      child: MusicLeftMenu(
                        controller: ctrl,
                        collapsed: collapsed,
                        onToggleCollapse: () =>
                            ctrl.sidebarCollapsed.value = !collapsed,
                      ),
                    ),
                    Expanded(child: _buildRight(ctrl)),
                  ],
                ),
              ),
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  reverseDuration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) {
                    final curved = CurvedAnimation(
                      parent: anim,
                      curve: Curves.easeOutCubic,
                    );
                    final offset = Tween<Offset>(
                      begin: const Offset(0, 0.06),
                      end: Offset.zero,
                    ).animate(curved);
                    return FadeTransition(
                      opacity: curved,
                      child: SlideTransition(position: offset, child: child),
                    );
                  },
                  child: ctrl.showFullPlayer.value
                      ? MusicPlayCtrlFullScreenSheet(
                          key: const ValueKey('music_full_player'),
                          onClose: ctrl.closeFullPlayer,
                        )
                      : const SizedBox.shrink(
                          key: ValueKey('music_full_player_hidden'),
                        ),
                ),
              ),
            ],
          );
        });
      },
    );
  }

  Widget _buildRight(MusicMainController ctrl) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final customColors = theme.extension<CustomColors>();
        return ColoredBox(
          color: customColors?.mainContentBgColor ?? theme.colorScheme.surface,
          child: Obx(() {
            final key = ctrl.currentPageKey.value;
            Widget page = Center(child: Text('not_implemented_yet'.tr));
            if (key == 'library.songs') {
              page = const KeyedSubtree(
                key: ValueKey('music_list_songs'),
                child: MusicListPage(
                  key: ValueKey('music_list_songs_page'),
                  listType: '',
                  initialSortBy: MusicListSortBy.title,
                  initialSortOrder: MusicListSortOrder.asc,
                ),
              );
            } else if (key == 'library.albums') {
              page = const KeyedSubtree(
                key: ValueKey('music_list_albums'),
                child: AlbumArtistListPage(
                  key: ValueKey('music_list_albums_page'),
                  keyType: 'album',
                  initialSortBy: AlbumArtistListSortBy.count,
                  initialSortOrder: AlbumArtistListSortOrder.desc,
                ),
              );
            } else if (key == 'library.artists') {
              page = const KeyedSubtree(
                key: ValueKey('music_list_artists'),
                child: AlbumArtistListPage(
                  key: ValueKey('music_list_artists_page'),
                  keyType: 'artist',
                  initialSortBy: AlbumArtistListSortBy.count,
                  initialSortOrder: AlbumArtistListSortOrder.desc,
                ),
              );
            } else if (key == 'library.file_view') {
              page = const KeyedSubtree(
                key: ValueKey('music_folder_view'),
                child: PcFolderViewPage(moduleType: FolderViewModuleType.music),
              );
            } else if (key == 'library.playlists') {
              page = const KeyedSubtree(
                key: ValueKey('music_list_playlists'),
                child: PlayListListView(),
              );
            } else if (key == 'settings.source') {
              page = const MusicSourceSettingsView();
            } else if (key == 'settings.cache') {
              page = const MusicCacheSettingsView();
            } else if (key == 'library.favorite') {
              page = const KeyedSubtree(
                key: ValueKey('music_list_favorite'),
                child: MusicListPage(
                  key: ValueKey('music_list_favorite_page'),
                  isFavorite: true,
                  listType: '',
                  initialSortBy: MusicListSortBy.favoriteTime,
                  initialSortOrder: MusicListSortOrder.desc,
                ),
              );
            } else if (key == 'library.collection') {
              page = const KeyedSubtree(
                key: ValueKey('music_collection_list'),
                child: MusicCollectionListView(),
              );
            } else if (key == 'library.history') {
              page = KeyedSubtree(
                key: const ValueKey('music_list_history'),
                child: Stack(
                  children: [
                    MusicSubListOverlay(
                      key: const ValueKey('music_list_history_overlay'),
                      keyType: 'history',
                      name: 'music_menu_library_history'.tr,
                      isHistory: true,
                      onClose: () => ctrl.selectPage('library.songs'),
                    ),
                  ],
                ),
              );
            }

            return Stack(
              children: [
                Positioned.fill(child: page),
                if (!ctrl.hidePlayerBar.value)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: MusicPlayCtrlBottomBar(
                      onOpenFullscreen: ctrl.openFullPlayer,
                    ),
                  ),
              ],
            );
          }),
        );
      },
    );
  }
}
