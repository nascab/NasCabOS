import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../list/view/book_list_page.dart';

class BookCustomListOverlay extends StatelessWidget {
  final int listId;
  final String name;
  final VoidCallback onClose;

  const BookCustomListOverlay({
    super.key,
    required this.listId,
    required this.name,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final customColors = Theme.of(context).extension<CustomColors>();

    return Positioned.fill(
      child: Material(
        color: customColors?.mainContentBgColor,
        child: SafeArea(
          child: Column(
            children: [
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Get.theme.dividerColor),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'back'.tr,
                      onPressed: onClose,
                      icon: const Icon(Icons.arrow_back_ios_outlined),
                    ),
                    Expanded(
                      child: Text(
                        '${'book_menu_book_list_custom'.tr}-$name',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Get.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: BookListPage(
                  key: ValueKey('book_custom_list_$listId'),
                  type: '',
                  listId: listId,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
