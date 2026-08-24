part of '../photo_collection_list_view.dart';

class _CollectionPreviewGrid extends StatelessWidget {
  final List<PhotoCollectionPreviewItem> previews;
  _CollectionPreviewGrid({required this.previews});

  @override
  Widget build(BuildContext context) {
    if (previews.isEmpty) {
      return CustomNoData(
        text: "",
        backgroundColorList: [Color(0xFF0061FF), Color(0xFF60EFFF)],
        imagePath: 'assets/icons/no_data.png',
      );
    }

    final urls = previews.take(4).map((e) {
      return ApiController.instance.getTinyUrl(e.fullpath);
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
