import 'package:NasCabOS/utils/device_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:extended_image/extended_image.dart';
import '../../base/components/custom_extended_image.dart';
import '../../base/components/custom_divider.dart';
import '../../base/components/custom_icon_button.dart';
import '../controllers/custom_gallery_controller.dart';
import 'components/gallery_navigation_arrow.dart';
import 'components/gallery_top_controls.dart';
import 'components/gallery_file_name.dart';
import 'components/gallery_info_panel.dart';
import 'live_photo_inline_player.dart';
import 'panorama_gallery_page.dart';

class CustomGallery extends StatefulWidget {
  const CustomGallery({super.key});

  @override
  State<CustomGallery> createState() => _CustomGalleryState();
}

class _CustomGalleryState extends State<CustomGallery> {
  @override
  void initState() {
    super.initState();
    if (!Get.isRegistered<CustomGalleryController>()) {
      Get.put(CustomGalleryController());
    }
  }

  @override
  void dispose() {
    Future.microtask(() {
      if (Get.isRegistered<CustomGalleryController>()) {
        Get.delete<CustomGalleryController>(force: true);
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<CustomGalleryController>(
      builder: (ctrl) {
        return Obx(() {
          final items = ctrl.galleryItems;
          if (items.isEmpty) {
            return Center(child: Text('gallery_no_images'.tr));
          }

          final currentIndex = ctrl.currentIndex.value;
          final currentItem = items[currentIndex];
          final fileName = currentItem['name'] ?? '';
          final liveVideoUrl = ctrl.getLiveVideoUrlForItem(currentItem);
          final isLivePhoto = liveVideoUrl != null;
          ctrl.ensurePanoramaCandidate(currentIndex);
          final panoramaUrl = ctrl.getPanoramaImageUrlForItem(currentItem);
          final showPanoramaButton =
              panoramaUrl != null && ctrl.isPanoramaCandidate(currentIndex);

          final isMobile = DeviceUtils.isPhone(context);
          final showInfo = ctrl.isInfoPanelVisible.value;
          final showSidePanel = showInfo && !isMobile;

          void openInfoBottomSheet() {
            ctrl.fetchCurrentImageInfo(force: true);
            showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (sheetContext) => DraggableScrollableSheet(
                initialChildSize: 0.6,
                minChildSize: 0.3,
                maxChildSize: 0.95,
                expand: false,
                builder: (_, scrollController) => Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.95),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  child: GalleryInfoPanel(
                    controller: ctrl,
                    onClose: () => Navigator.pop(sheetContext),
                  ),
                ),
              ),
            );
          }

          return Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                width: showSidePanel ? 300 : 0,
                child: showSidePanel
                    ? GalleryInfoPanel(controller: ctrl)
                    : const SizedBox(),
              ),
              if (showSidePanel)
                SizedBox(
                  width: 1,
                  height: double.infinity,
                  child: RotatedBox(
                    quarterTurns: 1,
                    child: CustomDivider(
                      height: 1,
                      thickness: 1,
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Stack(
                      children: [
                        Container(color: Colors.black),
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.deferToChild,
                            onTapUp: (details) {
                              // 触控设备仅保留点击中间区域切换控制栏，左右区域不切换图片（仅滑动切换）
                              if (isMobile) {
                                ctrl.toggleControls();
                                return;
                              }
                              final screenWidth = constraints.maxWidth;
                              final tapX = details.localPosition.dx;

                              if (tapX < screenWidth * 0.3) {
                                ctrl.previousImage();
                              } else if (tapX > screenWidth * 0.7) {
                                ctrl.nextImage();
                              } else {
                                ctrl.toggleControls();
                              }
                            },
                            child: ExtendedImageGesturePageView.builder(
                              controller: ctrl.pageController,
                              itemCount: items.length,
                              itemBuilder: (context, index) {
                                final item = items[index];
                                final itemLiveVideoUrl =
                                    ctrl.getLiveVideoUrlForItem(item);
                                final itemIsLivePhoto =
                                    itemLiveVideoUrl != null;

                                return Obx(() {
                                  final rotation = ctrl.getRotation(index);
                                  Widget imageWidget = RotatedBox(
                                    quarterTurns: rotation,
                                    child: CustomExtendedImage(
                                      imageUrl: item['url'] ?? '',
                                      fit: BoxFit.contain,
                                      mode: ExtendedImageMode.gesture,
                                      initGestureConfigHandler: (state) {
                                        return GestureConfig(
                                          minScale: 0.5,
                                          maxScale: 10.0,
                                          animationMinScale: 0.5,
                                          animationMaxScale: 10,
                                          initialScale: ctrl.getScale(index),
                                          inPageView: true,
                                        );
                                      },
                                      onDoubleTap:
                                          (ExtendedImageGestureState state) {
                                            ctrl.handleDoubleTapScale(
                                              index,
                                              state,
                                            );
                                          },
                                    ),
                                  );

                                  // Live Photo：页内播放（视频覆盖在当前图片上，可继续滑动切换）
                                  if (itemIsLivePhoto &&
                                      ctrl.livePlayingIndex.value == index) {
                                    return Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        imageWidget,
                                        LivePhotoInlinePlayer(
                                          videoUrl: itemLiveVideoUrl,
                                          fallbackVideoUrl: ctrl
                                              .getLiveVideoFallbackUrlForItem(
                                                item,
                                              ),
                                          onClose: ctrl.stopLivePlayback,
                                        ),
                                      ],
                                    );
                                  }

                                  // Live Photo：长按播放（手机端按住播放 / PC 端鼠标按住播放）
                                  if (itemIsLivePhoto) {
                                    return GestureDetector(
                                      onLongPressStart: (_) {
                                        if (ctrl.isLivePhotoPlaying) return;
                                        ctrl.startLivePlayback(index);
                                      },
                                      child: imageWidget,
                                    );
                                  }
                                  return imageWidget;
                                });
                              },
                            ),
                          ),
                        ),
                        Obx(() {
                          if (!ctrl.isControlsVisible.value) {
                            return const SizedBox();
                          }

                          return Stack(
                            children: [
                              GalleryTopControls(
                                onInfoPressed: isMobile
                                    ? openInfoBottomSheet
                                    : null,
                              ),
                              GalleryFileName(
                                fileName: fileName,
                                isLivePhoto: isLivePhoto,
                                showPanoramaButton: showPanoramaButton,
                                onLiveTap: liveVideoUrl != null
                                    ? () =>
                                          ctrl.startLivePlayback(currentIndex)
                                    : null,
                                onPanoramaTap: panoramaUrl != null
                                    ? () => Navigator.of(context).push(
                                        PageRouteBuilder<void>(
                                          pageBuilder:
                                              (
                                                _,
                                                animation,
                                                secondaryAnimation,
                                              ) => PanoramaGalleryPage(
                                                imageUrl: panoramaUrl,
                                              ),
                                          transitionDuration: Duration.zero,
                                          reverseTransitionDuration:
                                              Duration.zero,
                                        ),
                                      )
                                    : null,
                              ),
                              if (!isMobile)
                                const GalleryNavigationArrow(isLeft: true),
                              if (!isMobile)
                                const GalleryNavigationArrow(isLeft: false),
                            ],
                          );
                        }),
                        // 触控设备：左上角常驻关闭按钮（置于最上层确保可点击）
                        if (isMobile)
                          Positioned(
                            left: 0,
                            top: 0,
                            child: SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  top: 24,
                                  left: 12,
                                ),
                                child: CustomIconButton(
                                  icon: Icons.close,
                                  onPressed: () {
                                    if (Navigator.of(context).canPop()) {
                                      Navigator.of(context).pop();
                                    } else {
                                      ctrl.closeGallery();
                                    }
                                  },
                                  iconColor: Colors.white,
                                  iconSize: 24,
                                  buttonSize: 44,
                                  tooltip: 'close'.tr,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        });
      },
    );
  }
}
