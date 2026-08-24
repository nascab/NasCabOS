import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../base/components/custom_album.dart';
import '../../../../base/components/custom_button.dart';
import '../../../../base/components/custom_checkbox.dart';
import '../../../../base/components/custom_extended_image.dart';
import '../../../../../utils/dialog_util.dart';
import '../../../base/beans/video_item_bean.dart';
import '../../../base/video_utils/video_utils.dart';
import '../../models/video_album_model.dart';
import '../../service/video_album_api_service.dart';

class VideoAlbumSelectDialog extends StatefulWidget {
  final int? initialSelectedId;
  const VideoAlbumSelectDialog({super.key, this.initialSelectedId});

  static Future<VideoAlbumItem?> show(
    BuildContext context, {
    int? initialSelectedId,
  }) {
    return showDialog<VideoAlbumItem?>(
      context: context,
      builder: (ctx) =>
          VideoAlbumSelectDialog(initialSelectedId: initialSelectedId),
    );
  }

  @override
  State<VideoAlbumSelectDialog> createState() => _VideoAlbumSelectDialogState();
}

class _VideoAlbumSelectDialogState extends State<VideoAlbumSelectDialog> {
  bool _loading = true;
  List<VideoAlbumItem> _items = const <VideoAlbumItem>[];

  List<String> _previewUrls(List<VideoAlbumPreviewItem> previews) {
    return previews.take(4).map((e) {
      final item = VideoHomeItemBean(
        id: 0,
        mediaType: '',
        path: '',
        filename: '',
        firstFilePath: e.firstFilePath,
        nfoName: '',
        nfoYear: 0,
        nfoScore: 0,
        nfoRegions: '',
        nfoGenres: '',
        posterPath: '',
        fanartPath: '',
        logoPath: '',
        progress: 0,
        viewTime: null,
        createTime: null,
        fullPath: e.fullpath,
      );
      return VideoUtils.getPosterUrl(item, size: 500);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() => _loading = true);
    }
    try {
      final res = await VideoAlbumApiService.instance.listAlbums(
        page: 1,
        pageSize: 100,
        sortField: 'create_time',
        sortOrder: 'desc',
        previewLimit: 4,
      );
      final data = res.data;
      if (!res.success || data == null) {
        if (mounted) {
          setState(() {
            _items = const <VideoAlbumItem>[];
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _items = data.items.where((e) => e.isOwner).toList();
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreateAlbum() async {
    var name = '';
    final rootNav = Navigator.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final canSubmit = name.trim().isNotEmpty;
            return DialogUtil.createAlertDialog(
              title: Text('create'.tr),
              content: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 280,
                  maxWidth: 520,
                ),
                child: TextFormField(
                  initialValue: '',
                  autofocus: true,
                  onChanged: (v) {
                    name = v;
                    setState(() {});
                  },
                  decoration: InputDecoration(
                    labelText: 'name'.tr,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text('cancel'.tr),
                ),
                ElevatedButton(
                  onPressed: !canSubmit
                      ? null
                      : () async {
                            final trimmed = name.trim();
                            final res =
                                await VideoAlbumApiService.instance.createAlbum(
                              name: trimmed,
                              isPublic: false,
                            );
                            if (!res.success) {
                              if (res.message != null &&
                                  res.message!.isNotEmpty) {
                                DialogUtil.showInfoDialog(
                                  title: 'tip'.tr,
                                  content: res.message!,
                                );
                              }
                              return;
                            }
                            final m = res.data;
                            final id = (m?['id'] as num?)?.toInt() ?? 0;
                            if (id <= 0) {
                              DialogUtil.showInfoDialog(
                                title: 'tip'.tr,
                                content: 'operation_failed'.tr,
                              );
                              return;
                            }
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            if (!mounted) return;
                            rootNav.pop(
                              VideoAlbumItem(
                                id: id,
                                ownerId: 0,
                                name: trimmed,
                                isPublic: false,
                                isOwner: true,
                                previews: const [],
                              ),
                            );
                          },
                    child: Text('ok'.tr),
                  ),
                ],
              );
            },
          );
        },
      );
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = widget.initialSelectedId ?? 0;
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = (screenWidth - 48).clamp(320.0, 860.0);

    Widget body;
    if (_loading) {
      body = const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_items.isEmpty) {
      body = SizedBox(
        width: double.infinity,
        height: 280,
        child: Center(
          child: CustomButton(
            text: 'create'.tr,
            icon: const Icon(Icons.add),
            onPressed: _openCreateAlbum,
          ),
        ),
      );
    } else {
      body = SizedBox(
        height: (_items.length * 200.0).clamp(220.0, 620.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 360,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.9,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final album = _items[index];
                      final checked = selectedId > 0 && album.id == selectedId;
                      return _AlbumSelectCard(
                        album: album,
                        checked: checked,
                        previewUrls: _previewUrls(album.previews),
                        onSelect: () => Navigator.of(context).pop(album),
                      );
                    }, childCount: _items.length),
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    return AlertDialog(
      title: Text('video_album_select'.tr),
      content: SizedBox(width: dialogWidth, child: body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text('cancel'.tr),
        ),
      ],
    );
  }
}

class _AlbumSelectCard extends StatelessWidget {
  final VideoAlbumItem album;
  final bool checked;
  final List<String> previewUrls;
  final VoidCallback onSelect;

  const _AlbumSelectCard({
    required this.album,
    required this.checked,
    required this.previewUrls,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final headerLeft = Row(
      children: [
        Flexible(
          child: Text(
            album.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.white,
              shadows: [
                Shadow(
                  blurRadius: 6,
                  color: Colors.black54,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    return CustomAlbum(
      preview: _AlbumPreviewGrid(urls: previewUrls),
      onTap: onSelect,
      headerLeft: headerLeft,
      headerRight: null,
      headerHeight: 50,
      headerPosition: CustomAlbumHeaderPosition.bottom,
      overlayChildren: [
        Positioned(
          top: 8,
          right: 8,
          child: CustomCheckbox(
            value: checked,
            onChanged: (_) => onSelect(),
            isCircle: true,
            side: const BorderSide(color: Colors.white, width: 2),
          ),
        ),
      ],
    );
  }
}

class _AlbumPreviewGrid extends StatelessWidget {
  final List<String> urls;
  const _AlbumPreviewGrid({required this.urls});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safeUrls = urls.where((e) => e.trim().isNotEmpty).toList();
    if (safeUrls.isEmpty) {
      return Container(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        child: Icon(
          Icons.video_collection_outlined,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          size: 46,
        ),
      );
    }

    final show = safeUrls.take(4).toList();
    if (show.length == 1) {
      return CustomExtendedImage(imageUrl: show.first, fit: BoxFit.cover);
    }

    final itemCount = show.length;
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 1,
        mainAxisSpacing: 1,
      ),
      itemCount: itemCount,
      itemBuilder: (ctx, i) {
        return CustomExtendedImage(imageUrl: show[i], fit: BoxFit.cover);
      },
    );
  }
}
