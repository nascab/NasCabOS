import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:NasCabOS/core/theme/custom_colors.dart';
import '../controller/book_main_controller.dart';
import 'home_parts/book_left_menu.dart';
import '../../book_list/view/book_custom_list_list_view.dart';
import '../../list/controller/book_list_controller.dart';
import '../../list/view/book_list_page.dart';
import '../../source_setting/view/book_source_settings_view.dart';
import '../../history/view/book_history_list_view.dart';
import '../../cache_download/view/book_cache_download_view.dart';
import '../../collection/view/book_collection_list_view.dart';
import '../../../folder_view/folder_view_module_type.dart';
import '../../../folder_view/view/pc_folder_view_page.dart';

class BookMainView extends StatelessWidget {
  const BookMainView({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<BookMainController>(
      init: BookMainController(),
      builder: (ctrl) {
        return Obx(() {
          final collapsed = ctrl.sidebarCollapsed.value;
          final leftWidth = collapsed ? 64.0 : ctrl.leftWidth.value;

          final overlayCtrl = Get.isRegistered<BookSeriesOverlayController>()
              ? Get.find<BookSeriesOverlayController>()
              : Get.put(BookSeriesOverlayController());

          return Stack(
            children: [
              Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    width: leftWidth,
                    child: BookLeftMenu(
                      controller: ctrl,
                      collapsed: collapsed,
                      onToggleCollapse: () =>
                          ctrl.sidebarCollapsed.value = !collapsed,
                    ),
                  ),
                  Expanded(child: _buildRight(ctrl)),
                ],
              ),
              Obx(() {
                final active = overlayCtrl.active.value;
                if (active == null) return const SizedBox.shrink();
                return BookSeriesOverlay(
                  seriesIndexId: active.seriesIndexId,
                  title: active.title,
                  onClose: overlayCtrl.close,
                );
              }),
            ],
          );
        });
      },
    );
  }

  Widget _buildRight(BookMainController ctrl) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final customColors = theme.extension<CustomColors>();
        return ColoredBox(
          color: customColors?.mainContentBgColor ?? theme.colorScheme.surface,
          child: Obx(() {
            final key = ctrl.currentPageKey.value;
            if (key == 'library.book') {
              return const KeyedSubtree(
                key: ValueKey('book_list_book'),
                child: BookListPage(
                  key: ValueKey('book_list_book_page'),
                  type: 'book',
                  alertWhenNoSourcePath: true,
                ),
              );
            }
            if (key == 'library.comic') {
              return const KeyedSubtree(
                key: ValueKey('book_list_comic'),
                child: BookListPage(
                  key: ValueKey('book_list_comic_page'),
                  type: 'comic',
                  alertWhenNoSourcePath: true,
                ),
              );
            }
            if (key == 'library.favorite') {
              return const KeyedSubtree(
                key: ValueKey('book_list_favorite'),
                child: BookListPage(
                  key: ValueKey('book_list_favorite_page'),
                  type: '',
                  isFavorite: true,
                  alertWhenNoSourcePath: true,
                ),
              );
            }
            if (key == 'library.collection') {
              return const KeyedSubtree(
                key: ValueKey('book_collection_list'),
                child: BookCollectionListView(
                  key: ValueKey('book_collection_list_view'),
                ),
              );
            }
            if (key == 'library.history') {
              return const KeyedSubtree(
                key: ValueKey('book_list_history'),
                child: BookHistoryListView(
                  key: ValueKey('book_history_list_view'),
                ),
              );
            }
            if (key == 'library.file_view') {
              return const KeyedSubtree(
                key: ValueKey('book_folder_view'),
                child: PcFolderViewPage(moduleType: FolderViewModuleType.book),
              );
            }
            if (key == 'settings.source') {
              return const BookSourceSettingsView();
            }
            if (key == 'settings.cache_download') {
              return const BookCacheDownloadView();
            }
            if (key == 'book_list.custom') {
              return const BookCustomListListView();
            }
            return Center(child: Text('not_implemented_yet'.tr));
          }),
        );
      },
    );
  }
}
