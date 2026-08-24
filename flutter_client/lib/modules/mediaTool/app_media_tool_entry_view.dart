import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/user/current_user_controller.dart';
import '../base/views/app_base_page.dart';
import 'app_media_tool_items.dart';
import 'app_media_tool_subpage.dart';

class AppMediaToolEntryView extends StatelessWidget {
  const AppMediaToolEntryView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = _groupedItems();

    return AppBasePage(
      title: 'app_media_tool'.tr,
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final g = groups[index];
                  return _Section(title: g.$1.tr, children: g.$2, theme: theme);
                }, childCount: groups.length),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<(String, List<AppMediaToolItem>)> _groupedItems() {
    final isAdmin = CurrentUserController.instance.isAdmin;
    final items = isAdmin
        ? appMediaToolItems
        : appMediaToolItems.where((it) => it.key == 'image.compress').toList();

    final map = <String, List<AppMediaToolItem>>{};
    for (final it in items) {
      map.putIfAbsent(it.groupTitleKey, () => []).add(it);
    }

    final keys = <String>[
      'media_tool_menu_image',
      'media_tool_menu_video',
      'media_tool_menu_audio',
      'media_tool_menu_other',
    ];
    return keys
        .where((k) => map.containsKey(k))
        .map((k) => (k, map[k] ?? const []))
        .toList(growable: false);
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<AppMediaToolItem> children;
  final ThemeData theme;

  const _Section({
    required this.title,
    required this.children,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ...children.map((e) => AppMediaToolMenuCard(item: e)),
        const SizedBox(height: 16),
      ],
    );
  }
}

class AppMediaToolMenuCard extends StatelessWidget {
  final AppMediaToolItem item;
  const AppMediaToolMenuCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Get.to(() => AppMediaToolSubPage(pageKey: item.key)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(item.icon, color: colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.titleKey.tr,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.subtitleKey.tr,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.70),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.chevron_right_outlined,
                color: colorScheme.onSurface.withValues(alpha: 0.50),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
