import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/core/user/current_user_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/api/api_controller.dart';
import '../../../base/components/custom_extended_image.dart';
import '../../../base/components/custom_no_data.dart';
import '../../../base/components/custom_glass_card.dart';
import '../../../base/components/custom_outlined_button.dart';
import '../../ai_faces/models/ai_faces_models.dart';
import '../../ai_faces/view/ai_faces_view.dart';
import '../../ai_scenes/models/ai_scenes_models.dart';
import '../../ai_scenes/view/ai_scenes_view.dart';
import '../../ai_similar/view/ai_similar_view.dart';
import '../../app_setting/view/app_photo_settings_view.dart';
import '../../timeline/view/app_photo_timeline_view.dart';
import '../controller/app_photo_ai_controller.dart';

class AppPhotoAiView extends StatelessWidget {
  const AppPhotoAiView({super.key});

  @override
  Widget build(BuildContext context) {
    const tag = 'photo_app_ai';
    final customColors = Theme.of(context).extension<CustomColors>();
    final isAdmin = CurrentUserController.instance.isAdmin;
    return GetBuilder<AppPhotoAiController>(
      init: AppPhotoAiController(),
      tag: tag,
      dispose: (_) => Get.delete<AppPhotoAiController>(tag: tag),
      builder: (ctrl) {
        return Container(
          color: customColors?.mainContentBgColor,
          child: Obx(() {
            final isLoading = ctrl.isLoading.value;
            final data = ctrl.overview.value;
            if (data == null && isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            return RefreshIndicator(
              onRefresh: () => ctrl.refreshOverview(showToastOnError: true),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                children: [
                  _PreviewSection(
                    title: 'photo_menu_ai_face'.tr,
                    total: data?.faces.total ?? 0,
                    enabled: data?.faces.faceEnable ?? true,
                    hasData:
                        (data?.faces.items ?? const <AiFaceItem>[]).isNotEmpty,
                    disabledText: 'photo_ai_face_disabled'.tr,
                    onOpenAll: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AiFacesView()),
                    ),
                    onEnable: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const AppPhotoSettingsView(initialTabIndex: 2),
                      ),
                    ),
                    child: _FacePreviewRow(
                      items: (data?.faces.items ?? const <AiFaceItem>[])
                          .take(20)
                          .toList(),
                      onOpenAll: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AiFacesView()),
                      ),
                      onOpenItem: (face) {
                        final name = (face.name ?? '').trim();
                        final displayName = name.isNotEmpty
                            ? name
                            : '(${'face_unnamed'.tr})';
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AppPhotoTimelineRoutePage(
                              title: "${"photo_menu_ai_face".tr}-$displayName",
                              listType: 'timeline',
                              faceId: face.faceId,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  _PreviewSection(
                    title: 'photo_menu_ai_scene'.tr,
                    total: data?.scenes.total ?? 0,
                    enabled: data?.scenes.placeEnable ?? true,
                    hasData: (data?.scenes.items ?? const <AiSceneItem>[])
                        .isNotEmpty,
                    disabledText: 'photo_ai_scene_disabled'.tr,
                    onOpenAll: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AiScenesView()),
                    ),
                    onEnable: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const AppPhotoSettingsView(initialTabIndex: 2),
                      ),
                    ),
                    child: _ScenePreviewRow(
                      items: (data?.scenes.items ?? const <AiSceneItem>[])
                          .take(20)
                          .toList(),
                      onOpenAll: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AiScenesView()),
                      ),
                      onOpenItem: (scene) {
                        final name = scene.placeName.trim();
                        final displayName = name.isNotEmpty
                            ? name
                            : 'scene_unnamed'.tr;
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AppPhotoTimelineRoutePage(
                              title: "${"photo_menu_ai_scene".tr}-$displayName",
                              listType: 'timeline',
                              placeName: scene.placeNameRaw,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (isAdmin) const SizedBox(height: 16),
                  if (isAdmin)
                    _DedupCard(
                      enabled: data?.similarEnable ?? true,
                      onOpen: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AiSimilarView(),
                        ),
                      ),
                      onEnable: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const AppPhotoSettingsView(initialTabIndex: 2),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        );
      },
    );
  }
}

class _PreviewSection extends StatelessWidget {
  final String title;
  final int total;
  final bool enabled;
  final bool hasData;
  final String disabledText;
  final VoidCallback onOpenAll;
  final VoidCallback onEnable;
  final Widget child;

  const _PreviewSection({
    required this.title,
    required this.total,
    required this.enabled,
    required this.hasData,
    required this.disabledText,
    required this.onOpenAll,
    required this.onEnable,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalText = 'folder_status_total'.trParams({'total': '$total'});
    final isAdmin = CurrentUserController.instance.isAdmin;
    final header = InkWell(
      onTap: enabled ? onOpenAll : null,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (isAdmin) const SizedBox(width: 10),
            if (isAdmin)
              Expanded(
                child: Text(
                  totalText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ],
        ),
      ),
    );

    if (!enabled) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 8),
          _DisabledPanel(text: disabledText, onEnable: onEnable),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 8),
        hasData
            ? child
            : SizedBox(
                height: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CustomNoData(text: 'no_data'.tr),
                ),
              ),
      ],
    );
  }
}

class _DisabledPanel extends StatelessWidget {
  final String text;
  final VoidCallback onEnable;

  const _DisabledPanel({required this.text, required this.onEnable});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ),
          const SizedBox(width: 12),
          CustomOutlinedButton(
            text: 'photo_ai_enable_now'.tr,
            onPressed: onEnable,
            icon: const Icon(Icons.settings_outlined, size: 18),
          ),
        ],
      ),
    );
  }
}

class _FacePreviewRow extends StatelessWidget {
  final List<AiFaceItem> items;
  final VoidCallback onOpenAll;
  final ValueChanged<AiFaceItem> onOpenItem;

  const _FacePreviewRow({
    required this.items,
    required this.onOpenAll,
    required this.onOpenItem,
  });

  @override
  Widget build(BuildContext context) {
    final list = items.take(20).toList(growable: false);
    final customColors = Theme.of(context).extension<CustomColors>();
    return ClipRect(
      child: Container(
        height: 144,
        color:
            customColors?.mainContentBgColor ??
            Theme.of(context).colorScheme.surface,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: list.length,
          separatorBuilder: (context, index) => const SizedBox(width: 10),
          itemBuilder: (ctx, i) {
            final face = list[i];
            return _FacePreviewCard(face: face, onTap: () => onOpenItem(face));
          },
        ),
      ),
    );
  }
}

class _ScenePreviewRow extends StatelessWidget {
  final List<AiSceneItem> items;
  final VoidCallback onOpenAll;
  final ValueChanged<AiSceneItem> onOpenItem;

  const _ScenePreviewRow({
    required this.items,
    required this.onOpenAll,
    required this.onOpenItem,
  });

  @override
  Widget build(BuildContext context) {
    final list = items.take(20).toList(growable: false);
    final customColors = Theme.of(context).extension<CustomColors>();
    return ClipRect(
      child: Container(
        height: 172,
        color:
            customColors?.mainContentBgColor ??
            Theme.of(context).colorScheme.surface,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: list.length,
          separatorBuilder: (context, index) => const SizedBox(width: 12),
          itemBuilder: (ctx, i) {
            final scene = list[i];
            return _ScenePreviewCard(
              scene: scene,
              onTap: () => onOpenItem(scene),
            );
          },
        ),
      ),
    );
  }
}

class _FacePreviewCard extends StatelessWidget {
  final AiFaceItem face;
  final VoidCallback onTap;

  const _FacePreviewCard({required this.face, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final faceId = face.faceId;
    final faceCount = face.faceCount;
    final name = (face.name ?? '').trim();
    final isAdmin = CurrentUserController.instance.isAdmin;
    final shownName = name.isEmpty ? 'face_unnamed'.tr : name;
    return SizedBox(
      width: 108,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CustomGlassCard(
          borderRadius: 12,
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          onTap: onTap,
          child: Column(
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                  ),
                ),
                child: ClipOval(
                  child: CustomExtendedImage(
                    cache: false,
                    imageUrl: ApiController.instance.getFaceImageUrl(
                      faceId: faceId,
                      size: 240,
                      quality: 85,
                    ),
                    width: 78,
                    height: 78,
                    fit: BoxFit.cover,
                    borderRadius: 39,
                    showLoading: false,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                shownName,
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (isAdmin) const SizedBox(height: 2),
              if (isAdmin)
                Text(
                  'total_count'.trParams({'count': '$faceCount'}),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScenePreviewCard extends StatelessWidget {
  final AiSceneItem scene;
  final VoidCallback onTap;

  const _ScenePreviewCard({required this.scene, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = scene.placeName.trim();
    final shownName = name.isEmpty ? 'scene_unnamed'.tr : name;
    final photoCount = scene.photoCount;
    final coverPath = scene.cover?.fullpath.trim() ?? '';
    final isAdmin = CurrentUserController.instance.isAdmin;
    return SizedBox(
      width: 172,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CustomGlassCard(
          borderRadius: 12,
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 152,
                  height: 104,
                  child: coverPath.isEmpty
                      ? Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.landscape_outlined,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.55,
                            ),
                            size: 40,
                          ),
                        )
                      : CustomExtendedImage(
                          cache: false,
                          imageUrl: ApiController.instance.getTinyUrl(
                            coverPath,
                          ),
                          width: 152,
                          height: 104,
                          fit: BoxFit.cover,
                          borderRadius: 12,
                          showLoading: false,
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                shownName,
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (isAdmin) const SizedBox(height: 2),
              if (isAdmin)
                Text(
                  'total_count'.trParams({'count': '$photoCount'}),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DedupCard extends StatelessWidget {
  final bool enabled;
  final VoidCallback onOpen;
  final VoidCallback onEnable;

  const _DedupCard({
    required this.enabled,
    required this.onOpen,
    required this.onEnable,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = enabled
        ? 'photo_ai_enable_similar_subtitle'.tr
        : 'photo_dedup_disabled'.tr;
    return CustomGlassCard(
      borderRadius: 14,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      onTap: onOpen,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.auto_fix_high_outlined,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'photo_menu_ai_similar'.tr,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (!enabled)
            CustomOutlinedButton(
              text: 'photo_ai_enable_now'.tr,
              onPressed: onEnable,
              compact: true,
            )
          else
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
        ],
      ),
    );
  }
}
