import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/modules/base/components.dart';
import 'package:NasCabOS/modules/home/views/pc_components/pc_app_window.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SideMenuTwoLevelGroup {
  final String title;
  final IconData icon;
  final RxBool expanded;
  final List<TwoLevelSideMenuItem> items;

  const SideMenuTwoLevelGroup({
    required this.title,
    required this.icon,
    required this.expanded,
    required this.items,
  });
}

class TwoLevelSideMenuItem {
  final String title;
  final String key;
  final IconData icon;

  const TwoLevelSideMenuItem({
    required this.title,
    required this.key,
    required this.icon,
  });
}

class _CollapsedMenuItem extends StatefulWidget {
  final RxString currentKey;
  final TwoLevelSideMenuItem item;
  final void Function(String key) onSelect;

  const _CollapsedMenuItem({
    required this.currentKey,
    required this.item,
    required this.onSelect,
  });

  @override
  State<_CollapsedMenuItem> createState() => _CollapsedMenuItemState();
}

class _CollapsedMenuItemState extends State<_CollapsedMenuItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final selected = widget.currentKey.value == widget.item.key;
      final bg = selected
          ? theme.colorScheme.primary
          : (_hovered
                ? theme.colorScheme.onSurface.withValues(alpha: 0.06)
                : Colors.transparent);
      final fg = selected
          ? Colors.white
          : theme.colorScheme.onSurface.withValues(
              alpha: _hovered ? 0.9 : 0.75,
            );

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => widget.onSelect(widget.item.key),
              onHover: (v) => setState(() => _hovered = v),
              child: Center(child: Icon(widget.item.icon, size: 20, color: fg)),
            ),
          ),
        ),
      );
    });
  }
}

class _SubMenuTile extends StatefulWidget {
  final RxString currentKey;
  final String itemKey;
  final String title;
  final IconData icon;
  final void Function(String key) onSelect;

  const _SubMenuTile({
    required this.currentKey,
    required this.itemKey,
    required this.title,
    required this.icon,
    required this.onSelect,
  });

  @override
  State<_SubMenuTile> createState() => _SubMenuTileState();
}

class _SubMenuTileState extends State<_SubMenuTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final selected = widget.currentKey.value == widget.itemKey;
      final bg = selected
          ? theme.colorScheme.primary
          : (_hovered
                ? theme.colorScheme.onSurface.withValues(alpha: 0.01)
                : Colors.transparent);
      final fg = selected ? Colors.white : theme.colorScheme.onSurface;
      final iconColor = selected
          ? Colors.white
          : fg.withValues(alpha: _hovered ? 0.9 : 0.75);

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => widget.onSelect(widget.itemKey),
              onHover: (v) => setState(() => _hovered = v),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const iconSize = 18.0;
                    const gap = 10.0;
                    // 展开动画初期侧栏仍窄（如 64px），扣掉本组件内外边距后 Row 常不足 icon+间距
                    if (constraints.maxWidth < iconSize + gap) {
                      return Center(
                        child: Icon(
                          widget.icon,
                          size: iconSize,
                          color: iconColor,
                        ),
                      );
                    }
                    return Row(
                      children: [
                        Icon(widget.icon, size: iconSize, color: iconColor),
                        const SizedBox(width: gap),
                        Expanded(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: fg,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class TwoLevelSideMenu extends StatelessWidget {
  final RxString currentKey;
  final void Function(String key) onSelect;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;
  final String? toggleExpandTooltip;
  final String? toggleCollapseTooltip;
  final Widget? headerTrailing;
  final double topPlaceholderHeight;
  final List<SideMenuTwoLevelGroup> groups;
  const TwoLevelSideMenu({
    super.key,
    required this.currentKey,
    required this.onSelect,
    required this.groups,
    this.collapsed = false,
    this.onToggleCollapse,
    this.toggleExpandTooltip,
    this.toggleCollapseTooltip,
    this.headerTrailing,
    this.topPlaceholderHeight = PcAppWindow.titleBarHeight,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flatItems = groups.expand((g) => g.items).toList(growable: false);
    final customColors = Theme.of(context).extension<CustomColors>();

    return Container(
      color: customColors?.leftTreeBgColor,
      child: Column(
        children: [
          SizedBox(height: topPlaceholderHeight),
          SizedBox(
            height: 40,
            child: Center(
              child: Row(
                children: [
                  Tooltip(
                    message: collapsed
                        ? (toggleExpandTooltip ?? '')
                        : (toggleCollapseTooltip ?? ''),
                    child: IconButton(
                      onPressed: onToggleCollapse,
                      icon: Icon(
                        collapsed ? Icons.chevron_right : Icons.wrap_text,
                      ),
                    ),
                  ),
                  if (!collapsed) ...[
                    const SizedBox(width: 6),
                    if (headerTrailing != null)
                      Expanded(child: headerTrailing!),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                if (collapsed)
                  ...flatItems.map(_collapsedItem)
                else
                  ...groups.expand(
                    (g) => [
                      _parentMenu(
                        theme,
                        title: g.title,
                        icon: g.icon,
                        expanded: g.expanded,
                        items: g.items,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _parentMenu(
    ThemeData theme, {
    required String title,
    required IconData icon,
    required RxBool expanded,
    required List<TwoLevelSideMenuItem> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Obx(() {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: InkWell(
              onTap: () => expanded.value = !expanded.value,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    // Icon(icon, size: 18, color: theme.colorScheme.onSurface),
                    // const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        maxLines: 1,
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ),
                    Icon(
                      expanded.value ? Icons.expand_more : Icons.chevron_right,
                      size: 18,
                      color: theme.colorScheme.onSurface,
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        Obx(() {
          if (!expanded.value) return const SizedBox.shrink();
          return Column(
            children: items
                .map(
                  (it) => _subMenuItem(
                    theme,
                    title: it.title,
                    key: it.key,
                    icon: it.icon,
                  ),
                )
                .toList(),
          );
        }),
        SizedBox(height: 4),
        CustomDivider(color: theme.dividerColor.withValues(alpha: 0.1)),
      ],
    );
  }

  Widget _collapsedItem(TwoLevelSideMenuItem it) {
    return Tooltip(
      message: it.title,
      child: _CollapsedMenuItem(
        currentKey: currentKey,
        item: it,
        onSelect: onSelect,
      ),
    );
  }

  Widget _subMenuItem(
    ThemeData theme, {
    required String title,
    required String key,
    required IconData icon,
  }) {
    return _SubMenuTile(
      currentKey: currentKey,
      itemKey: key,
      title: title,
      icon: icon,
      onSelect: onSelect,
    );
  }
}
