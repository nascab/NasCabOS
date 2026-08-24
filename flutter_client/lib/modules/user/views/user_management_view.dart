import 'dart:convert';

import 'package:NasCabOS/modules/base/components/custom_switch.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/user_management_controller.dart';
import '../components/custom_user_card.dart';
import '../components/custom_user_form_dialog.dart';
import '../components/custom_login_record_card.dart';
import '../components/custom_user_info_card.dart';
import '../../base/components/custom_empty_state.dart';
import '../../base/components/custom_text_field.dart';
import '../../base/components/custom_expandable_search_bar.dart';
import '../components/custom_permission_editor.dart';
import '../../files/views/folder_picker_dialog.dart';
import '../../transfer/views/file_log/file_log_item.dart';
import '../../../utils/dialog_util.dart';
import '../../../utils/dimens_util.dart';

part 'parts/user_management_detail_panel.dart';
part 'parts/user_management_login_records_tab.dart';
part 'parts/user_management_permissions_tab.dart';
part 'parts/user_management_scaffold.dart';
part 'parts/app_user_management_scaffold.dart';
part 'parts/user_management_sidebar.dart';
part 'parts/user_management_sidebar_header.dart';
part 'parts/user_management_twofa_tab.dart';
part 'parts/user_management_user_list.dart';

class UserManagementView extends GetView<UserManagementController> {
  const UserManagementView({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<UserManagementController>(
      init: UserManagementController(),
      builder: (ctrl) {
        return _UserManagementScaffold(ctrl: ctrl);
      },
    );
  }
}
