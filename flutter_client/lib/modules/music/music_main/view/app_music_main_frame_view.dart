import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/core/user/current_user_controller.dart';
import 'package:NasCabOS/modules/folder_view/folder_view_module_type.dart';
import 'package:NasCabOS/modules/folder_view/view/app_folder_view_page.dart';
import 'package:NasCabOS/modules/music/cache_setting/view/music_cache_settings_view.dart';
import 'package:NasCabOS/modules/music/collection/view/music_collection_list_view.dart';
import 'package:NasCabOS/modules/music/play_service/app_components/app_music_play_ctrl_floating_bar.dart';
import 'package:NasCabOS/modules/music/music_main/view/app_music_main_view.dart';
import 'package:NasCabOS/modules/music/play_service/play_ctrl_fullscreen/music_play_ctrl_fullscreen_sheet.dart';
import 'package:NasCabOS/modules/music/playlist/view/play_list_list_view.dart';
import 'package:NasCabOS/modules/music/source_setting/view/music_source_settings_view.dart';
import 'package:NasCabOS/utils/device_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AppMusicMainFrameView extends StatefulWidget {
  const AppMusicMainFrameView({super.key});

  @override
  State<AppMusicMainFrameView> createState() => _AppMusicMainFrameViewState();
}

class _AppMusicMainFrameViewState extends State<AppMusicMainFrameView> {
  int _tabIndex = 0;
  bool _showFullPlayer = false;

  void _openSettings() {
    Get.to(
      () => Scaffold(
        appBar: AppBar(title: Text('setting'.tr)),
        body: const _AppMusicSettingsTab(),
      ),
      preventDuplicates: false,
    );
  }

  Widget _buildTabBody() {
    if (_tabIndex == 0) {
      return AppMusicMainView(onOpenSettings: _openSettings);
    }
    if (_tabIndex == 1) {
      return const KeyedSubtree(
        key: ValueKey('app_music_playlists'),
        child: PlayListListView(),
      );
    }
    if (_tabIndex == 2) {
      return const KeyedSubtree(
        key: ValueKey('app_music_collections'),
        child: MusicCollectionListView(),
      );
    }
    if (_tabIndex == 3) {
      return const KeyedSubtree(
        key: ValueKey('app_music_file_view'),
        child: AppFolderViewPage(moduleType: FolderViewModuleType.music),
      );
    }
    return Center(child: Text('not_implemented_yet'.tr));
  }

  bool _tabNeedsOwnStatusBar() => _tabIndex == 1 || _tabIndex == 2;

  void _openFullscreen() {
    if (_showFullPlayer) return;
    setState(() => _showFullPlayer = true);
  }

  void _closeFullscreen() {
    if (!_showFullPlayer) return;
    setState(() => _showFullPlayer = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    final barColor =
        customColors?.oprationBarBgColor ?? theme.colorScheme.surface;

    if (_showFullPlayer) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: MusicPlayCtrlFullScreenSheet(onClose: _closeFullscreen),
      );
    }

    final floatingBottom = 5.0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: _tabIndex == 0 || _tabNeedsOwnStatusBar()
                ? _buildTabBody()
                : SafeArea(top: true, bottom: false, child: _buildTabBody()),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: floatingBottom,
            child: AppMusicPlayCtrlFloatingBar(
              onOpenFullscreen: _openFullscreen,
            ),
          ),
        ],
      ),
      bottomNavigationBar: ColoredBox(
        color: barColor,
        child: SafeArea(
          top: false,
          child: BottomNavigationBar(
            backgroundColor: barColor,
            elevation: 0,
            currentIndex: _tabIndex,
            onTap: (i) {
              if (i == _tabIndex) return;
              setState(() => _tabIndex = i);
            },
            selectedItemColor: theme.colorScheme.primary,
            unselectedItemColor: theme.colorScheme.onSurfaceVariant,
            type: BottomNavigationBarType.fixed,
            items: [
              BottomNavigationBarItem(
                icon: const Icon(Icons.home_outlined),
                label: 'home'.tr,
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.queue_music_outlined),
                label: 'music_menu_library_playlists'.tr,
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.collections_bookmark_outlined),
                label: 'music_collection_title'.tr,
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.folder_outlined),
                label: 'file'.tr,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppMusicSettingsTab extends StatelessWidget {
  const _AppMusicSettingsTab();

  @override
  Widget build(BuildContext context) {
    final isAdmin = CurrentUserController.instance.isAdmin;
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();

    if (!isAdmin) {
      if (!DeviceUtils.isWeb) {
        return ColoredBox(
          color: customColors?.mainContentBgColor ?? theme.colorScheme.surface,
          child: SafeArea(
            bottom: false,
            child: const KeyedSubtree(
              key: ValueKey('app_music_settings_cache'),
              child: MusicCacheSettingsView(),
            ),
          ),
        );
      }
      return Center(child: Text('not_implemented_yet'.tr));
    }

    final tabs = <Widget>[];
    final tabViews = <Widget>[];

    tabs.add(Tab(text: 'settings_source'.tr));
    tabViews.add(
      const KeyedSubtree(
        key: ValueKey('app_music_settings_source'),
        child: MusicSourceSettingsView(),
      ),
    );

    if (!DeviceUtils.isWeb) {
      tabs.add(Tab(text: 'music_menu_settings_cache'.tr));
      tabViews.add(
        const KeyedSubtree(
          key: ValueKey('app_music_settings_cache'),
          child: MusicCacheSettingsView(),
        ),
      );
    }

    if (tabs.isEmpty) {
      return Center(child: Text('not_implemented_yet'.tr));
    }

    return DefaultTabController(
      length: tabs.length,
      child: ColoredBox(
        color: customColors?.mainContentBgColor ?? theme.colorScheme.surface,
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TabBar(
                  dividerColor: Colors.transparent,
                  labelStyle: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  tabs: tabs,
                ),
              ),
            ),
            Expanded(child: TabBarView(children: tabViews)),
          ],
        ),
      ),
    );
  }
}
