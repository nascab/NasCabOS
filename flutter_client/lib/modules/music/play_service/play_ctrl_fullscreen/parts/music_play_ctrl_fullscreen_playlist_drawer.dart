import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../base/components/custom_extended_image.dart';
import '../../../list/models/music_list_models.dart';
import '../../controller/music_play_service_controller.dart';

typedef MusicCoverUrlResolver = String Function(MusicListItem item, {int size});

class MusicPlayCtrlFullScreenPlaylistDrawer {
  static Future<void> showBottomSheet({
    required BuildContext context,
    required MusicPlayServiceController controller,
    required MusicCoverUrlResolver coverUrlResolver,
  }) async {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final height = (media.size.height * 0.86).clamp(380.0, media.size.height);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SizedBox(
          height: height,
          child: Column(
            children: [
              SizedBox(
                height: 56,
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'player_playlist'.tr,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
              Expanded(
                child: Obx(() {
                  final list = controller.playlist;
                  final current = controller.currentIndex.value;
                  return ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (c, i) {
                      final it = list[i];
                      final selected = i == current;
                      final coverUrl = coverUrlResolver(it, size: 120);
                      return ListTile(
                        selected: selected,
                        leading: SizedBox(
                          width: 42,
                          height: 42,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: coverUrl.trim().isEmpty
                                    ? Image.asset(
                                        'assets/music/icons/default_cover.jpg',
                                        fit: BoxFit.cover,
                                      )
                                    : CustomExtendedImage(
                                        imageUrl: coverUrl,
                                        fit: BoxFit.cover,
                                        width: 42,
                                        height: 42,
                                        showLoading: false,
                                        borderRadius: 0,
                                        errorBuilder:
                                            (
                                              context,
                                              error,
                                              stackTrace,
                                            ) => Image.asset(
                                              'assets/music/icons/default_cover.jpg',
                                              fit: BoxFit.cover,
                                            ),
                                      ),
                              ),
                              if (selected)
                                Container(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  child: const Icon(
                                    Icons.play_arrow,
                                    color: Colors.white,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        title: Text(
                          it.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          it.artist.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () async {
                          await controller.playAt(i);
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        },
                      );
                    },
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }

  static Future<void> show({
    required BuildContext context,
    required MusicPlayServiceController controller,
    required MusicCoverUrlResolver coverUrlResolver,
  }) async {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final screenSize = media.size;
    final anchor = context.findRenderObject();
    final anchorBox = anchor is RenderBox ? anchor : null;
    final anchorOffset = anchorBox == null
        ? Offset.zero
        : anchorBox.localToGlobal(Offset.zero);
    final anchorSize = anchorBox?.size ?? screenSize;
    final leftPad = anchorOffset.dx.clamp(0.0, screenSize.width);
    final rightPad = (screenSize.width - (anchorOffset.dx + anchorSize.width))
        .clamp(0.0, screenSize.width);
    final topPad = anchorOffset.dy.clamp(0.0, screenSize.height);
    final bottomPad =
        (screenSize.height - (anchorOffset.dy + anchorSize.height)).clamp(
          0.0,
          screenSize.height,
        );
    final drawerMaxWidth = min(520.0, anchorSize.width * 0.92).toDouble();
    final drawerMinWidth = min(380.0, anchorSize.width * 0.92).toDouble();

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, a1, a2) {
        return Padding(
          padding: EdgeInsets.fromLTRB(leftPad, topPad, rightPad, bottomPad),
          child: Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: theme.colorScheme.surface,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: drawerMaxWidth,
                  minWidth: drawerMinWidth,
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: 56,
                      child: Row(
                        children: [
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              'player_playlist'.tr,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            icon: const Icon(Icons.close),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Obx(() {
                        final list = controller.playlist;
                        final current = controller.currentIndex.value;
                        return ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (c, i) {
                            final it = list[i];
                            final selected = i == current;
                            final coverUrl = coverUrlResolver(it, size: 120);
                            return ListTile(
                              selected: selected,
                              leading: SizedBox(
                                width: 42,
                                height: 42,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: coverUrl.trim().isEmpty
                                          ? Image.asset(
                                              'assets/music/icons/default_cover.jpg',
                                              fit: BoxFit.cover,
                                            )
                                          : CustomExtendedImage(
                                              imageUrl: coverUrl,
                                              fit: BoxFit.cover,
                                              width: 42,
                                              height: 42,
                                              showLoading: false,
                                              borderRadius: 0,
                                              errorBuilder:
                                                  (
                                                    context,
                                                    error,
                                                    stackTrace,
                                                  ) => Image.asset(
                                                    'assets/music/icons/default_cover.jpg',
                                                    fit: BoxFit.cover,
                                                  ),
                                            ),
                                    ),
                                    if (selected)
                                      Container(
                                        color: Colors.black.withValues(
                                          alpha: 0.35,
                                        ),
                                        child: Icon(
                                          Icons.play_arrow,
                                          color: Colors.white,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              title: Text(
                                it.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                it.artist.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () async {
                                await controller.playAt(i);
                                if (ctx.mounted) Navigator.of(ctx).pop();
                              },
                            );
                          },
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, _, child) {
        final offset = Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
        return SlideTransition(position: offset, child: child);
      },
    );
  }
}
