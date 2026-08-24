import 'dart:async';

import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:get/get.dart';
import '../../base/components/app_item_action_sheet.dart';
import '../../base/components/custom_album.dart';
import '../../base/components/custom_expandable_search_bar.dart';
import '../../base/components/custom_context_menu_item.dart';
import '../../base/components/custom_extended_image.dart';
import '../../base/components/custom_no_data.dart';
import '../../files/views/pc_components/pc_file_drop_target.dart';
import '../../transfer/controllers/download_controller.dart';
import '../../transfer/controllers/upload_parts/upload_web_folder_drop_target_wrapper.dart';
import '../../../core/routes/app_routes.dart';
import '../../../utils/context_menu_util.dart';
import '../../../utils/device_utils.dart';
import '../../base/components/custom_popup_select_button.dart';
import '../controllers/encrypted_space_controller.dart';
import '../../base/components/custom_bordered_icon_button.dart';

part 'parts/encrypted_space_list_part.dart';
part 'parts/encrypted_space_detail_part.dart';
part 'parts/encrypted_space_space_grid_part.dart';
part 'parts/encrypted_space_space_grid_card_part.dart';
part 'parts/encrypted_space_file_grid_part.dart';
part 'parts/encrypted_space_file_card_part.dart';
part 'parts/app_encrypted_space_view_part.dart';
part 'parts/app_encrypted_space_list_part.dart';
part 'parts/app_encrypted_space_space_grid_part.dart';
part 'parts/app_encrypted_space_detail_part.dart';

class EncryptedSpaceView extends GetView<EncryptedSpaceController> {
  const EncryptedSpaceView({super.key});

  void _openSpaceMobile(
    BuildContext context,
    EncryptedSpaceController ctrl,
    Map<String, dynamic> space,
  ) {
    ctrl.openSpaceFlow(
      context,
      space,
      onSuccess: (data) {
        final id = int.tryParse('${space['id'] ?? ''}') ?? 0;
        if (id <= 0) return;
        final token = (data['token'] ?? '').toString().trim();
        if (token.isEmpty) return;
        final name = (space['space_name'] ?? '').toString().trim();
        final path =
            (space['folderPath'] ??
                    space['folder_path'] ??
                    space['path'] ??
                    space['space_path'] ??
                    '')
                .toString()
                .trim();

        final active = EncryptedSpaceActiveSpace(
          spaceId: id,
          token: token,
          name: name,
          path: path,
        );
        ctrl.openActiveSpace(active);
        Get.to(
          () => AppEncryptedSpaceDetailPage(active: active, ctrl: ctrl),
          preventDuplicates: false,
        );
      },
    );
  }

  void _openSpace(
    BuildContext context,
    EncryptedSpaceController ctrl,
    Map<String, dynamic> space,
  ) {
    ctrl.openSpaceFlow(
      context,
      space,
      onSuccess: (data) {
        final id = int.tryParse('${space['id'] ?? ''}') ?? 0;
        if (id <= 0) return;
        final token = (data['token'] ?? '').toString().trim();
        if (token.isEmpty) return;
        final name = (space['space_name'] ?? '').toString().trim();
        final path =
            (space['folderPath'] ??
                    space['folder_path'] ??
                    space['path'] ??
                    space['space_path'] ??
                    '')
                .toString()
                .trim();
        ctrl.openActiveSpace(
          EncryptedSpaceActiveSpace(
            spaceId: id,
            token: token,
            name: name,
            path: path,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<EncryptedSpaceController>(
      init: EncryptedSpaceController(),
      builder: (ctrl) {
        if (DeviceUtils.isMobile) {
          return AppEncryptedSpaceView(
            ctrl: ctrl,
            onOpen: (space) => _openSpaceMobile(context, ctrl, space),
          );
        }

        final list = Column(
          children: [
            SizedBox(height: 5),
            _EncryptedSpaceListTopBar(ctrl: ctrl),
            Expanded(
              child: _EncryptedSpaceSpaceGrid(
                ctrl: ctrl,
                onOpen: (space) => _openSpace(context, ctrl, space),
              ),
            ),
          ],
        );

        final customColors = Theme.of(context).extension<CustomColors>();
        return Scaffold(
          body: Container(
            decoration: BoxDecoration(color: customColors?.mainContentBgColor),
            child: Stack(
              children: [
                list,
                Obx(() {
                  final active = ctrl.activeSpace.value;
                  if (active == null) return const SizedBox.shrink();
                  return _EncryptedSpaceDetailOverlay(
                    active: active,
                    onClose: ctrl.closeActiveSpace,
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}
