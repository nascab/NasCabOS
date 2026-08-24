import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../../core/api/api_controller.dart';
import '../../../../../modules/base/components/custom_extended_image.dart';
import '../../../timeline/models/photo_timeline_model.dart';
import '../../controller/photo_trash_controller.dart';
import '../../../../../modules/base/components/custom_checkbox.dart';

/// 回收站照片项组件
class PhotoTrashItem extends StatefulWidget {
  final PhotoTrashController controller;
  final TimelinePhotoItem photo;

  const PhotoTrashItem({
    super.key,
    required this.controller,
    required this.photo,
  });

  @override
  State<PhotoTrashItem> createState() => _PhotoTrashItemState();
}

class _PhotoTrashItemState extends State<PhotoTrashItem> {
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
    final imageUrl = ApiController.instance.getTinyUrl(widget.photo.fullpath);
    return Obx(() {
      final isSelected = widget.controller.selectedItems.contains(
        widget.photo.id,
      );
      final isMultiSelectMode = widget.controller.isMultiSelectMode.value;
      final showCheck = _hover || isMultiSelectMode || isSelected;

      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: () {
            if (isMultiSelectMode) {
              widget.controller.toggleSelection(widget.photo.id);
            } else {
              // 进入多选模式并选中当前项
              widget.controller.isMultiSelectMode.value = true;
              widget.controller.selectedItems.add(widget.photo.id);
            }
          },
          onLongPress: () {
            // 长按进入多选模式并选中当前项
            widget.controller.isMultiSelectMode.value = true;
            widget.controller.selectedItems.add(widget.photo.id);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 图片容器
              CustomExtendedImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                borderRadius: 4,
              ),

              // 悬停效果
              if (_hover)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),

              // 选中状态覆盖层
              if (isSelected)
                Container(
                  decoration: BoxDecoration(
                    color: Get.theme.primaryColor.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Get.theme.primaryColor, width: 2),
                  ),
                ),

              // 顶部信息栏：文件名 + 类型标识
              Positioned(
                top: 6,
                left: 6,
                right: 6,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 文件名
                    Expanded(
                      child: _hover
                          ? Text(
                              widget.photo.filename,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            )
                          : const SizedBox(),
                    ),
                    // 视频时长
                    if (widget.photo.type == 2) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      // 视频时长
                      Text(
                        _formatDuration(widget.photo.duration),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ] else if (widget.photo.isLvp == 1) ...[
                      // livephoto 标识
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
                  ],
                ),
              ),

              // 选择框
              if (showCheck)
                Positioned(
                  bottom: 0,
                  right: 0,
                  // 选中框
                  child: CustomCheckbox(
                    value: isSelected,
                    onChanged: (_) =>
                        widget.controller.toggleSelection(widget.photo.id),
                    isCircle: true,
                    side: BorderSide(
                      color: Colors.white, // 未选中/禁用圆环色
                      width: 2.0, // 圆环宽度
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}
