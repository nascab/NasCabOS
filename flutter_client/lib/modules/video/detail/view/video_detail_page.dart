import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../base/components/custom_icon_button.dart';
import '../../base/beans/video_item_bean.dart';
import '../../base/video_utils/video_utils.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/device_utils.dart';
import '../controller/video_detail_controller.dart';
import 'parts/app_video_detail_body.dart';
import 'parts/video_detail_body.dart';

class VideoDetailPage extends StatefulWidget {
  final int? indexId;
  final VoidCallback? onClose;
  final String? controllerTag;

  const VideoDetailPage({
    super.key,
    this.indexId,
    this.onClose,
    this.controllerTag,
  });

  @override
  State<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends State<VideoDetailPage> {
  late final String _controllerTag;
  bool _errorDialogShown = false;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    final argIndexId = (args is Map ? args['index_id'] : null) as num?;
    final id = widget.indexId ?? argIndexId?.toInt() ?? 0;
    _controllerTag =
        widget.controllerTag ??
        'video_detail_${id}_${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<VideoDetailController>(
      init: VideoDetailController(indexId: widget.indexId),
      tag: _controllerTag,
      dispose: (_) {
        Get.delete<VideoDetailController>(tag: _controllerTag);
      },
      builder: (ctrl) {
        final theme = Theme.of(context);
        final isPhone = DeviceUtils.isPhone(context);
        final m = ctrl.item;
        final title = (m?['nfo_name']?.toString().trim().isNotEmpty ?? false)
            ? m!['nfo_name'].toString()
            : (m?['filename']?.toString() ?? '');
        final bgUrl = m == null
            ? ''
            : VideoUtils.getFanartUrl(
                VideoHomeItemBean.fromJson(Map<String, dynamic>.from(m as Map)),
                size: 1000,
              );
        final topInset = MediaQuery.of(context).padding.top;
        final closeTop = topInset + (isPhone ? 12 : 12);
        final closeSide = isPhone ? 12.0 : 30.0;
        final width = (m?['width'] as num?)?.toInt() ?? 0;
        final height = (m?['height'] as num?)?.toInt() ?? 0;
        final itemResLabel = _resolutionLabel(width, height);
        final resLabel = ctrl.mediaType == 'tv'
            ? (ctrl.episodeList.isNotEmpty
                  ? _resolutionLabel(
                      (ctrl.episodeList.first['width'] as num?)?.toInt() ?? 0,
                      (ctrl.episodeList.first['height'] as num?)?.toInt() ?? 0,
                    )
                  : '')
            : itemResLabel;

        return Theme(
          data: ThemeData.dark(), //详情页锁定黑色主题
          child: Scaffold(
            body: AnnotatedRegion<SystemUiOverlayStyle>(
              value: const SystemUiOverlayStyle(
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
              ),
              child: Obx(() {
                final loading = ctrl.loading.value;
                final hasItem = ctrl.item != null;
                if (!loading && !hasItem && !_errorDialogShown) {
                  _errorDialogShown = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    DialogUtil.showInfoDialog(
                      title: 'tip'.tr,
                      content: 'video_detail_load_failed'.tr,
                      onPressed: widget.onClose ?? AppRoutes.back,
                    );
                  });
                }
                return Stack(
                  children: [
                    Positioned.fill(
                      child: isPhone
                          ? AppVideoDetailBody(ctrl: ctrl)
                          : VideoDetailBody(ctrl: ctrl),
                    ),
                    //顶部栏：左侧分辨率标签 + 右侧关闭按钮
                    Positioned(
                      left: closeSide,
                      right: closeSide,
                      top: closeTop,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (isPhone && resLabel.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.22),
                                ),
                              ),
                              child: Text(
                                resLabel,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          const Spacer(),
                          CustomIconButton(
                            icon: Icons.close,
                            onPressed: widget.onClose ?? AppRoutes.back,
                            backgroundColor: Colors.black.withValues(
                              alpha: 0.35,
                            ),
                            iconColor: Colors.white,
                            tooltip: 'close'.tr,
                          ),
                        ],
                      ),
                    ),
                    if (loading && !hasItem)
                      const Positioned.fill(
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (!loading && !hasItem)
                      Positioned.fill(
                        child: Center(
                          child: Text('video_detail_load_failed'.tr),
                        ),
                      ),
                    if (bgUrl.isEmpty) const SizedBox.shrink(),
                    Positioned(
                      right: 12,
                      top: MediaQuery.of(context).padding.top + 10,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.0),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        );
      },
    );
  }
}

String _resolutionLabel(int width, int height) {
  final w = width < 0 ? 0 : width;
  final h = height < 0 ? 0 : height;
  if (w >= 3840 || h >= 2160) return '4K';
  if (w >= 1920 || h >= 1080) return '1080P';
  if (w >= 1280 || h >= 720) return '720P';
  return '';
}
