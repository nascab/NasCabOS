import 'dart:async';

import 'package:flutter/material.dart';

import 'read_controller_impl.dart';
import 'read_data.dart';

abstract class ReadController {
  const ReadController();

  factory ReadController.create({
    bool enableVerticalDrag = false,
    bool enableTapPage = true,
    Widget? loadingWidget,
    Widget? summaryWidget,
    ReadStyle? readStyle,
    EdgeCallback? onEdgeCallback,
  }) {
    return ReadControllerImpl(
      enableVerticalDrag: enableVerticalDrag,
      enableTapPage: enableTapPage,
      loadingWidget: loadingWidget,
      summaryWidget: summaryWidget,
      readStyle: readStyle,
      onEdgeCallback_: onEdgeCallback,
    );
  }

  // Start reading the entire book
  // 阅读整本小说
  Future<int> startReadBook(BookSource source, {ChapterData? chapter});

  // Force reopen with new source, clearing cached pages/sentences
  // 使用新的书源强制重新打开（清空已缓存的页与句子）
  Future<int> reopen(BookSource source, {ChapterData? chapter});

  // Start reading a chapter
  // 阅读章节
  Future<int> startReadChapter(BookSource source, ChapterData chapter);

  // Preload chapters
  // 预加载章节
  Future<void> addChapter(BookSource source, int chapterIndex);

  // Reading progress callback
  // 阅读进度回调
  Stream<BookProgress> get onPageIndexChanged;

  // Current book source
  // 当前书源
  BookSource? get currentBookSource;

  // Current progress
  // 当前进度
  BookProgress get currentProgress;

  // Reading style
  // 小说样式
  ReadStyle get readStyle;

  // Set reading style
  // 设置小说样式
  set readStyle(ReadStyle style);

  // Reflow book layout (e.g. after font ready or style update)
  // 重新排版（例如 Web 字体加载完成或样式更新后）
  Future<void> reflow();

  // Callback when scrolling to the edge
  // 滑动到边缘回调
  set onEdgeCallback(EdgeCallback? callback);

  // Callback during book data loading for inserting ads, chapter reviews, etc.
  // 小说页面数据加载时回调，用于插入广告，章评页等
  set onBookDataListCallback(ReadDataListCallback callback);

  // Previous page
  // 上一页
  void previousPage();

  // Next page
  // 下一页
  void nextPage();

  // Jump to page (0-based within current reading)
  // 跳转到指定页（0 起）
  void jumpToPage(int pageIndex);

  // Set summary page
  // 设置简介页
  void setSummaryWidget(Widget widget);

  // number of chapters
  // 获取章节数
  int getChapterNum();

  // Get book source from chapter index
  // 通过章节下标获取小说源
  BookSource? getSourceFromIndex(int chapterIndex);

  // Get sentence list from chapter index
  // 通过章节下标获取句子列表
  List<BookSentence>? getSentenceFromIndex(int chapterIndex);
}

typedef EdgeCallback = Function(bool isLeft);
typedef IndexCallback = void Function(int index, {bool pre});
typedef ReadDataListCallback = void Function(
    int chapterIndex, String title, List<PaintData> bookDataList);
typedef ReadItemBuilder = Widget Function(
    BuildContext context, String title, int pageIndex, int pageTotal);

class ReadStyle {
  final TextStyle textStyle;
  final TextStyle titleTextStyle;
  final TextAlign textAlign;
  final TextAlign titleTextAlign;
  final Color bgColor;
  final double sentenceSpacing;
  final double lineSpacing;
  final double wordSpacing;
  final EdgeInsets padding;

  ReadStyle({
    required this.textStyle,
    required this.titleTextStyle,
    required this.textAlign,
    required this.titleTextAlign,
    required this.bgColor,
    required this.sentenceSpacing,
    required this.lineSpacing,
    required this.wordSpacing,
    required this.padding,
  });

  ReadStyle copyWith({
    TextStyle? textStyle,
    TextStyle? titleTextStyle,
    TextAlign? textAlign,
    TextAlign? titleTextAlign,
    Color? bgColor,
    double? sentenceSpacing,
    double? lineSpacing,
    double? wordSpacing,
    EdgeInsets? padding,
  }) {
    return ReadStyle(
        textStyle: textStyle ?? this.textStyle,
        titleTextStyle: titleTextStyle ?? this.titleTextStyle,
        textAlign: textAlign ?? this.textAlign,
        titleTextAlign: titleTextAlign ?? this.titleTextAlign,
        bgColor: bgColor ?? this.bgColor,
        sentenceSpacing: sentenceSpacing ?? this.sentenceSpacing,
        lineSpacing: lineSpacing ?? this.lineSpacing,
        wordSpacing: wordSpacing ?? this.wordSpacing,
        padding: padding ?? this.padding);
  }
}
