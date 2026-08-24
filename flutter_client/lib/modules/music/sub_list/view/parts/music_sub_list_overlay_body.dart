import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../list/view/parts/music_list_multi_select_bottom_bar.dart';
import '../../../music_main/controller/music_main_controller.dart';
import '../../../play_service/controller/music_play_service_controller.dart';
import '../../controller/music_sub_list_controller.dart';
import 'music_sub_list_table.dart';

class MusicSubListOverlayBody extends StatefulWidget {
  final MusicSubListController controller;
  final ScrollController scrollController;

  const MusicSubListOverlayBody({
    super.key,
    required this.controller,
    required this.scrollController,
  });

  @override
  State<MusicSubListOverlayBody> createState() =>
      _MusicSubListOverlayBodyState();
}

class _MusicSubListOverlayBodyState extends State<MusicSubListOverlayBody> {
  bool? _lastShowMultiBar;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (widget.controller.loading.value) {
        return const Center(child: CircularProgressIndicator());
      }
      final showMultiBar = widget.controller.isMultiSelectMode.value;
      if (_lastShowMultiBar != showMultiBar) {
        _lastShowMultiBar = showMultiBar;
        final desired = showMultiBar;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!Get.isRegistered<MusicMainController>()) return;
          final mainCtrl = Get.find<MusicMainController>();
          if (mainCtrl.hidePlayerBar.value != desired) {
            mainCtrl.hidePlayerBar.value = desired;
          }
        });
      }

      final playCtrl = Get.isRegistered<MusicPlayServiceController>()
          ? Get.find<MusicPlayServiceController>()
          : null;
      final showPlayerBar =
          !showMultiBar &&
          playCtrl != null &&
          playCtrl.isReady.value &&
          playCtrl.playlist.isNotEmpty;
      final playerExtraSpace = showPlayerBar
          ? (112.0 + MediaQuery.of(context).padding.bottom)
          : 0.0;

      return Stack(
        children: [
          MusicSubListTable(
            controller: widget.controller,
            scrollController: widget.scrollController,
          ),
          if (showMultiBar)
            Positioned(
              left: 0,
              right: 0,
              bottom: playerExtraSpace,
              child: MusicListMultiSelectBottomBar(
                controller: widget.controller,
              ),
            ),
        ],
      );
    });
  }
}
