import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../base/components/custom_container.dart';
import '../../base/components/custom_divider.dart';
import '../../base/components/custom_title_bar.dart';
import '../../../core/theme/theme_manager.dart';

class ThemeSelectorView extends StatelessWidget {
  const ThemeSelectorView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: CustomTitleBar(title: 'settings_theme'.tr, showBackButton: true),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'settings_theme_title'.tr,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            CustomContainer(
              child: Column(
                children: [
                  _buildThemeOption(
                    context,
                    'settings_theme_light_mode'.tr,
                    Icons.light_mode_outlined,
                    ThemeMode.light,
                  ),
                  const CustomDivider(),
                  _buildThemeOption(
                    context,
                    'settings_theme_dark_mode'.tr,
                    Icons.dark_mode_outlined,
                    ThemeMode.dark,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext context,
    String title,
    IconData icon,
    ThemeMode mode,
  ) {
    final theme = Theme.of(context);
    final currentThemeMode = ThemeManager().getThemeMode();
    final isSelected = currentThemeMode == mode;

    return ListTile(
      leading: Icon(icon),
      title: Text(
        title,
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: isSelected ? Icon(Icons.check_circle_outlined) : null,
      onTap: () async {
        // 切换主题
        Get.changeThemeMode(mode);
        // 保存主题设置
        await ThemeManager().saveThemeMode(mode);
      },
    );
  }
}
