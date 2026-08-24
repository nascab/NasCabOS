import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_extended_image.dart';
import '../../../base/components/custom_no_data.dart';
import '../../base/beans/video_item_bean.dart';
import '../../../../core/api/api_controller.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/toast_util.dart';
import '../service/video_tmdb_api_service.dart';
import '../../scrape/service/video_scrape_api_service.dart';

class VideoSearchMediaDialog {
  static Future<void> show(
    BuildContext context, {
    required VideoHomeItemBean item,
  }) {
    final defaultMediaType =
            item.mediaType.toLowerCase() == 'movie' ||
            item.mediaType.toLowerCase() == 'bdmv' ||
            item.mediaType.toLowerCase() == 'video_ts'
        ? 'movie'
        : 'tv';
    final defaultQuery = item.nfoName.trim().isNotEmpty
        ? item.nfoName.trim()
        : item.filename;

    return showDialog<void>(
      context: context,
      builder: (context) {
        return _VideoSearchMediaDialogContent(
          item: item,
          defaultMediaType: defaultMediaType,
          defaultQuery: defaultQuery,
        );
      },
    );
  }
}

class _VideoSearchMediaDialogContent extends StatefulWidget {
  final VideoHomeItemBean item;
  final String defaultMediaType;
  final String defaultQuery;

  const _VideoSearchMediaDialogContent({
    required this.item,
    required this.defaultMediaType,
    required this.defaultQuery,
  });

  @override
  State<_VideoSearchMediaDialogContent> createState() =>
      _VideoSearchMediaDialogContentState();
}

class _VideoSearchMediaDialogContentState
    extends State<_VideoSearchMediaDialogContent> {
  late final TextEditingController _queryController;
  late final TextEditingController _tmdbIdController;

  late String _mediaType;
  String _searchMode = 'keyword';

  int _page = 1;
  int _totalPages = 0;
  bool _loading = false;
  List<VideoTmdbSearchItem> _results = const [];

  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    _mediaType = widget.defaultMediaType;
    _queryController = TextEditingController(text: widget.defaultQuery);
    _tmdbIdController = TextEditingController();
  }

  @override
  void dispose() {
    _queryController.dispose();
    _tmdbIdController.dispose();
    super.dispose();
  }

  Future<void> _applyResult(VideoTmdbSearchItem r) async {
    if (widget.item.id <= 0 || r.id <= 0) return;
    try {
      final resp = await VideoScrapeApiService.instance.startScrape(
        indexId: widget.item.id,
        tmdbId: r.id,
        mode: 'manual',
        showLoading: false,
      );
      if (!mounted) return;
      // 成功：resp.success 为 true，或 HTTP 200 且 body 含 success:true，或 data.started == true
      final raw = resp.rawResponse;
      final bool serverSuccess =
          raw is Map &&
          (identical(raw['success'], true) || raw['success'] == 'true');
      final bool dataStarted =
          resp.data is Map && ((resp.data as Map)['started'] == true);
      final bool ok =
          resp.success || (resp.code == 200 && (serverSuccess || dataStarted));
      if (!ok) {
        ToastUtil.show('video_scrape_start_failed'.tr);
        return;
      }
      // 先关闭对话框，再显示 Toast，否则 Toast 会被对话框遮挡或一起被移除
      Navigator.of(context).pop();
      ToastUtil.show('video_scrape_apply_success_toast'.tr);
    } catch (_) {
      if (!mounted) return;
      ToastUtil.show('video_scrape_start_failed'.tr);
    }
  }

  Future<void> _searchFromUi({int? overridePage}) async {
    final token = ++_searchToken;
    setState(() {
      _loading = true;
    });
    try {
      final p = overridePage ?? _page;
      final query = _queryController.text.trim();
      final tmdbId = _tmdbIdController.text.trim();
      final res = await VideoTmdbApiService.instance.search(
        mediaType: _mediaType,
        searchMode: _searchMode,
        query: query,
        tmdbId: tmdbId,
        page: p,
        showLoading: false,
      );
      if (!mounted || token != _searchToken) return;
      setState(() {
        _page = res.page;
        _totalPages = res.totalPages;
        _results = res.results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Widget _buildModePicker() {
    final theme = Theme.of(context);
    Widget chip({
      required bool selected,
      required String text,
      VoidCallback? onTap,
    }) {
      final bg = selected
          ? theme.colorScheme.primary.withValues(alpha: 0.14)
          : Colors.transparent;
      final fg = selected
          ? theme.colorScheme.primary
          : theme.colorScheme.onSurface;
      final content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(color: fg),
        ),
      );
      if (onTap == null) {
        return Material(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          child: content,
        );
      }
      return Material(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: content,
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        chip(
          selected: true,
          text: _mediaType == 'movie'
              ? 'video_home_type_movie'.tr
              : 'video_home_type_tv'.tr,
        ),
        const SizedBox(width: 12),
        chip(
          selected: _searchMode == 'keyword',
          text: 'video_tmdb_search_mode_keyword'.tr,
          onTap: () {
            setState(() {
              _searchMode = 'keyword';
            });
          },
        ),
        chip(
          selected: _searchMode == 'tmdb_id',
          text: 'video_tmdb_search_mode_tmdb_id'.tr,
          onTap: () {
            setState(() {
              _searchMode = 'tmdb_id';
            });
          },
        ),
      ],
    );
  }

  static const double _posterWidth = 110;
  static const double _posterHeight = 164;
  static const double _narrowBreakpoint = 600;
  static const double _narrowPosterScale = 0.6;

  Widget _resultRow(VideoTmdbSearchItem r) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth < _narrowBreakpoint;
    final posterW = isNarrow ? _posterWidth * _narrowPosterScale : _posterWidth;
    final posterH = isNarrow
        ? _posterHeight * _narrowPosterScale
        : _posterHeight;

    final title = r.title.isNotEmpty ? r.title : r.originalTitle;
    final subtitleParts = <String>[
      if (r.year > 0) r.year.toString(),
      if (r.id > 0) 'TMDB ${r.id}',
    ];
    final subtitle = subtitleParts.join(' · ');
    final posterUrl = r.posterUrl.isNotEmpty
        ? ApiController.instance.getVideoPosterImageUrl(
            tmdbId: r.id.toString(),
            size: 240,
            thumb: r.posterUrl,
            mediaType: r.mediaType,
          )
        : '';
    final actorsText = (r.actors).take(6).join(' / ');
    final genresText = (r.genres).take(6).join(' / ');

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: posterW,
              height: posterH,
              child: posterUrl.isNotEmpty
                  ? CustomExtendedImage(
                      imageUrl: posterUrl,
                      fit: BoxFit.cover,
                      showLoading: false,
                      borderRadius: 8,
                    )
                  : Container(color: theme.colorScheme.surfaceContainerHighest),
            ),
          ),
          SizedBox(width: isNarrow ? 8 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    if (r.voteAverage > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        r.voteAverage.toStringAsFixed(1),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ],
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.65,
                      ),
                    ),
                  ),
                ],
                if (actorsText.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    actorsText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
                if (genresText.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    genresText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.65,
                      ),
                    ),
                  ),
                ],
                if (r.overview.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    r.overview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: isNarrow ? 8 : 12),
          ElevatedButton(
            onPressed: () => _applyResult(r),
            child: Text('video_tmdb_apply'.tr),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPrev = _page > 1 && !_loading;
    final canNext = _totalPages > 0 && _page < _totalPages && !_loading;

    final input = _searchMode == 'tmdb_id'
        ? TextField(
            controller: _tmdbIdController,
            decoration: InputDecoration(
              labelText: 'video_tmdb_id'.tr,
              hintText: 'video_tmdb_id_hint'.tr,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              suffixIcon: IconButton(
                onPressed: _loading
                    ? null
                    : () => _searchFromUi(overridePage: 1),
                icon: const Icon(Icons.search, size: 20),
              ),
            ),
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _searchFromUi(overridePage: 1),
          )
        : TextField(
            controller: _queryController,
            decoration: InputDecoration(
              labelText: 'video_tmdb_keyword'.tr,
              hintText: 'video_tmdb_keyword_hint'.tr,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              suffixIcon: IconButton(
                onPressed: _loading
                    ? null
                    : () => _searchFromUi(overridePage: 1),
                icon: const Icon(Icons.search, size: 20),
              ),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _searchFromUi(overridePage: 1),
          );

    return DialogUtil.createAlertDialog(
      title: Row(
        children: [
          Expanded(child: Text('video_search_media_info'.tr)),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      constraints: const BoxConstraints(maxWidth: 780, minWidth: 540),
      content: SizedBox(
        width: 740,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildModePicker(),
            const SizedBox(height: 12),
            input,
            const SizedBox(height: 4),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: _results.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 26),
                        child: _loading
                            ? const Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : CustomNoData(text: 'video_tmdb_no_results'.tr),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _results.length,
                        itemBuilder: (context, index) =>
                            _resultRow(_results[index]),
                      ),
              ),
            ),
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  IconButton(
                    onPressed: canPrev
                        ? () => _searchFromUi(overridePage: _page - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    _totalPages > 0
                        ? 'video_tmdb_page'.trParams({
                            'page': _page.toString(),
                            'total': _totalPages.toString(),
                          })
                        : 'video_tmdb_page_single'.trParams({
                            'page': _page.toString(),
                          }),
                  ),
                  IconButton(
                    onPressed: canNext
                        ? () => _searchFromUi(overridePage: _page + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                  const Spacer(),
                  if (_loading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
