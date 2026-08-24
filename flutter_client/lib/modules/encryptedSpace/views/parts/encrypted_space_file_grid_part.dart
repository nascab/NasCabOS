part of '../encrypted_space_view.dart';

class _EncryptedSpaceDetailBody extends StatefulWidget {
  const _EncryptedSpaceDetailBody({required this.ctrl, this.onRefresh});

  final EncryptedSpaceDetailController ctrl;

  /// 非 null 时启用下拉刷新（用于 App 端）
  final Future<void> Function()? onRefresh;

  @override
  State<_EncryptedSpaceDetailBody> createState() =>
      _EncryptedSpaceDetailBodyState();
}

class _EncryptedSpaceDetailBodyState extends State<_EncryptedSpaceDetailBody> {
  final ScrollController _gridScrollCtrl = ScrollController();
  Timer? _autoTimer;
  Timer? _throttleTimer;
  bool _dragging = false;
  double _viewportHeight = 0;
  Offset _lastLocal = const Offset(0, 0);

  int _crossCount = 2;
  double _cellW = 100;
  double _cellH = 100;
  double _padding = 12.0;
  double _spacing = 12.0;

  @override
  void initState() {
    super.initState();
    _gridScrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _throttleTimer?.cancel();
    _gridScrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_dragging) {
      widget.ctrl.updateDragSelection(
        _lastLocal,
        scrollOffset: _gridScrollCtrl.offset,
      );
      _scheduleHitTest();
    }
    // 接近底部时加载下一页
    if (!_gridScrollCtrl.hasClients) return;
    final pos = _gridScrollCtrl.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent - 400 &&
        widget.ctrl.hasMore.value &&
        !widget.ctrl.loadingMore.value) {
      widget.ctrl.loadMore();
    }
  }

  void _scheduleHitTest() {
    if (_throttleTimer?.isActive ?? false) return;
    _throttleTimer = Timer(const Duration(milliseconds: 60), _performHitTest);
  }

  void _performHitTest() {
    if (!_dragging) return;
    final rect = widget.ctrl.selectionRectContent.value;
    final hits = <int>{};
    final data = widget.ctrl.files;
    if (rect != null) {
      final rowHeight = _cellH + _spacing;
      final minRow = ((rect.top - _padding) / rowHeight).floor();
      final maxRow = ((rect.bottom - _padding) / rowHeight).ceil();

      final minI = (minRow * _crossCount).clamp(0, data.length);
      final maxI = ((maxRow + 1) * _crossCount).clamp(0, data.length);

      for (int i = minI; i < maxI; i++) {
        final row = i ~/ _crossCount;
        final col = i % _crossCount;
        final x = _padding + col * (_cellW + _spacing);
        final y = _padding + row * (_cellH + _spacing);
        final r = Rect.fromLTWH(x, y, _cellW, _cellH);
        if (r.overlaps(rect)) hits.add(i);
      }
    }
    widget.ctrl.updateDragPreview(hits);
  }

  void _ensureAutoTimer() {
    _autoTimer ??= Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!_dragging) return;
      final pos = _gridScrollCtrl.position;
      if (!pos.hasPixels) return;
      const edge = 30.0;
      double delta = 0.0;
      if (_lastLocal.dy < edge) {
        final t = (edge - _lastLocal.dy).clamp(0.0, edge) / edge;
        delta = -12.0 * t;
      } else {
        final distBottom = (_viewportHeight - _lastLocal.dy);
        if (distBottom < edge) {
          final t = (edge - distBottom).clamp(0.0, edge) / edge;
          delta = 12.0 * t;
        }
      }
      if (delta != 0.0) {
        final target = (pos.pixels + delta).clamp(0.0, pos.maxScrollExtent);
        _gridScrollCtrl.jumpTo(target);
      }
    });
  }

  Future<void> _downloadItems(List<Map<String, dynamic>> items) async {
    final urls = <String>[];
    for (final it in items) {
      final id = widget.ctrl.indexIdOf(it);
      if (id <= 0) continue;
      final name = widget.ctrl.displayNameOf(it);
      final url = widget.ctrl.buildDecodeUrl(
        indexId: id,
        download: true,
        fileName: name,
      );
      urls.add(url);
    }
    if (urls.isEmpty) return;
    if (!Get.isRegistered<DownloadController>()) {
      Get.put(DownloadController(), permanent: true);
    }
    await Get.find<DownloadController>().handleDownload(urls);
  }

  Future<void> _openItem(Map<String, dynamic> item) async {
    final type = widget.ctrl.fileTypeOf(item);
    if (type == 'image' || type == 'video') {
      widget.ctrl.openItem(item);
      return;
    }
    await _downloadItems([item]);
  }

  List<ContextMenuEntry> _menuEntriesForSelection(
    List<Map<String, dynamic>> selected,
  ) {
    final count = selected.length;
    final hasSingle = count == 1;
    return <ContextMenuEntry>[
      if (hasSingle)
        CustomContextMenuItem.create(
          label: Text('open'.tr),
          icon: const Icon(Icons.open_in_new, size: 18),
          value: 'open',
          onSelected: (_) => _openItem(selected.first),
        ),
      if (hasSingle) const MenuDivider(),
      CustomContextMenuItem.create(
        label: Text(count > 1 ? "${'download'.tr} ($count)" : 'download'.tr),
        icon: const Icon(Icons.download_outlined, size: 18),
        value: 'download',
        onSelected: (_) => _downloadItems(selected),
      ),
      const MenuDivider(),
      CustomContextMenuItem.create(
        color: Colors.red,
        label: Text(count > 1 ? "${'delete'.tr} ($count)" : 'delete'.tr),
        icon: const Icon(Icons.delete_outline, size: 18),
        value: 'delete',
        onSelected: (_) => widget.ctrl.deleteItemsFlow(selected),
      ),
    ];
  }

  Future<void> _showContextMenuAt({
    required BuildContext context,
    required Offset globalPosition,
    Map<String, dynamic>? hitItem,
  }) async {
    if (hitItem != null) {
      final id = widget.ctrl.indexIdOf(hitItem);
      if (id > 0 && !widget.ctrl.selectedIds.contains(id)) {
        widget.ctrl.selectOnly(id);
      }
    }

    final selected = widget.ctrl.getSelectedItems();
    if (selected.isEmpty) return;

    ContextMenuUtil.showAtPosition(
      context,
      entries: _menuEntriesForSelection(selected),
      position: globalPosition,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (widget.ctrl.isLoading.value && widget.ctrl.files.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (widget.ctrl.errorText.value.isNotEmpty) {
        return Center(child: Text(widget.ctrl.errorText.value));
      }
      if (widget.ctrl.files.isEmpty) {
        return const CustomNoData(text: '将文件或文件夹拖动到此处上传');
      }

      return LayoutBuilder(
        builder: (context, constraints) {
          _viewportHeight = constraints.maxHeight;
          final maxWidth = constraints.maxWidth;
          const spacing = 12.0;
          const padding = 12.0;
          // 与 GridView padding 一致，避免 aspect ratio 与真实单元格宽度错位导致格子偏矮
          final gridWidth = (maxWidth - padding * 2) > 0
              ? maxWidth - padding * 2
              : maxWidth;
          const desiredWidth = 140.0;
          final crossAxisCount =
              (gridWidth / desiredWidth).floor().clamp(2, 8);
          final totalSpacing = spacing * (crossAxisCount - 1);
          final itemWidth = ((gridWidth - totalSpacing) / crossAxisCount)
              .clamp(1.0, double.infinity);
          const cellHeight = 208.0;

          _crossCount = crossAxisCount;
          _cellW = itemWidth;
          _cellH = cellHeight;
          _padding = padding;
          _spacing = spacing;

          final enableDragSelection =
              DeviceUtils.isDesktop ||
              (DeviceUtils.isWeb && DeviceUtils.isDesktopLayout(context));

          final listContent = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: (details) async {
              final local = details.localPosition;
              final global = details.globalPosition;
              final data = widget.ctrl.files;
              int? hitIndex;
              for (int i = 0; i < data.length; i++) {
                final row = i ~/ crossAxisCount;
                final col = i % crossAxisCount;
                final x = padding + col * (itemWidth + spacing);
                final y =
                    padding -
                    _gridScrollCtrl.offset +
                    row * (cellHeight + spacing);
                final r = Rect.fromLTWH(x, y, itemWidth, cellHeight);
                if (r.contains(local)) {
                  hitIndex = i;
                  break;
                }
              }
              await _showContextMenuAt(
                context: context,
                globalPosition: global,
                hitItem: hitIndex == null ? null : data[hitIndex],
              );
            },
            onPanStart: !enableDragSelection
                ? null
                : (d) {
                    final local = d.localPosition;
                    _dragging = true;
                    _lastLocal = local;
                    _ensureAutoTimer();
                    widget.ctrl.startDragSelection(
                      local,
                      scrollOffset: _gridScrollCtrl.offset,
                    );
                  },
            onPanUpdate: !enableDragSelection
                ? null
                : (d) {
                    _lastLocal = d.localPosition;
                    widget.ctrl.updateDragSelection(
                      d.localPosition,
                      scrollOffset: _gridScrollCtrl.offset,
                    );
                    _scheduleHitTest();
                  },
            onPanEnd: !enableDragSelection
                ? null
                : (_) {
                    _performHitTest();
                    _dragging = false;
                    widget.ctrl.finishDragSelection();
                  },
            onTapDown: (d) {
              final p = d.localPosition;
              final data = widget.ctrl.files;
              bool hit = false;
              for (int i = 0; i < data.length; i++) {
                final row = i ~/ crossAxisCount;
                final col = i % crossAxisCount;
                final x = padding + col * (itemWidth + spacing);
                final y =
                    padding -
                    _gridScrollCtrl.offset +
                    row * (cellHeight + spacing);
                final r = Rect.fromLTWH(x, y, itemWidth, cellHeight);
                if (r.contains(p)) {
                  hit = true;
                  break;
                }
              }
              if (!hit && !widget.ctrl.isAdditiveSelectionActive) {
                widget.ctrl.clearSelect();
              }
            },
            child: GridView.builder(
              controller: _gridScrollCtrl,
              padding: const EdgeInsets.all(12),
              itemCount: widget.ctrl.files.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: spacing,
                crossAxisSpacing: spacing,
                mainAxisExtent: cellHeight,
              ),
              itemBuilder: (context, i) {
                final item = widget.ctrl.files[i];
                return _EncryptedSpaceFileCard(
                  key: ValueKey('encrypted_space_file_${item['id'] ?? i}'),
                  item: item,
                  ctrl: widget.ctrl,
                );
              },
            ),
          );
          return Stack(
            children: [
              widget.onRefresh != null
                  ? RefreshIndicator(
                      onRefresh: widget.onRefresh!,
                      child: listContent,
                    )
                  : listContent,
              Obx(() {
                final r = widget.ctrl.selectionRect.value;
                if (r == null) return const SizedBox.shrink();
                return Positioned(
                  left: r.left,
                  top: r.top,
                  width: r.width,
                  height: r.height,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.15),
                        border: Border.all(color: Colors.blue, width: 1),
                      ),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      );
    });
  }
}
