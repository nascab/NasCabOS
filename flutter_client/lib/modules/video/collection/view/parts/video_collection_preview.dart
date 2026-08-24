part of '../video_collection_list_view.dart';

class _CollectionPreviewGrid extends StatelessWidget {
  final List<VideoCollectionPreviewItem> previews;
  _CollectionPreviewGrid({required this.previews});

  @override
  Widget build(BuildContext context) {
    if (previews.isEmpty) {
      final theme = Theme.of(context);
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

    final urls = previews.take(4).map((e) {
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

    Widget buildImage(String url) {
      return CustomExtendedImage(
        imageUrl: url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        borderRadius: 0,
        showLoading: false,
      );
    }

    Widget buildMainContent() {
      final children = <Widget>[];
      for (int i = 0; i < urls.length; i++) {
        children.add(Expanded(child: buildImage(urls[i])));
        if (i != urls.length - 1) {
          children.add(const SizedBox(width: 1));
        }
      }
      return Row(children: children);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return buildMainContent();
      },
    );
  }
}
