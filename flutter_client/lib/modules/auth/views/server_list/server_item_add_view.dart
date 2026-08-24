import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/theme/custom_colors.dart';
import '../../../../utils/dimens_util.dart';

/// 添加服务器列表项组件
class AddServerItemView extends StatelessWidget {
  final VoidCallback? onTap;
  final IconData icon;
  final String title;

  const AddServerItemView({
    super.key,
    this.onTap,
    this.icon = Icons.add,
    this.title = '',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = Theme.of(context).extension<CustomColors>();
    final titleText = title.isNotEmpty ? title : 'server_add'.tr;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 0),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DimensUtil.nestedCardRadius),
        ),
        color: customColors?.nestedCardColor, // 使用主题主色
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DimensUtil.nestedCardRadius),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // 加号图标
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(
                      alpha: 0.6,
                    ), // 使用主题主色
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 32, color: Colors.white),
                ),
                const SizedBox(width: 16),
                // 添加服务器文字
                Expanded(
                  child: Text(
                    titleText,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
