import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:get/get.dart';
import '../../../../../core/api/api_controller.dart';
import '../../../../../core/user/current_user_controller.dart';
import '../../../../../utils/context_menu_util.dart';
import '../../../../../utils/device_utils.dart';
import '../../../../base/components/custom_context_menu_item.dart';
import '../../../../base/components/custom_extended_image.dart';
import '../../controller/ai_scenes_controller.dart';
import '../../models/ai_scenes_models.dart';

class AiSceneItemCard extends StatefulWidget {
  final AiSceneItem scene;
  final AiScenesController controller;
  final double avatarSize;
  final VoidCallback onOpen;
  const AiSceneItemCard({
    super.key,
    required this.scene,
    required this.controller,
    required this.avatarSize,
    required this.onOpen,
  });

  @override
  State<AiSceneItemCard> createState() => _AiSceneItemCardState();
}

class _AiSceneItemCardState extends State<AiSceneItemCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatarSize = widget.avatarSize;
    final borderRadius = BorderRadius.circular(12);
    final scene = widget.scene;
    final ctrl = widget.controller;
    final name = scene.placeName.trim();
    final displayName = name.isNotEmpty ? name : 'scene_unnamed'.tr;
    final coverPath = scene.cover?.fullpath.trim() ?? '';

    final card = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
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
                        borderRadius: borderRadius,
                        border: Border.all(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.08,
                          ),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: borderRadius,
                        child: coverPath.isEmpty
                            ? Container(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.landscape_outlined,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                                  size: 40,
                                ),
                              )
                            : CustomExtendedImage(
                                cache: false,
                                imageUrl: ApiController.instance.getTinyUrl(
                                  coverPath,
                                ),
                                width: avatarSize,
                                height: avatarSize,
                                fit: BoxFit.cover,
                                borderRadius: 12,
                                showLoading: false,
                              ),
                      ),
                    ),
                    if (_hovered)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: borderRadius,
                            color: Colors.black.withValues(alpha: 0.1),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                displayName,
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                'total_count'.trParams({'count': scene.photoCount.toString()}),
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

    final withHover = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: card,
    );

    if (!DeviceUtils.isDesktopOrWeb) return withHover;

    final isAdmin = CurrentUserController.instance.isAdmin;
    if (!isAdmin) return withHover;

    final entries = <ContextMenuEntry>[
      CustomContextMenuItem.create(
        label: Text(
          scene.isHide ? 'face_action_show'.tr : 'face_action_hide'.tr,
        ),
        icon: Icon(
          scene.isHide
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          size: 18,
        ),
        value: 'toggle_hide',
        onSelected: (_) => ctrl.setSceneHidden(scene, !scene.isHide),
      ),
    ];

    return ContextMenuUtil.region(child: withHover, entries: entries);
  }
}
