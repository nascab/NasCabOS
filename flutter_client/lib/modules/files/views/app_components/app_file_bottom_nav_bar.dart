import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AppFileBottomNavBar extends StatelessWidget {
  const AppFileBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onIndexChanged,
  });

  final int currentIndex;
  final ValueChanged<int> onIndexChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: onIndexChanged,
        selectedItemColor: theme.colorScheme.primary,
        unselectedItemColor: theme.colorScheme.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.folder_open_outlined),
            label: 'app_folder'.tr,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.star_outline_outlined),
            label: 'favorites'.tr,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.history_outlined),
            label: 'recent'.tr,
          ),
        ],
      ),
    );
  }
}
