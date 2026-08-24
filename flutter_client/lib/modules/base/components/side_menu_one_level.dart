import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/modules/home/views/pc_components/pc_app_window.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class OneLevelSideMenuItem {
  final String title;
  final String key;
  final IconData icon;

  const OneLevelSideMenuItem({
    required this.title,
    required this.key,
    required this.icon,
  });
}

class _CollapsedMenuItem extends StatefulWidget {
  final RxString currentKey;
  final OneLevelSideMenuItem item;
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

class _MenuTile extends StatefulWidget {
  final RxString currentKey;
  final OneLevelSideMenuItem item;
  final void Function(String key) onSelect;

  const _MenuTile({
    required this.currentKey,
    required this.item,
    required this.onSelect,
  });

  @override
  State<_MenuTile> createState() => _MenuTileState();
}

class _MenuTileState extends State<_MenuTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final selected = widget.currentKey.value == widget.item.key;
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
              onTap: () => widget.onSelect(widget.item.key),
              onHover: (v) => setState(() => _hovered = v),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // 与侧栏 AnimatedContainer 同步：collapsed 已展开但宽度仍为 64 时，
                    // 可用宽度约 24px，无法容纳 icon(18)+间距(10)，会固定溢出 4px。
                    const iconSize = 18.0;
                    const gap = 10.0;
                    const minForLabeledRow = iconSize + gap + 16;
                    if (constraints.maxWidth < minForLabeledRow) {
                      return Center(
                        child: Icon(
                          widget.item.icon,
                          size: iconSize,
                          color: iconColor,
                        ),
                      );
                    }
                    return Row(
                      children: [
                        Icon(
                          widget.item.icon,
                          size: iconSize,
                          color: iconColor,
                        ),
                        const SizedBox(width: gap),
                        Expanded(
                          child: Text(
                            widget.item.title,
                            maxLines: 1,
                            softWrap: false,
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

class OneLevelSideMenu extends StatelessWidget {
  final RxString currentKey;
  final void Function(String key) onSelect;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;
  final bool showCollapseToggle;
  final String? toggleExpandTooltip;
  final String? toggleCollapseTooltip;
  final Widget? headerTrailing;
  final double topPlaceholderHeight;
  final List<OneLevelSideMenuItem> items;

  const OneLevelSideMenu({
    super.key,
    required this.currentKey,
    required this.onSelect,
    required this.items,
    this.collapsed = false,
    this.onToggleCollapse,
    this.showCollapseToggle = true,
    this.toggleExpandTooltip,
    this.toggleCollapseTooltip,
    this.headerTrailing,
    this.topPlaceholderHeight = PcAppWindow.titleBarHeight,
  });

  @override
  Widget build(BuildContext context) {
    final showHeader = showCollapseToggle || headerTrailing != null;
    final customColors = Theme.of(context).extension<CustomColors>();
    return Container(
      color: customColors?.leftTreeBgColor,
      child: Column(
        children: [
          SizedBox(height: topPlaceholderHeight),
          if (showHeader)
            SizedBox(
              height: 40,
              child: Center(
                child: Row(
                  children: [
                    if (showCollapseToggle)
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
                      if (showCollapseToggle) const SizedBox(width: 6),
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
                  ...items.map(
                    (it) => Tooltip(
                      message: it.title,
                      child: _CollapsedMenuItem(
                        currentKey: currentKey,
                        item: it,
                        onSelect: onSelect,
                      ),
                    ),
                  )
                else
                  ...items.map(
                    (it) => _MenuTile(
                      currentKey: currentKey,
                      item: it,
                      onSelect: onSelect,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
