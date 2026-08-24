import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'server_list_controller.dart';
import '../../beans/server_info_bean.dart';
import 'server_item_view.dart';
import 'server_item_add_view.dart';
import '../../../../modules/base/components.dart';
import '../server_add/server_add_view.dart';
import '../server_add/server_add_controller.dart';
import '../admin_create/admin_create_view.dart';
import '../admin_create/admin_create_controller.dart';
import '../../../../core/bg/background_controller.dart';
import '../../../../core/theme/dark_theme.dart';
import '../../../../utils/dimens_util.dart';
import '../../../../utils/device_utils.dart';

/// 服务器列表视图
class ServerListView extends GetView<ServerListController> {
  const ServerListView({super.key});

  @override
  Widget build(BuildContext context) {
    // 初始化Controller并注入
    return GetBuilder<ServerListController>(
      init: ServerListController(),
      builder: (controller) {
        return _ServerListViewContent();
      },
    );
  }
}

class _ServerListViewContent extends StatelessWidget {
  final ServerListController serverListController =
      ServerListController.instance;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: darkTheme,
      child: Builder(
        builder: (context) {
          return Obx(() {
            final ServerListController listCtrl =
                Get.find<ServerListController>();
            final bool blockRootPop = DeviceUtils.isPhone(context) &&
                (listCtrl.showAddServerView.value ||
                    listCtrl.showCreateAdminView.value);
            return PopScope(
              canPop: !blockRootPop,
              onPopInvoked: (bool didPop) {
                if (didPop) return;
                if (!DeviceUtils.isPhone(context)) return;
                final c = Get.find<ServerListController>();
                if (c.showAddServerView.value &&
                    Get.isRegistered<ServerAddController>()) {
                  Get.find<ServerAddController>().goBack();
                  return;
                }
                if (c.showCreateAdminView.value &&
                    Get.isRegistered<AdminCreateController>()) {
                  Get.find<AdminCreateController>().goBack();
                }
              },
              child: Scaffold(
                body: Container(
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage(
                        BackgroundController.instance.loginBgUrl,
                      ),
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: Center(
                    child: Container(child: _buildCenterView(context)),
                  ),
                ),
              ),
            );
          });
        },
      ),
    );
  }

  ///根据变量 构建合适的view
  Widget _buildCenterView(BuildContext context) {
    final ServerListController controller = Get.find<ServerListController>();

    /// 构建添加服务器界面
    if (controller.showAddServerView.value) {
      return ServerAddView();
    }

    /// 构建创建管理员界面
    if (controller.showCreateAdminView.value) {
      return AdminCreateView();
    }
    return _buildServerListWidget(context, controller);
  }

  /// 构建服务器列表组件
  Widget _buildServerListWidget(
    BuildContext context,
    ServerListController serverListController,
  ) {
    // 使用响应式状态获取服务器列表
    final List<ServerInfoBean> savedServers =
        serverListController.savedServersRx;
    final List<ServerInfoBean> discoveredServers =
        serverListController.discoveredServersRx;

    // 添加一个空对象用于添加服务器按钮
    final List<ServerInfoBean?> savedServerItems = [
      ...savedServers,
      null, // 最后一个为null，表示添加服务器按钮.
    ];

    final theme = Theme.of(context);
    // 使用 context.width 判断屏幕宽度，适配多端

    return Container(
      constraints: DimensUtil.authCenterMaxWidthConstraints(context),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(
          DimensUtil.authCenterCardRadius(context),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题 登录nascab服务器（优先使用自定义欢迎语）
          CustomAuthHeader(
            title: 'server_listTitle'.tr,
            icon: Icons.cloud_done,
            actions: [CustomLanguageSelector(tooltip: 'language'.tr)],
          ),
          // 服务器列表
          Expanded(
            child: Scrollbar(
              // 优化Scrollbar配置
              thumbVisibility: true, // 始终显示滚动条（PC端）
              trackVisibility: true, // 显示滚动轨道
              interactive: true, // 允许交互（PC端拖拽）
              thickness: DimensUtil.scrollbarThickness, // 滚动条宽度
              radius: DimensUtil.scrollbarRadius, // 圆角
              child: ListView(
                shrinkWrap: true,
                primary: true, // 启用PrimaryScrollController
                padding: EdgeInsets.zero, // 移除内边距
                children: [
                  // 已保存的服务器区域
                  _buildServerSection(
                    context,
                    serverListController,
                    title: 'server_saved'.tr,
                    serverItems: savedServerItems,
                  ),

                  // 自动发现的服务器区域
                  if (discoveredServers.isNotEmpty)
                    _buildServerSection(
                      context,
                      serverListController,
                      title: 'server_scanned'.tr,
                      serverItems: discoveredServers,
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: Dimens.s12),
        ],
      ),
    );
  }

  /// 构建服务器区域组件
  Widget _buildServerSection(
    BuildContext context,
    ServerListController serverListController, {
    required String title,
    required List<ServerInfoBean?> serverItems,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 区域标题
        Padding(
          padding: EdgeInsets.fromLTRB(
            Dimens.s20,
            Dimens.s16,
            Dimens.s20,
            Dimens.s8,
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: Dimens.t14,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
        // 服务器列表
        ...serverItems.map((serverItem) {
          // 最后一个item是添加服务器按钮（仅适用于已保存服务器区域）
          if (serverItem == null) {
            // 添加服务器
            return AddServerItemView(
              onTap: () {
                serverListController.goToAddServerView(null);
              },
            );
          }
          // 服务器列表项
          return ServerItemView(
            serverItem: serverItem,
            onTap: () {
              serverListController.handleServerTap(context, serverItem);
            },
            onSettingsTap: (String value) =>
                serverListController.handleMenuSelection(value, serverItem),
          );
        }),
        if (serverItems.any((e) => e == null))
          AddServerItemView(
            icon: Icons.qr_code_2,
            title: 'server_add_by_pair_code_title'.tr,
            onTap: () {
              serverListController.addServerByPairCode();
            },
          ),
      ],
    );
  }
}
