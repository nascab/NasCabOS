part of '../encrypted_space_view.dart';

class _EncryptedSpaceFileCard extends StatelessWidget {
  const _EncryptedSpaceFileCard({
    super.key,
    required this.item,
    required this.ctrl,
  });

  final Map<String, dynamic> item;
  final EncryptedSpaceDetailController ctrl;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final theme = Theme.of(context);
      final indexId = ctrl.indexIdOf(item);
      final type = ctrl.fileTypeOf(item);
      final fileName = ctrl.displayNameOf(item);
      final moreKey = GlobalKey();
      final isSelected = indexId > 0 && ctrl.selectedIds.contains(indexId);

      String iconForName(String name) {
        final parts = name.split('.');
        final ext = parts.length > 1 ? parts.last.toLowerCase() : '';
        switch (ext) {
          case 'epub':
          case 'mobi':
          case 'azw3':
            return 'assets/icons/file/ebook.png';
          case 'doc':
            return 'assets/icons/file/doc.png';
          case 'docx':
            return 'assets/icons/file/docx.png';
          case 'xls':
            return 'assets/icons/file/xls.png';
          case 'xlsx':
            return 'assets/icons/file/xlsx.png';
          case 'xml':
            return 'assets/icons/file/xml.png';
          case 'txt':
            return 'assets/icons/file/txt.png';
          case 'log':
            return 'assets/icons/file/log.png';
          case 'mp3':
          case 'flac':
          case 'aac':
          case 'wav':
          case 'ogg':
          case 'opus':
          case 'wma':
          case 'ape':
            return 'assets/icons/file/audio.png';
          default:
            return 'assets/icons/file/file.png';
        }
      }

      Future<void> openItem(Map<String, dynamic> it) async {
        final id = ctrl.indexIdOf(it);
        if (id <= 0) return;
        final t = ctrl.fileTypeOf(it);
        if (t == 'image' || t == 'video') {
          ctrl.openItem(it);
          return;
        }
        final name = ctrl.displayNameOf(it);
        final url = ctrl.buildDecodeUrl(
          indexId: id,
          download: true,
          fileName: name,
        );
        if (!Get.isRegistered<DownloadController>()) {
          Get.put(DownloadController(), permanent: true);
        }
        await Get.find<DownloadController>().handleDownload([url]);
      }

      Future<void> downloadItems(List<Map<String, dynamic>> items) async {
        final urls = <String>[];
        for (final it in items) {
          final id = ctrl.indexIdOf(it);
          if (id <= 0) continue;
          final name = ctrl.displayNameOf(it);
          urls.add(
            ctrl.buildDecodeUrl(indexId: id, download: true, fileName: name),
          );
        }
        if (urls.isEmpty) return;
        if (!Get.isRegistered<DownloadController>()) {
          Get.put(DownloadController(), permanent: true);
        }
        await Get.find<DownloadController>().handleDownload(urls);
      }

      List<Map<String, dynamic>> selectionForMenu() {
        if (indexId > 0 && !ctrl.selectedIds.contains(indexId)) {
          ctrl.selectOnly(indexId);
        }
        final selected = ctrl.getSelectedItems();
        return selected.isNotEmpty ? selected : [item];
      }

      List<ContextMenuEntry> entriesFor(List<Map<String, dynamic>> selected) {
        final count = selected.length;
        final hasSingle = count == 1;
        return <ContextMenuEntry>[
          if (hasSingle)
            CustomContextMenuItem.create(
              label: Text('open'.tr),
              icon: const Icon(Icons.open_in_new, size: 18),
              value: 'open',
              onSelected: (_) => openItem(selected.first),
            ),
          if (hasSingle) const MenuDivider(),
          CustomContextMenuItem.create(
            label: Text(
              count > 1 ? "${'download'.tr} ($count)" : 'download'.tr,
            ),
            icon: const Icon(Icons.download_outlined, size: 18),
            value: 'download',
            onSelected: (_) => downloadItems(selected),
          ),
          const MenuDivider(),
          CustomContextMenuItem.create(
            color: Colors.red,
            label: Text(count > 1 ? "${'delete'.tr} ($count)" : 'delete'.tr),
            icon: const Icon(Icons.delete_outline, size: 18),
            value: 'delete',
            onSelected: (_) => ctrl.deleteItemsFlow(selected),
          ),
        ];
      }

      Widget thumb() {
        final bg = theme.colorScheme.surfaceContainerHighest;

        if (type != 'image' && type != 'video') {
          final iconPath = iconForName(fileName);
          return Container(
            color: theme.cardColor,
            alignment: Alignment.center,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                iconPath,
                width: 70,
                height: 70,
                fit: BoxFit.contain,
              ),
            ),
          );
        }

        final url = ctrl.buildDecodeUrl(indexId: indexId, type: 'tiny');
        final img = CustomExtendedImage(
          imageUrl: url,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          showLoading: false,
          borderRadius: 0,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: bg,
              alignment: Alignment.center,
              child: Icon(
                type == 'video'
                    ? Icons.movie_outlined
                    : Icons.image_not_supported_outlined,
                color: theme.colorScheme.onSurfaceVariant,
                size: 38,
              ),
            );
          },
        );

        if (type != 'video') return img;
        return Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            img,
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 22,
              ),
            ),
          ],
        );
      }

      final borderColor = isSelected
          ? theme.colorScheme.primary
          : Colors.transparent;
      final cardColor = isSelected
          ? theme.colorScheme.primary.withValues(alpha: 0.08)
          : null;

      return Card(
        color: cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borderColor, width: 1),
        ),
        child: InkWell(
          onTap: () async {
            if (indexId <= 0) return;
            if (!DeviceUtils.isDesktopOrWeb) {
              await openItem(item);
              return;
            }
            // 桌面/Web：视频单击即可播放（仍通过 AppRoutes.toVideoPlayer），避免依赖双击
            if (ctrl.fileTypeOf(item) == 'video' &&
                !ctrl.isAdditiveSelectionActive) {
              await openItem(item);
              return;
            }
            final isDouble = ctrl.registerTap(indexId);
            if (isDouble) {
              await openItem(item);
              return;
            }
            final additive = ctrl.isAdditiveSelectionActive;
            if (additive) {
              ctrl.toggleSelect(indexId);
            } else {
              ctrl.selectOnly(indexId);
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox.expand(child: thumb()),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        fileName.isNotEmpty ? fileName : '$indexId',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    IconButton(
                      key: moreKey,
                      tooltip: 'more'.tr,
                      onPressed: () {
                        final selected = selectionForMenu();
                        final entries = entriesFor(selected);
                        final box =
                            moreKey.currentContext?.findRenderObject()
                                as RenderBox?;
                        final overlay =
                            Overlay.of(context).context.findRenderObject()
                                as RenderBox?;
                        if (box == null || overlay == null) return;
                        final pos = box.localToGlobal(
                          Offset.zero,
                          ancestor: overlay,
                        );
                        ContextMenuUtil.showAtPosition(
                          context,
                          entries: entries,
                          position: pos + Offset(0, box.size.height),
                        );
                      },
                      icon: Icon(
                        Icons.more_horiz,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
