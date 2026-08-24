import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../list/view/book_list_page.dart';
import '../../models/book_collection_model.dart';

class BookCollectionBookOverlay extends StatelessWidget {
  final BookCollectionItem collection;
  final VoidCallback onClose;

  const BookCollectionBookOverlay({
    super.key,
    required this.collection,
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
                        "${'book_collection_title'.tr}-${collection.name}",
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
                  key: ValueKey('collection_book_list_${collection.id}'),
                  type: '',
                  collectionId: collection.id,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
