import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:get/get.dart';
import '../../../../../core/api/api_controller.dart';
import '../../../../../core/user/current_user_controller.dart';
import '../../../../../utils/device_utils.dart';
import '../../../../base/components/custom_checkbox.dart';
import '../../../../base/components/custom_context_menu_item.dart';
import '../../../../base/components/custom_extended_image.dart';
import '../../controller/ai_faces_controller.dart';
import '../../models/ai_faces_models.dart';
import '../../../../../utils/context_menu_util.dart';
import '../../../../../utils/dialog_util.dart';

class AiFacesItemCard extends StatefulWidget {
  final AiFaceItem face;
  final VoidCallback onOpen;
  final AiFacesController controller;
  final double avatarSize;
  const AiFacesItemCard({
    super.key,
    required this.face,
    required this.onOpen,
    required this.controller,
    this.avatarSize = 108,
  });

  @override
  State<AiFacesItemCard> createState() => _AiFacesItemCardState();
}

class _AiFacesItemCardState extends State<AiFacesItemCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatarSize = widget.avatarSize;
    final face = widget.face;
    final ctrl = widget.controller;
    final hasName = (face.name ?? '').trim().isNotEmpty;
    final isAdmin = CurrentUserController.instance.isAdmin;
    return Obx(() {
      final inSelectionMode = ctrl.selectionMode.value;
      final selected = ctrl.selectedFaceIds.contains(face.faceId);
      final enableHover =
          DeviceUtils.isDesktop ||
          (DeviceUtils.isWeb && DeviceUtils.isDesktopLayout(context));
      final showCheckbox =
          !DeviceUtils.isMobile && enableHover && (_hovered || inSelectionMode);
      final showMobileMenu =
          DeviceUtils.isMobile && !inSelectionMode && isAdmin;

      final card = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (inSelectionMode) {
              ctrl.toggleSelected(face.faceId);
            } else {
              widget.onOpen();
            }
          },
          borderRadius: BorderRadius.circular(12),
          onLongPress: () {
            ctrl.toggleSelected(face.faceId);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.08)
                  : Colors.transparent,
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary.withValues(alpha: 0.45)
                    : Colors.transparent,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: avatarSize,
                  height: avatarSize,
                  child: Stack(
                    children: [
                      Container(
                        width: avatarSize,
                        height: avatarSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface.withValues(
                                    alpha: 0.08,
                                  ),
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: ClipOval(
                          child: CustomExtendedImage(
                            cache: false,
                            imageUrl: ApiController.instance.getFaceImageUrl(
                              faceId: face.faceId,
                              size: 240,
                              quality: 85,
                            ),
                            width: avatarSize,
                            height: avatarSize,
                            fit: BoxFit.cover,
                            borderRadius: avatarSize / 2,
                            showLoading: false,
                          ),
                        ),
                      ),
                      if (selected)
                        Container(
                          width: avatarSize,
                          height: avatarSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.14,
                            ),
                          ),
                        ),
                      if (showCheckbox)
                        Positioned(
                          left: 0,
                          top: 0,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => ctrl.toggleSelected(face.faceId),
                            child: Container(
                              width: 34,
                              height: 34,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.35),
                                shape: BoxShape.circle,
                              ),
                              child: CustomCheckbox(
                                value: selected,
                                onChanged: (_) =>
                                    ctrl.toggleSelected(face.faceId),
                                isCircle: true,
                                side: const BorderSide(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                        ),
                      if (showMobileMenu)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: PopupMenuButton<String>(
                            tooltip: 'more'.tr,
                            onSelected: (value) async {
                              if (value == 'download') {
                                await ctrl.downloadFaces([face.faceId]);
                                return;
                              }
                              if (value == 'rename') {
                                final name = await DialogUtil.showInputDialog(
                                  title: 'face_name_dialog_title'.tr,
                                  content: 'face_name_dialog_hint'.tr,
                                  initialValue: (face.name ?? '').trim(),
                                  confirmText: 'ok'.tr,
                                  cancelText: 'cancel'.tr,
                                  validator: (v) {
                                    final t = (v ?? '').trim();
                                    if (t.isEmpty) {
                                      return 'name_cannot_be_empty'.tr;
                                    }
                                    if (t.length > 30) {
                                      return 'face_name_too_long'.tr;
                                    }
                                    return null;
                                  },
                                );
                                if (name == null || name.trim().isEmpty) return;
                                await ctrl.renameFace(face, name.trim());
                                return;
                              }
                              if (value == 'toggle_hide') {
                                await ctrl.setFaceHidden(face, !face.isHide);
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'download',
                                child: Text('download'.tr),
                              ),
                              PopupMenuItem(
                                value: 'rename',
                                child: Text('rename'.tr),
                              ),
                              PopupMenuItem(
                                value: 'toggle_hide',
                                child: Text(
                                  (face.isHide
                                          ? 'face_action_show'
                                          : 'face_action_hide')
                                      .tr,
                                ),
                              ),
                            ],
                            icon: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.3),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.more_vert,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                if (hasName)
                  Text(
                    face.name!.trim(),
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                else if (isAdmin)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () async {
                      final name = await DialogUtil.showInputDialog(
                        title: 'face_name_dialog_title'.tr,
                        content: 'face_name_dialog_hint'.tr,
                        confirmText: 'ok'.tr,
                        cancelText: 'cancel'.tr,
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return 'name_cannot_be_empty'.tr;
                          if (t.length > 30) return 'face_name_too_long'.tr;
                          return null;
                        },
                      );
                      if (name == null || name.trim().isEmpty) return;
                      await ctrl.renameFace(face, name.trim());
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        'face_add_name'.tr,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                else
                  Text(
                    'face_unnamed'.tr,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (isAdmin) const SizedBox(height: 2),
                if (isAdmin)
                  Text(
                    'total_count'.trParams({
                      'count': face.faceCount.toString(),
                    }),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 10,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ),
      );

      final withHover = enableHover
          ? MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: card,
            )
          : card;

      if (!enableHover) return withHover;
      if (inSelectionMode) return withHover;

      final entries = <ContextMenuEntry>[
        CustomContextMenuItem.create(
          label: Text('download'.tr),
          icon: const Icon(Icons.download, size: 18),
          value: 'download',
          onSelected: (_) => ctrl.downloadFaces([face.faceId]),
        ),
        if (isAdmin) ...[
          const MenuDivider(),
          CustomContextMenuItem.create(
            label: Text('rename'.tr),
            icon: const Icon(Icons.edit_outlined, size: 18),
            value: 'rename',
            onSelected: (_) async {
              final name = await DialogUtil.showInputDialog(
                title: 'face_name_dialog_title'.tr,
                content: 'face_name_dialog_hint'.tr,
                initialValue: (face.name ?? '').trim(),
                confirmText: 'ok'.tr,
                cancelText: 'cancel'.tr,
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'name_cannot_be_empty'.tr;
                  if (t.length > 30) return 'face_name_too_long'.tr;
                  return null;
                },
              );
              if (name == null || name.trim().isEmpty) return;
              await ctrl.renameFace(face, name.trim());
            },
          ),
          if (face.isHide)
            CustomContextMenuItem.create(
              label: Text('face_action_show'.tr),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              value: 'show',
              onSelected: (_) => ctrl.setFaceHidden(face, false),
            )
          else
            CustomContextMenuItem.create(
              label: Text('face_action_hide'.tr),
              icon: const Icon(Icons.visibility_off_outlined, size: 18),
              value: 'hide',
              onSelected: (_) => ctrl.setFaceHidden(face, true),
            ),
        ],
      ];

      return ContextMenuUtil.region(child: withHover, entries: entries);
    });
  }
}
