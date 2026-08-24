import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controller/photo_timeline_controller.dart';
import '../../models/photo_timeline_model.dart';
import '../../../../base/components/custom_checkbox.dart';
import '../../../../../core/api/api_controller.dart';
import '../../../../base/components/custom_extended_image.dart';
import 'photo_timeline_context_menu.dart';
import '../../../../../utils/device_utils.dart';

class PhotoTimelineItem extends StatefulWidget {
  final TimelinePhotoItem item;
  final String? controllerTag;

  const PhotoTimelineItem({super.key, required this.item, this.controllerTag});

  @override
  State<PhotoTimelineItem> createState() => _PhotoTimelineItemState();
}

class _PhotoTimelineItemState extends State<PhotoTimelineItem> {
  bool _hover = false;

  String _formatDuration(int duration) {
    final Duration d = Duration(seconds: duration);
    final int hours = d.inHours;
    final int minutes = d.inMinutes.remainder(60);
    final int seconds = d.inSeconds.remainder(60);

    final String minStr = minutes.toString().padLeft(2, '0');
    final String secStr = seconds.toString().padLeft(2, '0');

    if (hours > 0) {
      return '$hours:$minStr:$secStr';
    }
    return '$minStr:$secStr';
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<PhotoTimelineController>(
      tag: widget.controllerTag,
    );
    final imageUrl = ApiController.instance.getTinyUrl(widget.item.fullpath);

    return Obx(() {
      final isSelected = controller.selectedItems.contains(widget.item.id);
      final isMulti = controller.isMultiSelectMode.value;
      final showCheck = _hover || isMulti || isSelected;
      final content = GestureDetector(
        onTap: () {
          if (isMulti) {
            controller.toggleSelection(widget.item.id);
            return;
          }
          controller.openMedia(
            widget.item,
            controllerTag: widget.controllerTag,
          );
        },
        onLongPress: () {
          if (!isMulti) {
            controller.toggleSelection(widget.item.id);
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomExtendedImage(
              imageUrl: imageUrl,
              fit: controller.isCoverMode.value ? BoxFit.cover : BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              borderRadius: 4,
            ),
            if (_hover)
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            if (isSelected)
              Container(
                decoration: BoxDecoration(
                  color: Get.theme.primaryColor.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Get.theme.primaryColor, width: 2),
                ),
              ),
            Positioned(
              top: 6,
              left: 6,
              right: 6,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _hover
                        ? Text(
                            widget.item.filename,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          )
                        : const SizedBox(),
                  ),
                  if (widget.item.type == 2) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.play_arrow, color: Colors.white, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      _formatDuration(widget.item.duration),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ] else if (widget.item.isLvp == 1) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.motion_photos_on,
                      color: Colors.white,
                      size: 14,
                      shadows: [
                        Shadow(
                          offset: Offset(0, 1),
                          blurRadius: 3,
                          color: Colors.black,
                        ),
                      ],
                    ),
                  ],
                  if (widget.item.rawShowExt.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.item.rawShowExt,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if ((_hover || widget.item.isFavorite) && !isMulti)
              Positioned(
                bottom: 0,
                left: 0,
                child: GestureDetector(
                  onTap: () => controller.toggleFavorite(widget.item),
                  child: IconButton(
                    icon: Icon(
                      widget.item.isFavorite
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: widget.item.isFavorite ? Colors.red : Colors.white,
                      size: 20,
                    ),
                    onPressed: () => controller.toggleFavorite(widget.item),
                  ),
                ),
              ),
            if (showCheck)
              Positioned(
                bottom: 0,
                right: 0,
                child: CustomCheckbox(
                  value: isSelected,
                  onChanged: (_) => controller.toggleSelection(widget.item.id),
                  isCircle: true,
                  side: BorderSide(color: Colors.white, width: 2.0),
                ),
              ),
          ],
        ),
      );

      final enableHover =
          DeviceUtils.isDesktop ||
          (DeviceUtils.isWeb && DeviceUtils.isDesktopLayout(context));
      final child = enableHover
          ? MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              child: content,
            )
          : content;
      return PhotoTimelineContextMenu(
        item: widget.item,
        controllerTag: widget.controllerTag,
        child: child,
      );
    });
  }
}
