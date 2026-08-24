import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../beans/server_info_bean.dart';
import '../../../../utils/dimens_util.dart';

import '../../../../core/theme/custom_colors.dart';
import '../../../../modules/base/components/custom_tag.dart';

/// 服务器列表项组件
class ServerItemView extends StatelessWidget {
  final ServerInfoBean serverItem;
  final VoidCallback? onTap;
  final Function(String)? onSettingsTap;

  const ServerItemView({
    super.key,
    required this.serverItem,
    this.onTap,
    this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = Theme.of(context).extension<CustomColors>();
    final pairCode = (serverItem.pairCode ?? '').trim();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 0),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DimensUtil.nestedCardRadius),
        ),
        color: customColors!.nestedCardColor,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DimensUtil.nestedCardRadius),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // 服务器平台图标
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(),
                  child: Image.asset(
                    _getPlatformIcon(serverItem.serverPlatform),
                  ),
                ),
                const SizedBox(width: 16),
                // 服务器信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 服务器名称 - 添加本地服务器标识
                      Row(
                        children: [
                          if (serverItem.isLocalServer)
                            // 本机 提示标签
                            CustomTag(
                              text: 'server_localServer'.tr,
                              backgroundColor: theme.colorScheme.secondary,
                            ),
                          Expanded(
                            child: Text(
                              //服务器名称和hostname
                              serverItem.displayHostName +
                                  (serverItem.serverName.isNotEmpty
                                      ? ' (${serverItem.serverName})'
                                      : ''),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // 服务器地址
                      Text(
                        serverItem.isP2p ? 'P2P' : serverItem.serverUrl,
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (pairCode.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'server_pair_code_display'.trParams({
                            'code': _maskPairCode(pairCode),
                          }),
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.7,
                            ),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 4),
                      // 自动发现或用户名
                      if (serverItem.username != null)
                        Text(
                          _getShowUsername(),
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.7,
                            ),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                // 选择箭头或设置图标
                if (serverItem.isAutoScanned)
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  )
                // 已保存的服务器显示设置图标
                else
                  // 弹出菜单
                  PopupMenuButton<String>(
                    tooltip: "",
                    icon: SizedBox(
                      width: 30,
                      height: 30,
                      child: Icon(
                        Icons.more_vert,
                        size: 20,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    onSelected: (String value) {
                      // 传递菜单选项值给onSettingsTap回调
                      if (onSettingsTap != null) {
                        onSettingsTap!(value);
                      }
                    },
                    itemBuilder: (BuildContext context) => [
                      PopupMenuItem<String>(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 20),
                            SizedBox(width: 8),
                            Text('edit'.tr),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete,
                              size: 20,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'delete'.tr,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getShowUsername() {
    if (serverItem.username != null) {
      return '${'username'.tr}:${serverItem.username}';
    }
    return "";
  }

  /// 根据服务器平台获取对应的图标路径
  String _getPlatformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'darwin':
        return 'assets/home/server_mac.png';
      case 'win32':
        return 'assets/home/server_windows.png';
      case 'linux':
        return 'assets/home/server_linux.png';
      default:
        return 'assets/home/server_linux.png'; // 默认使用linux图标
    }
  }

  String _maskPairCode(String code) {
    final s = code.trim();
    if (s.isEmpty) return s;
    if (s.length <= 2) return '*' * s.length;
    final left = (s.length - 2) ~/ 2;
    final right = left + 2;
    return s.replaceRange(left, right, '**');
  }
}
