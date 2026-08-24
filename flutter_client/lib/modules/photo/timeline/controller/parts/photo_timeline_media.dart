part of '../photo_timeline_controller.dart';

/// 打开图片/视频预览相关逻辑。
extension PhotoTimelineControllerMedia on PhotoTimelineController {
  /// 打开媒体预览。
  ///
  /// - 视频（`type == 2`）：进入视频播放器页面，并构造 playlist
  /// - 图片：进入图片浏览器（桌面端优先走 `PcHomeController.openImageViewer`）
  Future<void> openMedia(
    TimelinePhotoItem item, {
    String? controllerTag,
  }) async {
    // 从 photoItems 提取所有照片
    final allPhotos = photoItems
        .whereType<TimelineListPhoto>()
        .map((e) => e.photo)
        .toList(growable: false);

    if (item.type == 2) {
      final videos = allPhotos
          .where((e) => e.type == 2)
          .map(
            (e) => <String, dynamic>{
              'type': 'video',
              'path': e.fullpath,
              'name': e.filename,
            },
          )
          .toList();

      final index = videos.indexWhere((e) => e['path'] == item.fullpath);
      if (index < 0) return;

      final routeArgs = <String, dynamic>{
        'playlist': videos,
        'initialIndex': index,
      };
      if (DeviceUtils.isDesktop) {
        Get.to(
          () => PcVideoPlayerView(playlist: videos, initialIndex: index),
          transition: Transition.fadeIn,
          arguments: routeArgs,
        );
        return;
      }

      Get.to(
        () => AppVideoPlayerPage(playlist: videos, initialIndex: index),
        arguments: routeArgs,
      );
      return;
    }

    final images = allPhotos
        .where((e) => e.type != 2)
        .map(
          (e) => <String, dynamic>{
            'type': 'image',
            'path': e.fullpath,
            'name': e.filename,
            'photoId': e.id,
            'width': e.width,
            'height': e.height,
            'isLvp': e.isLvp,
            'isMergeLvp': e.isMergeLvp,
            'liveFilename': e.liveFilename,
            'rawFilename': e.rawFilename,
            if (controllerTag != null && controllerTag.trim().isNotEmpty)
              'photoTimelineTag': controllerTag.trim(),
          },
        )
        .toList();

    final index = images.indexWhere((e) => e['path'] == item.fullpath);
    if (index < 0) return;

    if (DeviceUtils.isDesktop && Get.isRegistered<PcHomeController>()) {
      final homeController = Get.find<PcHomeController>();
      homeController.openImageViewer(images, index);
      return;
    }

    if (!Get.isRegistered<CustomGalleryController>()) {
      Get.put(CustomGalleryController());
    }

    final galleryCtrl = CustomGalleryController.instance;
    galleryCtrl.configure();
    galleryCtrl.isControlsVisible.value = true;
    galleryCtrl.galleryItems = images;
    galleryCtrl.galleryInitialIndex.value = index;
    Get.to(() => const CustomGallery());
  }

  /// 切换收藏状态
  Future<void> toggleFavorite(TimelinePhotoItem item) async {
    try {
      // 乐观更新 UI
      final newStatus = !item.isFavorite;
      _updateItemFavoriteStatus(item.id, newStatus);

      final res = await _apiService.toggleFavorite(item.fileHash);
      if (res.success && res.data != null) {
        final isFavorite = res.data!['is_favorite'] as bool;
        // 如果后端返回的状态与乐观更新不一致，则修正
        if (isFavorite != newStatus) {
          _updateItemFavoriteStatus(item.id, isFavorite);
        }
      } else {
        // 失败回滚
        _updateItemFavoriteStatus(item.id, !newStatus);
      }
    } catch (e) {
      print('切换收藏失败: $e');
    }
  }

  void _updateItemFavoriteStatus(int itemId, bool isFavorite) {
    if (listType.value == 'favorite' && !isFavorite) {
      // Remove item
      final index = photoItems.indexWhere(
        (e) => e is TimelineListPhoto && e.photo.id == itemId,
      );
      if (index == -1) return;

      final item = photoItems[index] as TimelineListPhoto;
      final date = item.photo.originalDate;

      photoItems.removeAt(index);

      // Check if any other items exist for this date
      bool hasSiblings = photoItems.any(
        (e) => e is TimelineListPhoto && e.photo.originalDate == date,
      );
      if (!hasSiblings) {
        // Remove header
        photoItems.removeWhere(
          (e) => e is TimelineListDateHeader && e.date == date,
        );
        // Also update dateList
        dateList.removeWhere((e) => e.originalDate == date);
      }
      return;
    }

    final index = photoItems.indexWhere(
      (e) => e is TimelineListPhoto && e.photo.id == itemId,
    );
    if (index != -1) {
      final oldItem = photoItems[index] as TimelineListPhoto;
      photoItems[index] = TimelineListPhoto(
        photo: oldItem.photo.copyWith(isFavorite: isFavorite),
      );
    }
  }
}
