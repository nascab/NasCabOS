import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/api/api_controller.dart';
import '../app_home_controller.dart';

class AppAppsGrid extends StatelessWidget {
  final AppHomeController controller;

  const AppAppsGrid({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: GetBuilder<ApiController>(
        builder: (_) {
          return Obx(() {
            final apps = controller.filteredApps();
            return LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                const minItemWidth = 75.0;
                const spacing = 10.0;

                final count = (width + spacing) ~/ (minItemWidth + spacing);
                final crossAxisCount = count > 0 ? count : 1;

                return GridView.builder(
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: spacing,
                    mainAxisSpacing: spacing,
                    childAspectRatio: 0.86,
                  ),
                  itemCount: apps.length,
                  itemBuilder: (context, index) {
                    final app = apps[index];
                    return _buildAppIcon(context, controller, app, index);
                  },
                );
              },
            );
          });
        },
      ),
    );
  }

  Widget _buildAppIcon(
    BuildContext context,
    AppHomeController controller,
    String app,
    int index,
  ) {
    return LongPressDraggable<int>(
      data: index,
      feedback: Material(
        color: Colors.transparent,
        child: _appIconContent(context, app, scale: 1.1),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _appIconContent(context, app),
      ),
      onDragEnd: (details) {},
      child: DragTarget<int>(
        onWillAcceptWithDetails: (data) => data.data != index,
        onAcceptWithDetails: (data) {
          controller.reorderApp(data.data, index);
        },
        builder: (context, candidate, rejected) {
          return InkWell(
            onTap: () => controller.openApp(app),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                color: candidate.isNotEmpty
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.1)
                    : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _appIconContent(context, app),
            ),
          );
        },
      ),
    );
  }

  Widget _appIconContent(
    BuildContext context,
    String app, {
    double scale = 1.0,
  }) {
    final theme = Theme.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheSide =
        (60.0 * scale * dpr).round().clamp(1, 4096);

    return Transform.scale(
      scale: scale,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/app_icons/$app.webp',
            width: 60,
            height: 60,
            filterQuality: FilterQuality.high,
            isAntiAlias: true,
            cacheWidth: cacheSide,
            cacheHeight: cacheSide,
            errorBuilder: (context, error, stackTrace) =>
                Icon(Icons.apps, size: 38, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 6),
          Text(
            'app_$app'.tr,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: Colors.white,
              shadows: const [
                Shadow(
                  color: Color(0xB3000000),
                  offset: Offset(0, 1),
                  blurRadius: 4,
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
