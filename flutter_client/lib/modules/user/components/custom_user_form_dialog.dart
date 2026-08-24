import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../base/components/custom_text_field.dart';
import '../controllers/custom_user_form_controller.dart';

class CustomUserFormDialog extends StatelessWidget {
  final Map<String, dynamic>? user;
  final Future<bool> Function(
    String username,
    String password, {
    String? userRemark,
    String? phone,
  })
  onCreate;
  final Future<bool> Function(
    int id, {
    String? username,
    String? password,
    String? userRemark,
    String? phone,
  })
  onUpdate;
  const CustomUserFormDialog({
    super.key,
    this.user,
    required this.onCreate,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final isEdit = user != null;
    return GetBuilder<CustomUserFormController>(
      init: CustomUserFormController(
        user: user,
        onCreate: onCreate,
        onUpdate: onUpdate,
      ),
      builder: (ctrl) {
        return AlertDialog(
          title: Text(isEdit ? 'user_mgmt_edit'.tr : 'user_mgmt_create'.tr),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomTextField(
                  controller: ctrl.usernameController.value,
                  labelText: 'username'.tr,
                  validator: ctrl.validateUsername,
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: ctrl.passwordController.value,
                  obscureText: true,
                  labelText: isEdit
                      ? 'user_mgmt_new_password'.tr
                      : 'password'.tr,
                  validator: ctrl.validatePassword,
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: ctrl.phoneController.value,
                  keyboardType: TextInputType.phone,
                  labelText: 'user_mgmt_phone_label'.tr,
                  validator: ctrl.validatePhone,
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: ctrl.remarkController.value,
                  maxLines: 2,
                  labelText: 'user_mgmt_remark_label'.tr,
                  validator: ctrl.validateRemark,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('cancel'.tr),
            ),
            ElevatedButton(onPressed: ctrl.submitForm, child: Text('save'.tr)),
          ],
        );
      },
    );
  }
}
