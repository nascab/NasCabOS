import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/music_sub_list_controller.dart';
import 'parts/music_sub_list_header.dart';
import 'parts/music_sub_list_overlay_body.dart';
import '../../music_main/controller/music_main_controller.dart';
import '../../../../utils/device_utils.dart';
import '../../play_service/app_components/app_music_play_ctrl_floating_bar.dart';
import '../../play_service/play_ctrl_fullscreen/music_play_ctrl_fullscreen_sheet.dart';

class MusicSubListOverlay extends StatefulWidget {
  final String keyType;
  final String name;
  final bool isFavorite;
  final bool isHistory;
  final int? listId;
  final int? seriesIndexId;
  final int? collectionId;
  final String? listType;
  final MusicSubListSortBy initialSortBy;
  final MusicSubListSortOrder initialSortOrder;
  final String? coverCenterAsset;
  final double coverCenterAssetSize;
  final VoidCallback onClose;

  const MusicSubListOverlay({
    super.key,
    required this.keyType,
    required this.name,
    this.isFavorite = false,
    this.isHistory = false,
    this.listId,
    this.seriesIndexId,
    this.collectionId,
    this.listType,
    this.initialSortBy = MusicSubListSortBy.filename,
    this.initialSortOrder = MusicSubListSortOrder.asc,
    this.coverCenterAsset,
    this.coverCenterAssetSize = 42,
    required this.onClose,
  });

  @override
  State<MusicSubListOverlay> createState() => _MusicSubListOverlayState();
}

class _MusicSubListOverlayState extends State<MusicSubListOverlay> {
  final ScrollController _scrollController = ScrollController();
  late final String _controllerTag;
  MusicSubListController? _controller;

  @override
  void initState() {
    super.initState();
    _controllerTag =
        'music_sub_list_${widget.keyType}_${widget.name}_${widget.isFavorite}_${widget.isHistory}_${widget.listType ?? ''}_${widget.listId ?? 0}_${widget.seriesIndexId ?? 0}_${widget.collectionId ?? 0}_${widget.initialSortBy}_${widget.initialSortOrder}_${UniqueKey()}';
    if (!Get.isRegistered<MusicSubListController>(tag: _controllerTag)) {
      Get.put(
        MusicSubListController(
          keyType: widget.keyType,
          name: widget.name,
          isFavorite: widget.isFavorite,
          isHistory: widget.isHistory,
          listType: widget.listType,
          listId: widget.listId,
          seriesIndexId: widget.seriesIndexId,
          collectionId: widget.collectionId,
          initialSortBy: widget.initialSortBy,
          initialSortOrder: widget.initialSortOrder,
        ),
        tag: _controllerTag,
      );
    }
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    if (Get.isRegistered<MusicMainController>()) {
      final mainCtrl = Get.find<MusicMainController>();
      if (mainCtrl.hidePlayerBar.value) {
        mainCtrl.hidePlayerBar.value = false;
      }
    }
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    if (Get.isRegistered<MusicSubListController>(tag: _controllerTag)) {
      Get.delete<MusicSubListController>(tag: _controllerTag);
    }
    super.dispose();
  }

  void _onScroll() {
    final ctrl =
        _controller ??
        (Get.isRegistered<MusicSubListController>(tag: _controllerTag)
            ? Get.find<MusicSubListController>(tag: _controllerTag)
            : null);
    if (ctrl == null) return;
    if (!_scrollController.hasClients) return;
    ctrl.markScrolling();
    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent - 360) {
      ctrl.loadMore(fromAuto: true).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<MusicSubListController>(
      tag: _controllerTag,
      builder: (ctrl) {
        _controller = ctrl;
        final customColors = Theme.of(context).extension<CustomColors>();
        return Positioned.fill(
          child: Material(
            color: customColors?.mainContentBgColor,
            child: SafeArea(
              child: Column(
                children: [
                  (DeviceUtils.isMobile || DeviceUtils.isPhone(context))
                      ? MusicSubListMobileHeader(
                          controller: ctrl,
                          onClose: widget.onClose,
                          coverCenterAsset: widget.coverCenterAsset,
                          coverCenterAssetSize: widget.coverCenterAssetSize,
                        )
                      : MusicSubListHeader(
                          controller: ctrl,
                          onClose: widget.onClose,
                          coverCenterAsset: widget.coverCenterAsset,
                          coverCenterAssetSize: widget.coverCenterAssetSize,
                        ),
                  Expanded(
                    child: MusicSubListOverlayBody(
                      controller: ctrl,
                      scrollController: _scrollController,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class MusicSubListMobilePage extends StatefulWidget {
  final String keyType;
  final String name;
  final bool isFavorite;
  final bool isHistory;
  final int? listId;
  final int? seriesIndexId;
  final int? collectionId;
  final String? listType;
  final MusicSubListSortBy initialSortBy;
  final MusicSubListSortOrder initialSortOrder;
  final String? coverCenterAsset;
  final double coverCenterAssetSize;

  const MusicSubListMobilePage({
    super.key,
    required this.keyType,
    required this.name,
    this.isFavorite = false,
    this.isHistory = false,
    this.listId,
    this.seriesIndexId,
    this.collectionId,
    this.listType,
    this.initialSortBy = MusicSubListSortBy.filename,
    this.initialSortOrder = MusicSubListSortOrder.asc,
    this.coverCenterAsset,
    this.coverCenterAssetSize = 42,
  });

  @override
  State<MusicSubListMobilePage> createState() => _MusicSubListMobilePageState();
}

class _MusicSubListMobilePageState extends State<MusicSubListMobilePage> {
  final ScrollController _scrollController = ScrollController();
  late final String _controllerTag;
  MusicSubListController? _controller;
  bool _showFullPlayer = false;

  void _openFullscreen() {
    if (_showFullPlayer) return;
    setState(() => _showFullPlayer = true);
  }

  void _closeFullscreen() {
    if (!_showFullPlayer) return;
    setState(() => _showFullPlayer = false);
  }

  @override
  void initState() {
    super.initState();
    _controllerTag =
        'music_sub_list_page_${widget.keyType}_${widget.name}_${widget.isFavorite}_${widget.isHistory}_${widget.listType ?? ''}_${widget.listId ?? 0}_${widget.seriesIndexId ?? 0}_${widget.collectionId ?? 0}_${widget.initialSortBy}_${widget.initialSortOrder}_${UniqueKey()}';
    if (!Get.isRegistered<MusicSubListController>(tag: _controllerTag)) {
      Get.put(
        MusicSubListController(
          keyType: widget.keyType,
          name: widget.name,
          isFavorite: widget.isFavorite,
          isHistory: widget.isHistory,
          listType: widget.listType,
          listId: widget.listId,
          seriesIndexId: widget.seriesIndexId,
          collectionId: widget.collectionId,
          initialSortBy: widget.initialSortBy,
          initialSortOrder: widget.initialSortOrder,
        ),
        tag: _controllerTag,
      );
    }
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    if (Get.isRegistered<MusicMainController>()) {
      final mainCtrl = Get.find<MusicMainController>();
      if (mainCtrl.hidePlayerBar.value) {
        mainCtrl.hidePlayerBar.value = false;
      }
    }
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    if (Get.isRegistered<MusicSubListController>(tag: _controllerTag)) {
      Get.delete<MusicSubListController>(tag: _controllerTag);
    }
    super.dispose();
  }

  void _onScroll() {
    final ctrl =
        _controller ??
        (Get.isRegistered<MusicSubListController>(tag: _controllerTag)
            ? Get.find<MusicSubListController>(tag: _controllerTag)
            : null);
    if (ctrl == null) return;
    if (!_scrollController.hasClients) return;
    ctrl.markScrolling();
    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent - 360) {
      ctrl.loadMore(fromAuto: true).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();

    if (_showFullPlayer) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: MusicPlayCtrlFullScreenSheet(onClose: _closeFullscreen),
      );
    }

    return GetBuilder<MusicSubListController>(
      tag: _controllerTag,
      builder: (ctrl) {
        _controller = ctrl;
        final floatingBottom = 35.0;
        return Scaffold(
          appBar: AppBar(title: Text(widget.name)),
          body: Stack(
            children: [
              Positioned.fill(
                child: Material(
                  color: customColors?.mainContentBgColor,
                  child: SafeArea(
                    child: Column(
                      children: [
                        MusicSubListMobilePageHeader(controller: ctrl),
                        Expanded(
                          child: MusicSubListOverlayBody(
                            controller: ctrl,
                            scrollController: _scrollController,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: floatingBottom,
                child: AppMusicPlayCtrlFloatingBar(
                  onOpenFullscreen: _openFullscreen,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
