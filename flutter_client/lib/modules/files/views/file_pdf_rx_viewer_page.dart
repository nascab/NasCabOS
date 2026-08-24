import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:NasCabOS/modules/book/reader_comic/service/book_comic_reader_api_service.dart';

/// 使用 pdfrx 打开远程 PDF（URL 已含鉴权参数）。
///
/// [fileHash] 非空且图书索引存在时：通过 `/api/book/history` 与服务器同步进度
/// （`current_page` 与漫画/TXT 一致为 **0-based**）。
///
/// [progressStorageKey] 通常为文件路径：在无法使用服务器进度（无 hash 或 404）时作本地备份。
///
/// [pdfUri] / [pdfBytes] / [localFilePath] 三选一（非 Web 缓存打开用本地路径）。
class FilePdfRxViewerPage extends StatefulWidget {
  FilePdfRxViewerPage({
    super.key,
    this.pdfUri,
    this.pdfBytes,
    this.localFilePath,
    required this.title,
    this.progressStorageKey,
    this.fileHash,
  }) {
    var n = 0;
    if (pdfUri != null) {
      n++;
    }
    if (pdfBytes != null) {
      n++;
    }
    final lp = localFilePath?.trim() ?? '';
    if (lp.isNotEmpty) {
      n++;
    }
    assert(n == 1, 'Exactly one of pdfUri, pdfBytes, or localFilePath');
  }

  final Uri? pdfUri;

  /// Web P2P 下由主线程拉取后的 PDF 字节（pdfrx Worker 无法走 p2p.local）。
  final Uint8List? pdfBytes;

  /// 非 Web：图书缓存目录下的本地 PDF 路径。
  final String? localFilePath;

  final String title;

  /// 非空时：将当前页写入 [SharedPreferences]，下次打开同一路径时恢复。
  final String? progressStorageKey;

  /// 非空时：从服务器读取/写入 `/api/book/history`（依赖图书索引中的 `file_hash`）。
  final String? fileHash;

  @override
  State<FilePdfRxViewerPage> createState() => _FilePdfRxViewerPageState();
}

class _FilePdfRxViewerPageState extends State<FilePdfRxViewerPage> {
  static const _prefPrefix = 'pdf_rx_page_';
  static const _kShowProgressKey = 'pdf_rx_show_progress';
  static const _kShowScrollThumbKey = 'pdf_rx_show_scroll_thumb';

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final PdfViewerController _viewerController = PdfViewerController();

  /// 从 AppBar 打开侧栏时选中的 Tab（0 搜索 / 1 目录 / 2 页码）。
  int _drawerInitialTab = 0;

  bool _prefsReady = false;
  int _restoredPage = 1;

  int _totalPages = 0;

  /// 当前页：用 [ValueNotifier] 更新，避免 setState 重建 [PdfViewer] 导致白屏/重载。
  final ValueNotifier<int> _currentPageNotifier = ValueNotifier<int>(1);

  /// 导航栏滑块拖动中的临时页码。
  final ValueNotifier<double?> _navScrubNotifier = ValueNotifier<double?>(null);

  List<PdfOutlineNode> _outline = const [];
  Timer? _saveDebounce;

  /// 与服务器 `current_page` 对齐（0-based），用于去重上传。
  int _lastPersistedServer0 = -1;
  int _lastPersistedTotal = 0;

  bool _showProgressBar = true;
  bool _showScrollThumb = true;

  PdfTextSearcher? _textSearcher;

  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;
    Get.back();
    return true;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
    _viewerController.addListener(_onControllerUpdate);
    unawaited(_loadSavedPage());
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    unawaited(_persistPage(_currentPageNotifier.value));
    _textSearcher?.dispose();
    _textSearcher = null;
    _viewerController.removeListener(_onControllerUpdate);
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _currentPageNotifier.dispose();
    _navScrubNotifier.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    final n = _viewerController.pageNumber;
    if (n == null || n == _currentPageNotifier.value) return;
    _currentPageNotifier.value = n;
    _scheduleSave();
  }

  Future<void> _loadSavedPage() async {
    var page1 = 1;
    var usedServer = false;
    final fh = widget.fileHash?.trim();
    if (fh != null && fh.isNotEmpty) {
      final progress = await BookComicReaderApiService.instance.getProgress(
        fileHash: fh,
        showLoading: false,
      );
      if (progress != null) {
        usedServer = true;
        final raw = progress['current_page'];
        final cp0 = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
        if (cp0 >= 0) {
          page1 = cp0 + 1;
        }
      }
    }
    if (!usedServer) {
      final key = widget.progressStorageKey?.trim();
      if (key != null && key.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final id = _prefsIdForKey(key);
        final saved = prefs.getInt('$_prefPrefix$id');
        if (saved != null && saved >= 1) {
          page1 = saved;
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final showProgress = prefs.getBool(_kShowProgressKey) ?? true;
    final showThumb = prefs.getBool(_kShowScrollThumbKey) ?? true;

    if (!mounted) return;
    _currentPageNotifier.value = page1;
    setState(() {
      _restoredPage = page1;
      _showProgressBar = showProgress;
      _showScrollThumb = showThumb;
      _prefsReady = true;
    });
  }

  String _prefsIdForKey(String key) =>
      md5.convert(utf8.encode(key.trim())).toString();

  Future<void> _persistPage(int page1Based) async {
    if (page1Based < 1) return;

    final key = widget.progressStorageKey?.trim();
    if (key != null && key.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('$_prefPrefix${_prefsIdForKey(key)}', page1Based);
    }

    final fh = widget.fileHash?.trim();
    if (fh == null || fh.isEmpty) return;

    final total = _totalPages > 0
        ? _totalPages
        : (_viewerController.isReady ? _viewerController.pageCount : 0);
    if (total <= 0) return;

    final cp0 = page1Based - 1;
    if (cp0 == _lastPersistedServer0 && total == _lastPersistedTotal) {
      return;
    }
    _lastPersistedServer0 = cp0;
    _lastPersistedTotal = total;

    await BookComicReaderApiService.instance.upsertProgress(
      fileHash: fh,
      currentPage: cp0,
      totalPage: total,
      showLoading: false,
    );
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(_persistPage(_currentPageNotifier.value));
    });
  }

  int? _calcInitialPageNumber(PdfDocument doc, PdfViewerController _) {
    return _restoredPage.clamp(1, doc.pages.length);
  }

  void _onPageChanged(int? pageNumber) {
    if (pageNumber == null) return;
    if (pageNumber == _currentPageNotifier.value) return;
    _currentPageNotifier.value = pageNumber;
    _scheduleSave();
  }

  void _onDocumentChanged(PdfDocument? doc) {
    if (doc == null) {
      _textSearcher?.dispose();
      _textSearcher = null;
      setState(() {
        _totalPages = 0;
        _outline = const [];
      });
      return;
    }
    setState(() => _totalPages = doc.pages.length);
    unawaited(_loadOutline(doc));
  }

  Future<void> _loadOutline(PdfDocument doc) async {
    try {
      final nodes = await doc.loadOutline();
      if (!mounted) return;
      setState(() => _outline = nodes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _outline = const []);
    }
  }

  void _onPdfLinkTap(PdfLink link) {
    if (!_viewerController.isReady) return;
    if (link.dest != null) {
      unawaited(_viewerController.goToDest(link.dest!));
      return;
    }
    final u = link.url;
    if (u != null) {
      unawaited(launchUrl(u, mode: LaunchMode.externalApplication));
    }
  }

  Widget _buildLoadingBanner(
    BuildContext context,
    int bytesDownloaded,
    int? totalBytes,
  ) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (totalBytes != null && totalBytes > 0) ...[
            const SizedBox(height: 12),
            Text(
              '${(100 * bytesDownloaded / totalBytes).clamp(0, 100).toStringAsFixed(0)}%',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }

  void _openSidePanel(int tabIndex) {
    setState(() => _drawerInitialTab = tabIndex.clamp(0, 2));
    _scaffoldKey.currentState?.openEndDrawer();
  }

  void _onViewerReady(PdfDocument _, PdfViewerController ctrl) {
    assert(identical(ctrl, _viewerController));
    _textSearcher?.dispose();
    _textSearcher = PdfTextSearcher(_viewerController);
  }

  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              top: 8,
            ),
            child: StatefulBuilder(
              builder: (ctx, setModalState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        'pdf_viewer_settings'.tr,
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(child: Text('pdf_viewer_show_progress'.tr)),
                        Switch.adaptive(
                          value: _showProgressBar,
                          onChanged: (v) async {
                            setState(() => _showProgressBar = v);
                            setModalState(() {});
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool(_kShowProgressKey, v);
                          },
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text('pdf_viewer_show_scroll_thumb'.tr),
                        ),
                        Switch.adaptive(
                          value: _showScrollThumb,
                          onChanged: (v) async {
                            setState(() {
                              _showScrollThumb = v;
                            });
                            setModalState(() {});
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool(_kShowScrollThumbKey, v);
                          },
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _jumpOutline(PdfDest? dest) {
    if (dest == null || !_viewerController.isReady) return;
    _scaffoldKey.currentState?.closeEndDrawer();
    unawaited(_viewerController.goToDest(dest));
  }

  void _jumpToPageFromDrawer(int page1) {
    if (!_viewerController.isReady || page1 < 1) return;
    final t = _totalPages > 0
        ? _totalPages
        : (_viewerController.isReady ? _viewerController.pageCount : 0);
    final p = t > 0 ? page1.clamp(1, t) : page1;
    _scaffoldKey.currentState?.closeEndDrawer();
    _currentPageNotifier.value = p;
    unawaited(_viewerController.goToPage(pageNumber: p));
    _scheduleSave();
  }

  Widget _buildPdfViewer(ThemeData theme) {
    final params = PdfViewerParams(
      calculateInitialPageNumber: _calcInitialPageNumber,
      linkHandlerParams: PdfLinkHandlerParams(
        onLinkTap: _onPdfLinkTap,
        linkColor: theme.colorScheme.primary.withValues(alpha: 0.12),
      ),
      loadingBannerBuilder: _buildLoadingBanner,
      onDocumentChanged: _onDocumentChanged,
      onPageChanged: _onPageChanged,
      onViewerReady: _onViewerReady,
      matchTextColor: theme.colorScheme.primary.withValues(alpha: 0.28),
      activeMatchTextColor: theme.colorScheme.tertiary.withValues(alpha: 0.5),
      pagePaintCallbacks: [
        (canvas, pageRect, page) {
          _textSearcher?.pageTextMatchPaintCallback(canvas, pageRect, page);
        },
      ],
      viewerOverlayBuilder: (ctx, viewSize, _) {
        if (!_showScrollThumb) return <Widget>[];
        return [
          PdfViewerScrollThumb(
            controller: _viewerController,
            thumbSize: const Size(12, 40),
            margin: 2,
          ),
        ];
      },
    );

    final path = widget.localFilePath?.trim();
    if (path != null && path.isNotEmpty) {
      return PdfViewer.file(
        path,
        controller: _viewerController,
        params: params,
      );
    }
    final bytes = widget.pdfBytes;
    if (bytes != null) {
      return PdfViewer.data(
        bytes,
        sourceName: widget.title,
        controller: _viewerController,
        params: params,
      );
    }
    return PdfViewer.uri(
      widget.pdfUri!,
      controller: _viewerController,
      params: params,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_prefsReady) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_outlined),
            onPressed: () => Get.back(),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);
    final total = _totalPages;

    final drawerW = (MediaQuery.sizeOf(context).width * 0.42)
        .clamp(280.0, 440.0)
        .toDouble();

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: Drawer(
        width: drawerW,
        child: _PdfReaderSidePanel(
          initialTab: _drawerInitialTab,
          searcher: _textSearcher,
          outline: _outline,
          totalPages: total,
          onJumpOutline: _jumpOutline,
          onJumpPage: _jumpToPageFromDrawer,
        ),
      ),
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_outlined),
          onPressed: () => Get.back(),
        ),
        bottom: (!_showProgressBar || total <= 0)
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(16),
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 2,
                  ),
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _currentPageNotifier,
                      _navScrubNotifier,
                    ]),
                    builder: (context, _) {
                      final current = _currentPageNotifier.value.clamp(
                        1,
                        total,
                      );
                      final scrub = _navScrubNotifier.value;
                      return Row(
                        children: [
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2,
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 0,
                                ),
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                                tickMarkShape: const RoundSliderTickMarkShape(
                                  tickMarkRadius: 0,
                                ),
                                showValueIndicator: ShowValueIndicator.never,
                              ),
                              child: SizedBox(
                                height: 14,
                                child: Slider(
                                  value: (scrub ?? current.toDouble())
                                      .clamp(1, total)
                                      .toDouble(),
                                  min: 1,
                                  max: total.toDouble(),
                                  divisions: (total - 1).clamp(1, 500),
                                  onChanged: (v) {
                                    _navScrubNotifier.value = v;
                                  },
                                  onChangeEnd: (v) {
                                    final p = v.round().clamp(1, total);
                                    _navScrubNotifier.value = null;
                                    _currentPageNotifier.value = p;
                                    unawaited(
                                      _viewerController.goToPage(pageNumber: p),
                                    );
                                    _scheduleSave();
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${(scrub?.round() ?? current).clamp(1, total)}/$total',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
        actions: [
          IconButton(
            tooltip: 'search'.tr,
            icon: const Icon(Icons.search_outlined),
            onPressed: () => _openSidePanel(0),
          ),
          IconButton(
            tooltip: 'pdf_viewer_outline'.tr,
            icon: const Icon(Icons.list_alt_outlined),
            onPressed: () => _openSidePanel(1),
          ),
          IconButton(
            tooltip: 'pdf_viewer_settings'.tr,
            icon: const Icon(Icons.tune_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: _buildPdfViewer(theme),
    );
  }
}

/// 与官方示例类似：匹配上下文 + 命中词黄底高亮。
class _PdfMatchSnippet {
  _PdfMatchSnippet._();

  static const int _ctxBefore = 44;
  static const int _ctxAfter = 72;

  static InlineSpan buildSpan(PdfPageTextRange m, ThemeData theme) {
    final full = m.pageText.fullText;
    final base = theme.textTheme.bodySmall;
    if (full.isEmpty) {
      return TextSpan(text: m.text, style: base);
    }
    final lo = (m.start - _ctxBefore).clamp(0, full.length);
    final hi = (m.end + _ctxAfter).clamp(lo, full.length);
    final seg = full.substring(lo, hi);
    final r0 = (m.start - lo).clamp(0, seg.length);
    final r1 = (m.end - lo).clamp(0, seg.length);
    final hl = base?.copyWith(
      backgroundColor: const Color(0xFFFFF59D),
      color: Colors.black,
    );
    final spans = <InlineSpan>[];
    if (lo > 0) {
      spans.add(TextSpan(text: '…', style: base));
    }
    if (r0 > 0) {
      spans.add(TextSpan(text: seg.substring(0, r0), style: base));
    }
    if (r1 > r0) {
      spans.add(TextSpan(text: seg.substring(r0, r1), style: hl));
    }
    if (r1 < seg.length) {
      spans.add(TextSpan(text: seg.substring(r1), style: base));
    }
    if (hi < full.length) {
      spans.add(TextSpan(text: '…', style: base));
    }
    return TextSpan(style: base, children: spans);
  }
}

class _PdfReaderSidePanel extends StatefulWidget {
  const _PdfReaderSidePanel({
    required this.initialTab,
    required this.searcher,
    required this.outline,
    required this.totalPages,
    required this.onJumpOutline,
    required this.onJumpPage,
  });

  final int initialTab;
  final PdfTextSearcher? searcher;
  final List<PdfOutlineNode> outline;
  final int totalPages;
  final void Function(PdfDest? dest) onJumpOutline;
  final void Function(int page1Based) onJumpPage;

  @override
  State<_PdfReaderSidePanel> createState() => _PdfReaderSidePanelState();
}

class _PdfReaderSidePanelState extends State<_PdfReaderSidePanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final TextEditingController _query;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
    final p = widget.searcher?.pattern;
    final initial = p is String ? p : '';
    _query = TextEditingController(text: initial);
    _query.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = widget.searcher;
      if (s != null && initial.isNotEmpty) {
        s.startTextSearch(
          initial,
          caseInsensitive: true,
          searchImmediately: true,
        );
      }
    });
  }

  @override
  void didUpdateWidget(covariant _PdfReaderSidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab &&
        widget.initialTab >= 0 &&
        widget.initialTab < _tabs.length) {
      _tabs.animateTo(widget.initialTab.clamp(0, 2));
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _query.dispose();
    super.dispose();
  }

  String _searchStatus(PdfTextSearcher s) {
    final q = _query.text.trim();
    if (q.isEmpty) return '';
    if (s.isSearching) {
      final buf = StringBuffer('pdf_viewer_search_in_progress'.tr);
      final t = s.totalPageCount;
      final p = s.searchingPageNumber;
      if (t != null && t > 0 && p != null) {
        buf.write(' (${p.clamp(1, t)}/$t)');
      }
      return buf.toString();
    }
    if (s.matches.isEmpty) return 'pdf_viewer_search_no_matches'.tr;
    final ci = s.currentIndex;
    final n = s.matches.length;
    if (ci == null) return '$n';
    return '${ci + 1} / $n';
  }

  Widget _buildSearchTab(ThemeData theme, PdfTextSearcher s) {
    final q = _query.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: _query,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'pdf_viewer_search_hint'.tr,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (v) {
                    s.startTextSearch(v, caseInsensitive: true);
                  },
                ),
              ),
              ListenableBuilder(
                listenable: s,
                builder: (context, _) {
                  final status = q.isEmpty ? '' : _searchStatus(s);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 52),
                      child: Text(
                        status,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                },
              ),
              ListenableBuilder(
                listenable: s,
                builder: (context, _) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'pdf_viewer_search_next'.tr,
                        onPressed: s.matches.isEmpty
                            ? null
                            : () => unawaited(s.goToNextMatch()),
                        icon: const Icon(Icons.keyboard_arrow_down_outlined),
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        tooltip: 'pdf_viewer_search_prev'.tr,
                        onPressed: s.matches.isEmpty
                            ? null
                            : () => unawaited(s.goToPrevMatch()),
                        icon: const Icon(Icons.keyboard_arrow_up_outlined),
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        tooltip: 'cancel'.tr,
                        onPressed: _query.text.isEmpty
                            ? null
                            : () {
                                _query.clear();
                                s.resetTextSearch();
                                setState(() {});
                              },
                        icon: const Icon(Icons.close_outlined),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: s,
            builder: (context, _) {
              if (q.isEmpty) {
                return Center(
                  child: Text(
                    'pdf_viewer_search_hint'.tr,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              if (s.isSearching && s.matches.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (s.matches.isEmpty) {
                return Center(
                  child: Text(
                    'pdf_viewer_search_no_matches'.tr,
                    style: theme.textTheme.bodyMedium,
                  ),
                );
              }
              final byPage = <int, List<int>>{};
              for (var i = 0; i < s.matches.length; i++) {
                final pn = s.matches[i].pageNumber;
                byPage.putIfAbsent(pn, () => []).add(i);
              }
              final pageOrder = byPage.keys.toList()..sort();
              final ci = s.currentIndex;
              final tiles = <Widget>[];
              for (final p in pageOrder) {
                tiles.add(
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
                    child: Text(
                      'pdf_viewer_search_page_label'.trParams({'page': '$p'}),
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                );
                for (final mi in byPage[p]!) {
                  final m = s.matches[mi];
                  final selected = ci == mi;
                  tiles.add(
                    Material(
                      color: selected
                          ? theme.colorScheme.primaryContainer.withValues(
                              alpha: 0.42,
                            )
                          : null,
                      child: InkWell(
                        onTap: () => unawaited(s.goToMatchOfIndex(mi)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Text.rich(
                            _PdfMatchSnippet.buildSpan(m, theme),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  );
                }
              }
              return ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: tiles,
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.searcher;

    if (s == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'pdf_viewer_search_waiting'.tr,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
        ),
      );
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tabs,
            tabs: [
              Tab(text: 'search'.tr),
              Tab(text: 'pdf_viewer_tab_outline'.tr),
              Tab(text: 'pdf_viewer_tab_pages'.tr),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildSearchTab(theme, s),
                widget.outline.isEmpty
                    ? Center(child: Text('pdf_viewer_no_outline'.tr))
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: widget.outline
                            .map(
                              (n) => _OutlineEntry(
                                node: n,
                                depth: 0,
                                onJump: widget.onJumpOutline,
                              ),
                            )
                            .toList(),
                      ),
                widget.totalPages <= 0
                    ? Center(child: Text('pdf_viewer_search_waiting'.tr))
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: widget.totalPages,
                        itemBuilder: (context, i) {
                          final p = i + 1;
                          return ListTile(
                            dense: true,
                            title: Text(
                              'pdf_viewer_search_page_label'.trParams({
                                'page': '$p',
                              }),
                            ),
                            onTap: () => widget.onJumpPage(p),
                          );
                        },
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OutlineEntry extends StatelessWidget {
  const _OutlineEntry({
    required this.node,
    required this.depth,
    required this.onJump,
  });

  final PdfOutlineNode node;
  final int depth;
  final void Function(PdfDest? dest) onJump;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasChildren = node.children.isNotEmpty;
    final dest = node.dest;

    if (!hasChildren) {
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.only(left: 16 + depth * 12.0, right: 8),
        title: Text(
          node.title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: dest != null
                ? theme.colorScheme.primary
                : theme.textTheme.bodyMedium?.color,
          ),
        ),
        enabled: dest != null,
        onTap: dest == null ? null : () => onJump(dest),
      );
    }

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.only(left: 8 + depth * 12.0, right: 8),
        title: Text(
          node.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
        children: [
          if (dest != null)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.only(
                left: 24 + depth * 12.0,
                right: 8,
              ),
              leading: Icon(
                Icons.bookmark_outline_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              title: Text(
                'pdf_viewer_outline_jump_here'.tr,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              onTap: () => onJump(dest),
            ),
          ...node.children.map(
            (c) => _OutlineEntry(node: c, depth: depth + 1, onJump: onJump),
          ),
        ],
      ),
    );
  }
}
