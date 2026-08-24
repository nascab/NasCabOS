import 'package:NasCabOS/utils/dimens_util.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class CustomUserCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggleActive;
  const CustomUserCard({
    super.key,
    required this.user,
    required this.selected,
    required this.onTap,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = user['type']?.toString() ?? 'user';
    // final isActive = (user['is_active'] == true);
    return Card(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DimensUtil.containerCardRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(DimensUtil.containerCardRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.onSurface.withValues(
                  alpha: 0.6,
                ),
                child: Icon(Icons.person, color: theme.colorScheme.surface),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 用户类型容器
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start, // 垂直居中
                      crossAxisAlignment: CrossAxisAlignment.center, // 水平居中
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(4, 2, 4, 3),
                          decoration: BoxDecoration(
                            color: type == "super_admin"
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface.withValues(
                                    alpha: 0.5,
                                  ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          // 用户类型（user, admin, super_admin）
                          child: Text(
                            "user_type_$type".tr,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: DimensUtil.textSmall,
                            ),
                          ),
                        ),

                        // const Spacer(),
                        // Switch(value: isActive, onChanged: onToggleActive),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      user['username']?.toString() ?? '',
                      style: theme.textTheme.bodyMedium,
                    ),
                    if ((user['phone'] as String?)?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${'user_mgmt_phone'.tr}: ${user['phone']}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.65,
                          ),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if ((user['user_remark'] as String?)?.trim().isNotEmpty ==
                        true) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${'user_mgmt_remark'.tr}: ${user['user_remark']}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.65,
                          ),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
