import 'package:NasCabOS/utils/device_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'custom_divider.dart';

/// 认证模块通用的头部组件
class CustomAuthHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onBack;
  final List<Widget>? actions;
  final bool showDivider;

  const CustomAuthHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.onBack,
    this.actions,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = DeviceUtils.isPhone(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20 + (isMobile ? context.mediaQueryPadding.top : 0),
            20,
            20,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 返回按钮
              if (onBack != null) ...[
                IconButton(
                  onPressed: onBack,
                  icon: Icon(
                    Icons.arrow_back,
                    color: theme.colorScheme.onSurface,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              // 图标
              if (icon != null) ...[
                Icon(icon, color: theme.colorScheme.onSurface, size: 24),
                const SizedBox(width: 12),
              ],
              // 标题
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    if ((subtitle ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!.trim(),
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // 右侧操作按钮
              if (actions != null) ...actions!,
            ],
          ),
        ),
        // 分割线
        if (showDivider)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: CustomDivider(
              color: theme.dividerColor,
              height: 1,
              thickness: 1,
            ),
          ),
      ],
    );
  }
}
