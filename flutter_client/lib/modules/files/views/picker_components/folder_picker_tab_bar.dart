import 'package:flutter/material.dart';
import 'package:get/get.dart';

class FolderPickerTabBar extends StatelessWidget {
  const FolderPickerTabBar({
    super.key,
    required this.currentTab,
    required this.tabController,
  });

  final RxInt currentTab;
  final TabController tabController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TabBar(
      tabs: [
        Tab(text: 'folder_picker_recent'.tr),
        Tab(text: 'folder_picker_file_system'.tr),
      ],
      onTap: (index) {
        currentTab.value = index;
        tabController.index = index;
      },
      indicatorColor: theme.primaryColor,
      indicatorSize: TabBarIndicatorSize.tab,
      controller: tabController,
    );
  }
}
