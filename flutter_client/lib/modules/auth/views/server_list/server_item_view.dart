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
  final VoidCallback? onEditConnectPref;
  final bool showMoveToTop;

  const ServerItemView({
    super.key,
    required this.serverItem,
    this.onTap,
    this.onSettingsTap,
    this.onEditConnectPref,
    this.showMoveToTop = false,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 第一行：平台小图标 + 本机标识 + 服务器名称（宽度不足时压缩）+ 更多菜单
                Row(
                  children: [
                    // 服务器平台小图标
                    Image.asset(
                      _getPlatformIcon(serverItem.serverPlatform),
                      width: 24,
                      height: 24,
                    ),
                    const SizedBox(width: 8),
                    // 本机 提示标签
                    if (serverItem.isLocalServer)
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
                    const SizedBox(width: 4),
                    // 选择箭头（自动发现）或更多菜单（已保存）
                    if (serverItem.isAutoScanned)
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      )
                    else
                      // 弹出菜单
                      PopupMenuButton<String>(
                        tooltip: "",
                        padding: EdgeInsets.zero,
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
                          // 远程连接偏好设置（仅有配对码时显示）
                          if (pairCode.isNotEmpty)
                            PopupMenuItem<String>(
                              value: 'remote_connect_pref',
                              child: Row(
                                children: [
                                  Icon(Icons.settings_ethernet, size: 20),
                                  SizedBox(width: 8),
                                  Text('server_remote_connect_pref'.tr),
                                ],
                              ),
                            ),
                          // 移动到列表顶部（列表多于一个已保存服务器时显示）
                          if (showMoveToTop)
                            PopupMenuItem<String>(
                              value: 'move_to_top',
                              child: Row(
                                children: [
                                  Icon(Icons.vertical_align_top, size: 20),
                                  SizedBox(width: 8),
                                  Text('server_move_to_top'.tr),
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
                const SizedBox(height: 4),
                // 服务器地址
                Text(
                  serverItem.isP2p ? 'P2P' : serverItem.serverUrl,
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
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
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // P2P 连接偏好（跟随服务器 item 持久化），编辑图标紧跟文字；
                  // Flexible：空间充足时文字取实际宽度，不足时收缩省略、不溢出
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${'server_remote_connect_pref'.tr}: '
                          '${serverItem.p2pRelayPreferred
                              ? 'remote_pref_relay_first'.tr
                              : 'remote_pref_direct_first'.tr}',
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.7,
                            ),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: Tooltip(
                          message: 'edit'.tr,
                          child: InkWell(
                            onTap: onEditConnectPref,
                            customBorder: const CircleBorder(),
                            child: Icon(
                              Icons.edit,
                              size: 16,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                // 自动发现或用户名
                if (serverItem.username != null)
                  Text(
                    _getShowUsername(),
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
