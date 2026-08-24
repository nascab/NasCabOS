import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/api/api_controller.dart';
import '../../../../modules/base/components/custom_extended_image.dart';
import '../../../../modules/base/components/custom_no_data.dart';
import '../../../../modules/base/components/custom_glass_card.dart';
import '../../../../modules/base/components/custom_bordered_icon_button.dart';
import '../../../../utils/device_utils.dart';
import '../../../../utils/local_web_asset_server.dart';
import '../controller/ai_gps_add_controller.dart';
import '../models/ai_gps_add_models.dart';

class AiGpsAddView extends StatelessWidget {
  const AiGpsAddView({super.key});

  @override
  Widget build(BuildContext context) {
    const tag = 'photo_ai_gps_add';
    final customColors = Theme.of(context).extension<CustomColors>();
    return GetBuilder<AiGpsAddController>(
      init: AiGpsAddController(),
      tag: tag,
      dispose: (_) => Get.delete<AiGpsAddController>(tag: tag),
      builder: (controller) {
        return Container(
          color: customColors?.mainContentBgColor,
          child: Obx(() {
            final batch = controller.currentBatch.value;
            return LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxWidth < 900 || DeviceUtils.isMobile;
                final hPad = compact ? 12.0 : 20.0;
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(controller: controller),
                        const SizedBox(height: 8),
                        if (controller.running.value) const _RunningBanner(),
                        if (controller.errorText.value != null &&
                            controller.errorText.value!.isNotEmpty)
                          _ErrorBanner(text: controller.errorText.value!),
                        if (controller.loading.value && batch == null)
                          const Padding(
                            padding: EdgeInsets.only(top: 80),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (batch == null)
                          _EmptyState(
                            running: controller.running.value,
                            completed: controller.allCompleted.value,
                          )
                        else
                          _BatchPanel(controller: controller, compact: compact),
                      ],
                    ),
                  ),
                );
              },
            );
          }),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final AiGpsAddController controller;

  @override
  Widget build(BuildContext context) {
    return CustomGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'photo_menu_ai_gps_supplement'.tr,
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'photo_ai_gps_add_notice'.tr,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.64),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              CustomBorderedIconButton(
                icon: Icons.search,
                tooltip: 'photo_ai_gps_add_start_scan'.tr,
                onTap: controller.submitting.value
                    ? null
                    : controller.startScan,
              ),
              CustomBorderedIconButton(
                icon: Icons.clear_all,
                tooltip: 'photo_ai_gps_add_reset'.tr,
                onTap: controller.submitting.value
                    ? null
                    : controller.resetAndRescan,
              ),
              CustomBorderedIconButton(
                icon: Icons.refresh,
                tooltip: 'refresh'.tr,
                onTap: controller.refreshStatus,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RunningBanner extends StatelessWidget {
  const _RunningBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'photo_ai_gps_add_scanning'.tr,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.running, required this.completed});

  final bool running;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    return CustomGlassCard(
      child: SizedBox(
        height: 420,
        child: Center(
          child: CustomNoData(
            text: running
                ? 'photo_ai_gps_add_scanning'.tr
                : completed
                ? 'photo_ai_gps_add_completed'.tr
                : 'photo_ai_gps_add_empty'.tr,
          ),
        ),
      ),
    );
  }
}

class _BatchPanel extends StatelessWidget {
  const _BatchPanel({required this.controller, required this.compact});

  final AiGpsAddController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final batch = controller.currentBatch.value!;
    final selectedReference = controller.selectedReferencePhoto;
    final referencePhotos = controller.visibleReferencePhotos;
    final photoStripHeight = compact ? 172.0 : 188.0;
    final photoItemWidth = compact ? 118.0 : 138.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: 'photo_ai_gps_add_pending_title'.tr,
          subtitle: 'photo_ai_gps_add_pending_open_tip'.tr,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'photo_ai_gps_add_selected_count'.trParams({
                'count': '${controller.selectedPendingCount}',
              }),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontSize: 12),
            ),
          ),
          child: _PendingPhotoStrip(
            photos: batch.pendingPhotos,
            height: photoStripHeight,
            itemWidth: photoItemWidth,
            selectedIds: controller.selectedPendingIds,
            onToggleSelected: controller.togglePendingSelection,
            onTapPhoto: (photo) =>
                controller.openPhotoPreview(photo, batch.pendingPhotos),
          ),
        ),
        const SizedBox(height: 6),
        _SectionCard(
          title: 'photo_ai_gps_add_reference_title'.tr,
          subtitle: 'photo_ai_gps_add_reference_switch_tip'.tr,
          child: referencePhotos.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: Text('photo_ai_gps_add_reference_empty'.tr),
                  ),
                )
              : SizedBox(
                  height: photoStripHeight,
                  child: _HorizontalPhotoStrip(
                    itemWidth: photoItemWidth,
                    children: referencePhotos
                        .map(
                          (photo) => _ReferencePhotoCard(
                            photo: photo,
                            selected: controller.isReferenceSelected(photo),
                            width: photoItemWidth,
                            onTap: () => controller.selectReferencePhoto(photo),
                            onPreviewTap: () => controller.openPhotoPreview(
                              photo,
                              referencePhotos,
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
        ),
        const SizedBox(height: 6),
        _SectionCard(
          padding: EdgeInsets.zero,
          title: 'photo_ai_gps_add_map_title'.tr,
          subtitle: 'photo_ai_gps_add_map_hint'.tr,
          trailing: selectedReference == null
              ? null
              : Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'photo_ai_gps_add_selected_reference'.trParams({
                      'name': selectedReference.filename,
                    }),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
          child: _MapPanel(
            controller: controller,
            compact: compact,
            referencePhotos: referencePhotos,
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return CustomGlassCard(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: padding == EdgeInsets.zero
                ? const EdgeInsets.fromLTRB(16, 10, 16, 0)
                : EdgeInsets.zero,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 10,
              spacing: 10,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.64),
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          SizedBox(height: padding == EdgeInsets.zero ? 10 : 6),
          child,
        ],
      ),
    );
  }
}

class _ReferencePhotoCard extends StatelessWidget {
  const _ReferencePhotoCard({
    required this.photo,
    required this.selected,
    required this.width,
    required this.onTap,
    required this.onPreviewTap,
  });

  final AiGpsAddPhotoItem photo;
  final bool selected;
  final double width;
  final VoidCallback onTap;
  final VoidCallback onPreviewTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl = ApiController.instance.getTinyUrl(photo.fullpath);
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.dividerColor.withValues(alpha: 0.12),
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SizedBox.expand(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: theme.dividerColor),
                        child: IgnorePointer(
                          child: imageUrl.isEmpty
                              ? const Icon(Icons.image_not_supported_outlined)
                              : SizedBox.expand(
                                  child: CustomExtendedImage(
                                    imageUrl: imageUrl,
                                    fit: BoxFit.cover,
                                    cache: true,
                                    showLoading: false,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  photo.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontSize: 12),
                ),
                const SizedBox(height: 3),
                Text(
                  _formatOriginalTime(photo.originalTime),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            top: 18,
            right: 18,
            child: Material(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onPreviewTap,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.open_in_full,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingPhotoStrip extends StatelessWidget {
  const _PendingPhotoStrip({
    required this.photos,
    required this.height,
    required this.itemWidth,
    required this.selectedIds,
    required this.onToggleSelected,
    required this.onTapPhoto,
  });

  final List<AiGpsAddPhotoItem> photos;
  final double height;
  final double itemWidth;
  final Set<int> selectedIds;
  final ValueChanged<AiGpsAddPhotoItem> onToggleSelected;
  final ValueChanged<AiGpsAddPhotoItem> onTapPhoto;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(child: Text('photo_ai_gps_add_pending_empty'.tr)),
      );
    }

    return SizedBox(
      height: height,
      child: _HorizontalPhotoStrip(
        itemWidth: itemWidth,
        children: photos
            .map(
              (photo) => _PendingPhotoCard(
                photo: photo,
                selected: selectedIds.contains(photo.id),
                onTap: () => onTapPhoto(photo),
                onToggleSelected: () => onToggleSelected(photo),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _PendingPhotoCard extends StatelessWidget {
  const _PendingPhotoCard({
    required this.photo,
    required this.selected,
    required this.onTap,
    required this.onToggleSelected,
  });

  final AiGpsAddPhotoItem photo;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onToggleSelected;

  @override
  Widget build(BuildContext context) {
    final imageUrl = ApiController.instance.getTinyUrl(photo.fullpath);
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected
              ? theme.colorScheme.primary
              : theme.dividerColor.withValues(alpha: 0.12),
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: theme.dividerColor),
                      child: IgnorePointer(
                        child: imageUrl.isEmpty
                            ? const Icon(Icons.image_not_supported_outlined)
                            : SizedBox.expand(
                                child: CustomExtendedImage(
                                  imageUrl: imageUrl,
                                  fit: BoxFit.cover,
                                  cache: true,
                                  showLoading: false,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(40, 0, 0, 0),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onTap,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: onToggleSelected,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            photo.filename,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(fontSize: 12),
          ),
          const SizedBox(height: 3),
          Text(
            _formatOriginalTime(photo.originalTime),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 10,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
            ),
          ),
        ],
      ),
    );
  }
}

class _HorizontalPhotoStrip extends StatefulWidget {
  const _HorizontalPhotoStrip({
    required this.children,
    required this.itemWidth,
  });

  final List<Widget> children;
  final double itemWidth;

  @override
  State<_HorizontalPhotoStrip> createState() => _HorizontalPhotoStripState();
}

class _HorizontalPhotoStripState extends State<_HorizontalPhotoStrip> {
  final ScrollController _scrollController = ScrollController();
  bool _canLeft = false;
  bool _canRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateButtons);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateButtons());
  }

  @override
  void didUpdateWidget(covariant _HorizontalPhotoStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateButtons());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateButtons);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateButtons() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final canLeft = position.pixels > 4;
    final canRight = position.pixels < position.maxScrollExtent - 4;
    if (canLeft != _canLeft || canRight != _canRight) {
      setState(() {
        _canLeft = canLeft;
        _canRight = canRight;
      });
    }
  }

  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) return;
    final target = (_scrollController.offset + delta).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final showDesktopButtons =
        !DeviceUtils.isMobile && widget.children.length > 1;
    return Stack(
      children: [
        ListView.separated(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          itemCount: widget.children.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, index) =>
              SizedBox(width: widget.itemWidth, child: widget.children[index]),
        ),
        if (showDesktopButtons && _canLeft)
          Positioned(
            left: 4,
            top: 0,
            bottom: 0,
            child: _ScrollOverlayButton(
              icon: Icons.chevron_left,
              onTap: () => _scrollBy(-(widget.itemWidth + 12) * 2),
            ),
          ),
        if (showDesktopButtons && _canRight)
          Positioned(
            right: 4,
            top: 0,
            bottom: 0,
            child: _ScrollOverlayButton(
              icon: Icons.chevron_right,
              onTap: () => _scrollBy((widget.itemWidth + 12) * 2),
            ),
          ),
      ],
    );
  }
}

class _ScrollOverlayButton extends StatelessWidget {
  const _ScrollOverlayButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.black.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 72,
            child: Icon(icon, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}

class _MapPanel extends StatelessWidget {
  const _MapPanel({
    required this.controller,
    required this.compact,
    required this.referencePhotos,
  });

  final AiGpsAddController controller;
  final bool compact;
  final List<AiGpsAddPhotoItem> referencePhotos;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Stack(
        children: [
          SizedBox(
            height: compact ? 252 : 364,
            child: _EditableGpsMap(
              point: controller.selectedPoint.value,
              referencePhotos: referencePhotos,
              selectedReferenceId: controller.selectedReferenceId.value,
              onChanged: controller.updateSelectedPoint,
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  'photo_ai_gps_add_selected_point'.trParams({
                    'lat': controller.selectedPoint.value.latitude
                        .toStringAsFixed(6),
                    'lng': controller.selectedPoint.value.longitude
                        .toStringAsFixed(6),
                  }),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: compact
                ? Row(
                    children: [
                      Expanded(
                        child: _GpsActionButton(
                          filled: false,
                          icon: Icons.skip_next_outlined,
                          label: 'photo_ai_gps_add_skip'.tr,
                          onTap: controller.submitting.value
                              ? null
                              : controller.skipBatch,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _GpsActionButton(
                          filled: true,
                          icon: Icons.gps_fixed,
                          label: 'photo_ai_gps_add_apply'.tr,
                          onTap: controller.submitting.value
                              ? null
                              : controller.applyGps,
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      SizedBox(
                        width: 220,
                        child: _GpsActionButton(
                          filled: false,
                          icon: Icons.skip_next_outlined,
                          label: 'photo_ai_gps_add_skip'.tr,
                          onTap: controller.submitting.value
                              ? null
                              : controller.skipBatch,
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: _GpsActionButton(
                          filled: true,
                          icon: Icons.gps_fixed,
                          label: 'photo_ai_gps_add_apply'.tr,
                          onTap: controller.submitting.value
                              ? null
                              : controller.applyGps,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _GpsActionButton extends StatelessWidget {
  const _GpsActionButton({
    required this.filled,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool filled;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label, style: TextStyle(color: filled ? Colors.white : null)),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: filled
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: filled
            ? Colors.white
            : Theme.of(context).colorScheme.onSurface,
        elevation: 0,
      ),
    );
  }
}

class _EditableGpsMap extends StatefulWidget {
  const _EditableGpsMap({
    required this.point,
    required this.referencePhotos,
    required this.selectedReferenceId,
    required this.onChanged,
  });

  final LatLng point;
  final List<AiGpsAddPhotoItem> referencePhotos;
  final int selectedReferenceId;
  final ValueChanged<LatLng> onChanged;

  @override
  State<_EditableGpsMap> createState() => _EditableGpsMapState();
}

class _EditableGpsMapState extends State<_EditableGpsMap> {
  final MapController _mapController = MapController();
  Uri? _localProxyBase;
  bool _localProxyAcquired = false;
  bool _mapReady = false;

  @override
  void didUpdateWidget(covariant _EditableGpsMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.point.latitude != widget.point.latitude ||
        oldWidget.point.longitude != widget.point.longitude) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_mapReady) return;
        _mapController.move(widget.point, _mapController.camera.zoom);
      });
    }
  }

  @override
  void dispose() {
    if (_localProxyAcquired) {
      LocalWebAssetServer.instance.release();
      _localProxyAcquired = false;
    }
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final token = ApiController.instance.accessToken ?? '';
    final baseUrl = ApiController.instance.baseUrl;
    final isP2p = ApiController.instance.isP2pMode;

    if (isP2p && !DeviceUtils.isWeb && _localProxyBase == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _localProxyBase != null) return;
        final base = await LocalWebAssetServer.instance.acquire();
        if (!mounted) return;
        setState(() {
          _localProxyBase = base;
          _localProxyAcquired = true;
        });
      });
    }

    final tileBase = isP2p
        ? (DeviceUtils.isWeb ? '/__p2p__' : (_localProxyBase?.toString() ?? ''))
        : baseUrl;
    final urlTemplate = tileBase.isEmpty
        ? ''
        : (token.isNotEmpty
              ? '$tileBase/api/mapApi/tile?zoom={z}&x={x}&y={y}&accessToken=${Uri.encodeComponent(token)}'
              : '$tileBase/api/mapApi/tile?zoom={z}&x={x}&y={y}');

    final markers = <Marker>[
      ...widget.referencePhotos
          .where((e) => e.hasGps)
          .map(
            (photo) => Marker(
              point: LatLng(photo.latitude, photo.longitude),
              width: 34,
              height: 34,
              child: IgnorePointer(
                child: Icon(
                  Icons.place,
                  color: widget.selectedReferenceId == photo.id
                      ? Colors.orangeAccent
                      : Colors.white,
                  size: widget.selectedReferenceId == photo.id ? 28 : 22,
                ),
              ),
            ),
          ),
      Marker(
        point: widget.point,
        width: 46,
        height: 46,
        child: const IgnorePointer(
          child: Icon(Icons.location_on, color: Colors.red, size: 40),
        ),
      ),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.point,
              initialZoom: 12,
              minZoom: 3,
              maxZoom: 18,
              onMapReady: () {
                _mapReady = true;
              },
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
              onTap: (_, point) => widget.onChanged(point),
            ),
            children: [
              if (urlTemplate.isNotEmpty)
                TileLayer(
                  urlTemplate: urlTemplate,
                  userAgentPackageName: 'NasCabOS',
                ),
              MarkerLayer(markers: markers),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatOriginalTime(String value) {
  final ms = int.tryParse(value) ?? 0;
  if (ms <= 0) return '-';
  final date = DateTime.fromMillisecondsSinceEpoch(ms);
  String pad(int v) => v < 10 ? '0$v' : '$v';
  return '${date.year}-${pad(date.month)}-${pad(date.day)} ${pad(date.hour)}:${pad(date.minute)}';
}
