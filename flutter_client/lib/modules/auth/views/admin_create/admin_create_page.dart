import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/bg/background_controller.dart';
import '../../../../core/theme/dark_theme.dart';
import 'admin_create_controller.dart';
import 'admin_create_view.dart';

/// 管理员创建视图
class AdminCreatePage extends GetView<AdminCreateController> {
  const AdminCreatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<AdminCreateController>(
      init: AdminCreateController(),
      builder: (controller) {
        return _buildContent(context, controller);
      },
    );
  }

  Widget _buildContent(BuildContext context, AdminCreateController controller) {
    return Theme(
      data: darkTheme,
      child: Builder(
        builder: (context) {
          return Scaffold(
            body: Obx(
              () => Container(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage(BackgroundController.instance.loginBgUrl),
                    fit: BoxFit.cover,
                  ),
                ),
                child: _buildCenterView(context),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCenterView(BuildContext context) {
    return AdminCreateView();
  }
}
