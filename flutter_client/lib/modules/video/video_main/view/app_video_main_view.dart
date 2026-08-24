import 'package:NasCabOS/core/routes/app_routes.dart';
import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/core/user/current_user_controller.dart';
import 'package:NasCabOS/modules/folder_view/folder_view_module_type.dart';
import 'package:NasCabOS/modules/folder_view/view/app_folder_view_page.dart';
import 'package:NasCabOS/modules/video/app_album/view/app_video_albums_home_page.dart';
import 'package:NasCabOS/modules/base/components/custom_bordered_icon_button.dart';
import 'package:NasCabOS/modules/video/home/view/app_video_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../list/view/app_video_list_page.dart';
import 'app_video_settings_view.dart';

class AppVideoMainView extends StatefulWidget {
  const AppVideoMainView({super.key});

  @override
  State<AppVideoMainView> createState() => _AppVideoMainViewState();
}

class _AppVideoMainViewState extends State<AppVideoMainView> {
  int _tabIndex = 0;
  int _libraryIndex = 0;

  void _openHome() {
    AppRoutes.toHome();
  }

  void _openSettings() {
    Get.to(
      () => Scaffold(
        appBar: AppBar(title: Text('setting'.tr)),
        body: const AppVideoSettingsView(),
      ),
      preventDuplicates: false,
    );
  }

  Widget _modeChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? theme.colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: selected ? Colors.white : theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingModeBar() {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();

    if (_tabIndex != 0) return const SizedBox.shrink();

    return Positioned(
      left: 16,
      right: 16,
      bottom: 10,
      child: Container(
        height: 45,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: (customColors?.oprationBarBgColor ?? theme.colorScheme.surface)
              .withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(22.5),
        ),
        child: Row(
          children: [
            _modeChip(
              label: 'home'.tr,
              selected: _libraryIndex == 0,
              onTap: () => setState(() => _libraryIndex = 0),
            ),
            _modeChip(
              label: 'video_home_type_movie'.tr,
              selected: _libraryIndex == 1,
              onTap: () => setState(() => _libraryIndex = 1),
            ),
            _modeChip(
              label: 'video_home_type_tv'.tr,
              selected: _libraryIndex == 2,
              onTap: () => setState(() => _libraryIndex = 2),
            ),
            _modeChip(
              label: 'favorites'.tr,
              selected: _libraryIndex == 3,
              onTap: () => setState(() => _libraryIndex = 3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBody() {
    if (_tabIndex == 0) {
      if (_libraryIndex == 0) {
        return AppVideoHomePage(
          onOpenMovie: () => setState(() => _libraryIndex = 1),
          onOpenTv: () => setState(() => _libraryIndex = 2),
          onOpenHistory: () => setState(() => _tabIndex = 1),
        );
      }
      if (_libraryIndex == 1) {
        return AppVideoListPage(
          key: const ValueKey('app_video_list_movie'),
          initialMediaType: 'movie',
          onBack: () => setState(() => _libraryIndex = 0),
        );
      }
      if (_libraryIndex == 2) {
        return AppVideoListPage(
          key: const ValueKey('app_video_list_tv'),
          initialMediaType: 'tv',
          onBack: () => setState(() => _libraryIndex = 0),
        );
      }
      if (_libraryIndex == 3) {
        return AppVideoListPage(
          key: const ValueKey('app_video_list_favorite'),
          initialMediaType: '',
          listType: 'favorite',
          onBack: () => setState(() => _libraryIndex = 0),
        );
      }
      return Center(child: Text('not_implemented_yet'.tr));
    }
    if (_tabIndex == 1) {
      return AppVideoListPage(
        key: const ValueKey('app_video_list_history'),
        initialMediaType: '',
        listType: 'history',
        onBack: () => setState(() {
          _tabIndex = 0;
          _libraryIndex = 0;
        }),
      );
    }
    if (_tabIndex == 2) {
      return const KeyedSubtree(
        key: ValueKey('app_video_albums_home'),
        child: AppVideoAlbumsHomePage(),
      );
    }
    if (_tabIndex == 3) {
      return const KeyedSubtree(
        key: ValueKey('app_video_file_view'),
        child: AppFolderViewPage(moduleType: FolderViewModuleType.video),
      );
    }
    return Center(child: Text('not_implemented_yet'.tr));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    final barColor =
        customColors?.oprationBarBgColor ?? theme.colorScheme.surface;
    final isAdmin = CurrentUserController.instance.isAdmin;

    final bottomItems = <BottomNavigationBarItem>[
      BottomNavigationBarItem(
        icon: const Icon(Icons.movie_filter_outlined),
        label: 'video_menu_library'.tr,
      ),
      BottomNavigationBarItem(
        icon: const Icon(Icons.history_outlined),
        label: 'video_menu_library_history'.tr,
      ),
      BottomNavigationBarItem(
        icon: const Icon(Icons.video_collection_outlined),
        label: 'video_menu_albums'.tr,
      ),
      BottomNavigationBarItem(
        icon: const Icon(Icons.folder_outlined),
        label: 'file'.tr,
      ),
    ];

    final isHome = _tabIndex == 0 && _libraryIndex == 0;
    final statusBarIconBrightness = isHome
        ? Brightness.light
        : (theme.brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: statusBarIconBrightness,
          statusBarBrightness: isHome ? Brightness.dark : theme.brightness,
          systemNavigationBarColor: barColor,
          systemNavigationBarIconBrightness: Brightness.dark,
          systemNavigationBarDividerColor: barColor,
        ),
        child: Stack(
          children: [
            SafeArea(
              top: false,
              bottom: false,
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [_buildTabBody(), _buildFloatingModeBar()],
                    ),
                  ),
                ],
              ),
            ),
            if (_tabIndex == 0 && _libraryIndex == 0)
              Positioned(
                left: 12,
                top: MediaQuery.of(context).padding.top + 10,
                child: CustomBorderedIconButton(
                  icon: Icons.home_outlined,
                  onTap: _openHome,
                  size: 42,
                  iconSize: 22,
                  borderRadius: 999,
                  backgroundColor: theme.colorScheme.surface.withValues(
                    alpha: 0.75,
                  ),
                  borderColor: theme.colorScheme.onSurface.withValues(
                    alpha: 0.12,
                  ),
                  iconColor: theme.colorScheme.onSurface,
                ),
              ),
            if (isAdmin && _tabIndex == 0 && _libraryIndex == 0)
              Positioned(
                right: 12,
                top: MediaQuery.of(context).padding.top + 10,
                child: CustomBorderedIconButton(
                  icon: Icons.settings_outlined,
                  onTap: _openSettings,
                  size: 42,
                  iconSize: 22,
                  borderRadius: 999,
                  backgroundColor: theme.colorScheme.surface.withValues(
                    alpha: 0.75,
                  ),
                  borderColor: theme.colorScheme.onSurface.withValues(
                    alpha: 0.12,
                  ),
                  iconColor: theme.colorScheme.onSurface,
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: ColoredBox(
        color: barColor,
        child: SafeArea(
          top: false,
          child: BottomNavigationBar(
            backgroundColor: barColor,
            elevation: 0,
            currentIndex: _tabIndex.clamp(0, bottomItems.length - 1),
            onTap: (i) {
              if (i == _tabIndex) return;
              setState(() => _tabIndex = i);
            },
            selectedItemColor: theme.colorScheme.primary,
            unselectedItemColor: theme.colorScheme.onSurfaceVariant,
            type: BottomNavigationBarType.fixed,
            items: bottomItems,
          ),
        ),
      ),
    );
  }
}
