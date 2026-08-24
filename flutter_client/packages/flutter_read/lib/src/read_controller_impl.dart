import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:synchronized/synchronized.dart';

import 'read_analysis.dart';
import 'read_controller.dart';
import 'read_data.dart';

class ReadControllerImpl implements ReadController {
  // English: Associates with the reader
  // 中文: 关联上阅读器
  final ValueNotifier<bool> isAttach = ValueNotifier(false);

  // English: Current progress
  // 中文: 当前进度
  BookProgress currentProgress_ = BookProgress.zero;

  // English: Disable left swipe
  // 中文: 禁止左滑
  final ValueNotifier<bool> disableLeft = ValueNotifier(true);

  // English: Disable right swipe
  // 中文: 禁止右滑
  final ValueNotifier<bool> disableRight = ValueNotifier(true);

  // English: Call menu on upward swipe
  // 中文: 上划调用菜单
  final bool enableVerticalDrag;

  // English: Tap to page
  // 中文: 点击翻页
  final bool enableTapPage;

  final Widget? loadingWidget;

  BookSource? bookSource_;

  // English: Summary page
  // 中文: 简介页
  Widget? summaryWidget;

  // English: Rendering style
  // 中文: 绘制样式
  ReadStyle readStyle_ = ReadStyle(
    textStyle: const TextStyle(
        color: Color(0xFF212832), fontSize: 20, fontWeight: FontWeight.w400),
    titleTextStyle: const TextStyle(
        color: Color(0xFF212832), fontSize: 26, fontWeight: FontWeight.w600),
    textAlign: TextAlign.justify,
    titleTextAlign: TextAlign.center,
    bgColor: const Color(0xFFF5F5DC),
    sentenceSpacing: 16,
    lineSpacing: 8,
    wordSpacing: 2,
    padding: const EdgeInsets.all(20),
  );

  // English: Page index change notification
  // 中文: 页面下标改变通知
  final StreamController<BookProgress> onPageIndexChangedController =
      StreamController<BookProgress>.broadcast();

  @override
  Stream<BookProgress> get onPageIndexChanged =>
      onPageIndexChangedController.stream;

  // English: Notification when swiping to the edge, true indicates the left edge, false indicates the right edge
  // 中文: 滑动到边缘通知,true是左边缘，false是右边缘
  EdgeCallback? onEdgeCallback_;

  // English: Callback when loading the page, used to insert additional pages
  // 中文: 页面加载时的回调，用来插入额外的页面
  ReadDataListCallback? onBookDataListCallback_;

  //  ---------- inner start -------------
  // English: Internal variables, for internal use only
  // 中文: 内部变量，外部勿用
  static const int initialPage = 100000000;
  final Map<int, List<PaintData>> bookPageList = SplayTreeMap();
  final Map<int, BookSource> _chapterSourceList = SplayTreeMap();
  final Map<int, List<BookSentence>> chapterSentences = SplayTreeMap();

  // English: Indicates if the book has been fully loaded
  // 中文: 书本加载完成
  bool _isLoadCompleter = false;

  // English: Size of the reader container
  // 中文: 阅读器容器大小
  Size contentSize = Size.zero;

  // English: Current page offset
  // 中文: 当前页面偏移量
  int firstIndex = initialPage;

  // English: Data lock
  // 中文: 数据锁
  final Lock _beforeChapterLock = Lock();
  final Lock _afterChapterLock = Lock();

  // English: Text size
  // 中文: 文字大小
  Size zhWordSize = Size.zero;
  Size zhTitleWordSize = Size.zero;

  // English: Jump to the specified page
  // 中文: 跳转到指定页
  IndexCallback? jumpToPageCallback;

  // English: Refresh the page
  // 中文: 刷新页面
  VoidCallback? refreshCallback;

  // English: Reset the page
  // 中文: 重置页面
  VoidCallback? resetCallback;

  // English: Current page
  // 中文: 当前页面
  int Function()? currentPageIndexCallback;

  // English: Page scrolling
  // 中文: 页面跳转
  IndexCallback? scrollToPageCallback;

  //  ---------- inner end -------------

  bool _webReflowScheduled = false;
  int _webReflowStartedAtMs = 0;

  ReadControllerImpl({
    this.enableVerticalDrag = false,
    this.enableTapPage = true,
    this.onEdgeCallback_,
    this.loadingWidget,
    this.summaryWidget,
    ReadStyle? readStyle,
  }) {
    if (readStyle != null) {
      readStyle_ = readStyle;
    }
    isAttach.addListener(() {
      if (isAttach.value) {
        wordWidthMap.clear();
        _initWord();
      }
    });
    onPageIndexChangedController.stream.listen((event) {
      currentProgress_ = event;
    });
  }

  @override
  Future<int> startReadBook(BookSource source, {ChapterData? chapter}) async {
    if (!isAttach.value) {
      final Completer<int> isFinish = Completer<int>();
      isAttach.addListener(() async {
        if (isAttach.value && !isFinish.isCompleted) {
          int result = await startReadBook(source, chapter: chapter);
          isFinish.complete(result);
        }
      });
      return isFinish.future;
    }
    if (chapter != null && bookPageList.containsKey(chapter.chapterIndex)) {
      _jump(chapter);
      return -1;
    }
    final Map<String, List<BookSentence>> sentences =
        await compute((BookSource s) => s.getData(), source);
    if (sentences.isEmpty) {
      return -2;
    }
    _webReflowScheduled = false;
    _webReflowStartedAtMs = DateTime.now().millisecondsSinceEpoch;
    bookPageList.clear();
    firstIndex = initialPage;
    _isLoadCompleter = false;
    int i = 0;
    for (String title in sentences.keys) {
      List<BookSentence> content = sentences[title] ?? List.empty();
      chapterSentences[i] = content;
      addChapter(ChapterSource(content, title), i);
      i++;
    }
    chapter ??= ChapterData();
    return _startRead(
        _chapterSourceList[chapter.chapterIndex] ?? source, chapter);
  }

  @override
  Future<int> reopen(BookSource source, {ChapterData? chapter}) async {
    bookPageList.clear();
    chapterSentences.clear();
    _chapterSourceList.clear();
    firstIndex = initialPage;
    _isLoadCompleter = false;
    return startReadBook(source, chapter: chapter);
  }

  @override
  Future<int> startReadChapter(BookSource source, ChapterData chapter) async {
    if (!isAttach.value) {
      final Completer<int> isFinish = Completer<int>();
      isAttach.addListener(() async {
        if (isAttach.value && !isFinish.isCompleted) {
          int result = await startReadChapter(source, chapter);
          isFinish.complete(result);
        }
      });
      return isFinish.future;
    }
    int chapterIndex = chapter.chapterIndex;
    _chapterSourceList[chapterIndex] = source;
    if (bookPageList.containsKey(chapterIndex)) {
      _jump(chapter);
      return -1;
    }
    final List<BookSentence>? sentences = (await compute(
        (BookSource s) => s.getData(), source))[source.getTitle()];
    if (sentences?.isEmpty ?? true) {
      return -2;
    }
    _webReflowScheduled = false;
    _webReflowStartedAtMs = DateTime.now().millisecondsSinceEpoch;
    bookPageList.clear();
    firstIndex = initialPage;
    _isLoadCompleter = false;
    chapterSentences[chapterIndex] = sentences!;
    return _startRead(source, chapter);
  }

  Future<int> _startRead(BookSource source, ChapterData chapter) async {
    bookSource_ = source;
    int chapterIndex = chapter.chapterIndex;
    List<PaintData> bookDataList = List.empty(growable: true);
    bookPageList[chapterIndex] = bookDataList;
    List<PaintData> list = await addBookBeforeData(this, source.getTitle(),
        chapterIndex, chapter.sentenceIndex, chapter.wordIndex);
    bookDataList.addAll(list.reversed);
    _firstIndexDec(chapter, bookDataList, chapterIndex);
    list = await addBookAfterData(this, source.getTitle(), chapterIndex,
        chapter.sentenceIndex, chapter.wordIndex);
    bookDataList.addAll(list);
    if (chapter.colophon) {
      _firstIndexDec(chapter, list, chapterIndex);
    }
    onBookDataListCallback_?.call(
        chapterIndex, source.getTitle(), bookDataList);
    _addSummaryWidget(source, chapter.summary, chapterIndex, bookDataList);
    if (list.isNotEmpty) {
      preDraw();
    }
    _isLoadCompleter = true;
    resetCallback?.call();
    refreshCallback?.call();
    _scheduleWebReflowIfNeeded();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      BookSource? cache = _chapterSourceList[chapterIndex - 1];
      if (cache != null) {
        await addChapter(cache, chapterIndex - 1);
      }
      cache = _chapterSourceList[chapterIndex + 1];
      if (cache != null) {
        await addChapter(cache, chapterIndex + 1);
      }
    });
    return 0;
  }

  void _scheduleWebReflowIfNeeded() {
    if (!kIsWeb) return;
    if (_webReflowScheduled) return;
    _webReflowScheduled = true;
    final startedAt = _webReflowStartedAtMs;
    final baseProgress = currentProgress_;
    final delays = <int>[350, 1200];
    for (final ms in delays) {
      Future.delayed(Duration(milliseconds: ms), () async {
        if (!isAttach.value) return;
        if (startedAt <= 0 || startedAt != _webReflowStartedAtMs) return;
        final cur = currentProgress_;
        if (cur.chapterIndex != baseProgress.chapterIndex ||
            cur.pageIndex != baseProgress.pageIndex ||
            cur.sentenceIndex != baseProgress.sentenceIndex ||
            cur.wordIndex != baseProgress.wordIndex) {
          return;
        }
        wordWidthMap.clear();
        _initWord();
        await refresh();
      });
    }
  }

  @override
  Future<void> reflow() async {
    _webReflowStartedAtMs = DateTime.now().millisecondsSinceEpoch;
    wordWidthMap.clear();
    _initWord();
    await refresh();
  }

  Future<void> refresh() async {
    int chapterIndex = currentProgress_.chapterIndex;
    if (!_chapterSourceList.containsKey(chapterIndex) ||
        !chapterSentences.containsKey(chapterIndex)) {
      return;
    }
    bookPageList.clear();
    firstIndex = initialPage;
    _isLoadCompleter = false;

    BookSource source = _chapterSourceList[chapterIndex]!;
    ChapterData chapter = ChapterData(
        chapterIndex: chapterIndex,
        sentenceIndex: currentProgress_.sentenceIndex,
        wordIndex: currentProgress_.wordIndex,
        colophon: currentProgress_.interaction);
    List<PaintData> list = await addBookBeforeData(
        this,
        source.getTitle(),
        chapterIndex,
        currentProgress_.sentenceIndex,
        currentProgress_.wordIndex);
    List<PaintData> bookDataList = List.empty(growable: true);
    bookPageList[chapterIndex] = bookDataList;
    bookDataList.addAll(list.reversed);
    _firstIndexDec(chapter, bookDataList, chapterIndex);
    list = await addBookAfterData(this, source.getTitle(), chapterIndex,
        currentProgress_.sentenceIndex, currentProgress_.wordIndex);
    bookDataList.addAll(list);
    if (currentProgress_.interaction) {
      _firstIndexDec(chapter, bookDataList, chapterIndex);
    }
    onBookDataListCallback_?.call(
        chapterIndex, source.getTitle(), bookDataList);
    _addSummaryWidget(source, chapter.summary, chapterIndex, bookDataList);
    if (list.isNotEmpty) {
      preDraw();
    }
    _isLoadCompleter = true;
    resetCallback?.call();
    refreshCallback?.call();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      BookSource? cache = _chapterSourceList[chapterIndex - 1];
      if (cache != null) {
        await addChapter(cache, chapterIndex - 1);
      }
      cache = _chapterSourceList[chapterIndex + 1];
      if (cache != null) {
        await addChapter(cache, chapterIndex + 1);
      }
    });
  }

  @override
  BookSource? get currentBookSource => bookSource_;

  @override
  BookProgress get currentProgress => currentProgress_;

  @override
  ReadStyle get readStyle => readStyle_;

  @override
  set readStyle(ReadStyle style) {
    readStyle_ = style;
    if (isAttach.value) {
      _initWord();
      refresh();
    } else {
      isAttach.addListener(() {
        if (isAttach.value) {
          _initWord();
          refresh();
        }
      });
    }
  }

  @override
  set onEdgeCallback(EdgeCallback? callback) => onEdgeCallback_ = callback;

  @override
  set onBookDataListCallback(ReadDataListCallback callback) =>
      onBookDataListCallback_ = callback;

  void _jump(ChapterData chapter) {
    int chapterIndex = chapter.chapterIndex;
    List<PaintData> bookList = bookPageList[chapterIndex]!;
    int insertIndex = findChapterInsertIndex(chapterIndex) + firstIndex;
    int pageIndex = findChapterPageIndex(chapter, bookList);
    int summaryIndex = 0;
    if (bookList.isNotEmpty &&
        summaryWidget != null &&
        bookList.first.widget == summaryWidget) {
      summaryIndex++;
    }
    int interactionIndex = 0;
    if (chapter.colophon) {
      interactionIndex = bookList.length - 1;
    }
    jumpToPageCallback
        ?.call(insertIndex + pageIndex + summaryIndex + interactionIndex);
  }

  Future<void> edge(int index, PaintData bookData, bool pre) async {
    if (!pre) {
      disableLeft.value = index <= firstIndex;
      disableRight.value = index >= firstIndex + pageTotal() - 1;
    }
    BookPage? bookPage = bookData.bookPage;
    List<PaintData> bookDataList = bookPageList[bookData.chapterIndex]!;
    if (bookPage?.isRepair ?? false) {
      bookPage!.isRepair = false;
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
        List<int> insertIndex = findChapterIndex(index);
        bookDataList.removeRange(insertIndex[1] + 1, bookDataList.length);
        BookLine bookLine = bookPage.lines.last;
        List<PaintData> list = await addBookAfterData(this, bookData.title,
            bookData.chapterIndex, bookLine.sentence.index, bookLine.endIndex);
        bookDataList.addAll(list);
        onBookDataListCallback_?.call(
            bookData.chapterIndex, bookData.title, bookDataList);
        preDraw();
        disableRight.value = index >= firstIndex + pageTotal() - 1;
      });
    } else {
      Future.delayed(Duration.zero, () {
        preDraw();
      });
    }
  }

  // Add summary page widget
  // 添加简介页Widget
  @override
  void setSummaryWidget(Widget widget) {
    summaryWidget = widget;
  }

  @override
  int getChapterNum() {
    return _chapterSourceList.length;
  }

  @override
  BookSource? getSourceFromIndex(int chapterIndex) =>
      _chapterSourceList[chapterIndex];

  @override
  List<BookSentence>? getSentenceFromIndex(int chapterIndex) =>
      chapterSentences[chapterIndex];

  void _addSummaryWidget(BookSource source, bool summary, int chapterIndex,
      List<PaintData> bookDataList) {
    if (chapterIndex == 0 &&
        summaryWidget != null &&
        (bookDataList.isEmpty || bookDataList.first.widget != summaryWidget)) {
      bookDataList.insert(
        0,
        PaintData(chapterIndex, source.getTitle(), widget: summaryWidget),
      );
      if (!summary) {
        firstIndex--;
      }
    }
  }

  @override
  Future<void> addChapter(BookSource source, int chapterIndex) async {
    _chapterSourceList[chapterIndex] = source;
    if (!isAttach.value || !_isLoadCompleter) {
      return;
    }
    if (chapterIndex + 1 == currentProgress_.chapterIndex) {
      await addBeforeChapter(chapterIndex);
      refreshCallback?.call();
    } else if (chapterIndex - 1 == currentProgress_.chapterIndex) {
      await addAfterChapter(chapterIndex);
      refreshCallback?.call();
    }
    int? currentPageIndex = currentPageIndexCallback?.call();
    if (currentPageIndex != null) {
      disableLeft.value = currentPageIndex <= firstIndex;
      disableRight.value = currentPageIndex >= firstIndex + pageTotal() - 1;
    }
  }

  Future<void> addBeforeChapter(int chapterIndex) async {
    if (!_chapterSourceList.containsKey(chapterIndex) ||
        _beforeChapterLock.inLock) {
      return;
    }
    if (bookPageList.containsKey(chapterIndex)) {
      return;
    }
    return _beforeChapterLock.synchronized(() async {
      BookSource source = _chapterSourceList[chapterIndex]!;
      final List<BookSentence>? sentences = (await compute(
          (BookSource s) => s.getData(), source))[source.getTitle()];
      if (sentences?.isEmpty ?? true) {
        return;
      }
      chapterSentences[chapterIndex] = sentences!;
      String title = source.getTitle();
      List<PaintData> list =
          await addBookAfterData(this, title, chapterIndex, 0, 0);
      List<PaintData> bookDataList = List.empty(growable: true);
      bookPageList[chapterIndex] = bookDataList;
      bookDataList.addAll(list);
      onBookDataListCallback_?.call(chapterIndex, title, bookDataList);
      ChapterData chapter = ChapterData(chapterIndex: chapterIndex);
      _firstIndexDec(chapter, bookDataList, chapterIndex);
      _addSummaryWidget(source, chapter.summary, chapterIndex, bookDataList);
      preDraw();
    });
  }

  Future<void> addAfterChapter(int chapterIndex) async {
    if (!_chapterSourceList.containsKey(chapterIndex) ||
        _afterChapterLock.inLock) {
      return;
    }
    if (bookPageList.containsKey(chapterIndex)) {
      return;
    }
    return _afterChapterLock.synchronized(() async {
      BookSource source = _chapterSourceList[chapterIndex]!;
      final List<BookSentence>? sentences = (await compute(
          (BookSource s) => s.getData(), source))[source.getTitle()];
      if (sentences?.isEmpty ?? true) {
        return;
      }
      chapterSentences[chapterIndex] = sentences!;
      String title = source.getTitle();
      List<PaintData> list =
          await addBookAfterData(this, title, chapterIndex, 0, 0);
      List<PaintData> bookDataList = List.empty(growable: true);
      bookPageList[chapterIndex] = bookDataList;
      bookDataList.addAll(list);
      onBookDataListCallback_?.call(chapterIndex, title, bookDataList);
      preDraw();
    });
  }

  final List<int> _cacheList = List.empty(growable: true);

  Future<void> preDraw() async {
    int? index = currentPageIndexCallback?.call();
    if (index == null) {
      return;
    }
    List<int> last = List.of(_cacheList, growable: false);
    List<int> current = List.empty(growable: true);
    int range = 2;
    for (int i = index - range; i <= index + range; i++) {
      current.add(i);
    }
    _cacheList.clear();
    _cacheList.addAll(current);
    List<int> removeList =
        last.where((item) => !current.contains(item)).toList();
    for (int key in removeList) {
      List<int> chapterIndexDiff = findChapterIndex(key);
      PaintData? data = bookPageList[chapterIndexDiff[0]]?[chapterIndexDiff[1]];
      data?.picture.value = null;
    }
    for (int key in current) {
      List<int> chapterIndexDiff = findChapterIndex(key);
      PaintData? data = bookPageList[chapterIndexDiff[0]]?[chapterIndexDiff[1]];
      if (data == null || data.bookPage == null || data.picture.value != null) {
        continue;
      }
      drawTextOnCanvas(this, data.bookPage!).then((value) {
        data.picture.value = value;
      });
    }
  }

  void _initWord() {
    zhWordSize = _wordSize("龘", readStyle_.textStyle);
    zhTitleWordSize = _wordSize("龘", readStyle_.titleTextStyle);
    _prewarmAscii(readStyle_.textStyle);
    _prewarmAscii(readStyle_.titleTextStyle);
  }

  Size _wordSize(String word, TextStyle textStyle) {
    double contentWidth =
        contentSize.width - readStyle_.padding.left - readStyle_.padding.right;
    TextPainter textPaint = _measureText(textStyle, word);
    int maxLineWordNum = (contentWidth + readStyle_.wordSpacing) ~/
        (textPaint.width + readStyle_.wordSpacing);
    double wordWidth = (contentWidth + readStyle_.wordSpacing) / maxLineWordNum;
    return Size(wordWidth, textPaint.height);
  }

  TextPainter _measureText(TextStyle textStyle, String word) {
    final textPainter = TextPainter(
      text: TextSpan(text: word, style: textStyle),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    return textPainter;
  }

  void _prewarmAscii(TextStyle style) {
    final fontSize = style.fontSize;
    final fontWeight = style.fontWeight;
    final fontFamily = style.fontFamily;
    for (int code = 32; code <= 126; code++) {
      final ch = String.fromCharCode(code);
      final key = "$ch@${fontSize}@${fontWeight}@${fontFamily}";
      if (!wordWidthMap.containsKey(key)) {
        final tp = _measureText(style, ch);
        wordWidthMap[key] = tp.width;
      }
    }
  }

  int findPageIndex(int index) {
    int num = 0;
    for (final key in bookPageList.keys) {
      List<PaintData> bookList = bookPageList[key]!;
      if (bookList.isNotEmpty) {
        int insertIndex = findChapterInsertIndex(bookList.first.chapterIndex);
        int diff = index - insertIndex;
        if (diff > 0 && diff <= bookList.length) {
          return num + diff;
        }
        num += bookList.length;
      }
    }
    return num;
  }

  List<int> findChapterIndex(int index) {
    for (final key in bookPageList.keys) {
      List<PaintData> bookList = bookPageList[key]!;
      if (bookList.isNotEmpty) {
        int insertIndex =
            findChapterInsertIndex(bookList.first.chapterIndex) + firstIndex;
        int diff = index - insertIndex;
        if (diff >= 0 && diff < bookList.length) {
          return [key, diff];
        }
      }
    }
    return [-1, -1];
  }

  int findChapterPageIndex(ChapterData chapter, List<PaintData> bookDataList) {
    if (chapter.sentenceIndex > 0 || chapter.wordIndex > 0) {
      bool hasSummary = false;
      for (int i = 0; i < bookDataList.length; i++) {
        PaintData bookData = bookDataList[i];
        if (bookData.bookPage == null) {
          if (i == 0 && bookData.widget == summaryWidget) {
            hasSummary = true;
          }
          continue;
        }
        for (final bookLine in bookData.bookPage!.lines) {
          if (bookLine.sentence.index == chapter.sentenceIndex &&
              bookLine.startIndex == chapter.wordIndex) {
            return hasSummary ? i - 1 : i;
          }
        }
      }
    }
    return 0;
  }

  int findChapterInsertIndex(int chapterIndex) {
    int result = 0;
    for (final key in bookPageList.keys) {
      List<PaintData> bookList = bookPageList[key]!;
      if (bookList.isNotEmpty) {
        PaintData? page = bookList.first;
        if (page.chapterIndex >= chapterIndex) {
          return result;
        }
        result += bookList.length;
      }
    }
    return result;
  }

  int pageTotal() {
    int result = 0;
    for (final key in bookPageList.keys) {
      List<PaintData> bookList = bookPageList[key]!;
      result += bookList.length;
    }
    return result;
  }

  @override
  void previousPage() {
    scrollToPageCallback?.call(-1);
  }

  @override
  void nextPage() {
    scrollToPageCallback?.call(1);
  }

  @override
  void jumpToPage(int pageIndex) {
    jumpToPageCallback?.call(firstIndex + pageIndex);
  }

  void _firstIndexDec(
      ChapterData chapter, List<PaintData> bookDataList, int chapterIndex) {
    if (bookDataList.isNotEmpty) {
      int insertIndex = findChapterInsertIndex(chapterIndex) + firstIndex;
      int pageIndex = findChapterPageIndex(chapter, bookDataList);
      if (insertIndex + pageIndex <= initialPage) {
        firstIndex -= bookDataList.length;
      }
    }
  }
}
