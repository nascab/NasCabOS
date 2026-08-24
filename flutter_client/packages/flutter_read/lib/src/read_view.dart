import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'page_view.dart';
import 'read_controller.dart';
import 'read_controller_impl.dart';
import 'read_data.dart';
import 'read_painter.dart';
import 'scroll_controller.dart';

class ReadView extends StatefulWidget {
  final ReadControllerImpl readController;
  final ReadItemBuilder? itemBuilder;
  final GestureTapCallback? onMenu;
  final VoidCallback? onScroll;

  const ReadView({
    super.key,
    required ReadController readController,
    this.itemBuilder,
    this.onMenu,
    this.onScroll,
  }) : readController = readController as ReadControllerImpl;

  @override
  State<StatefulWidget> createState() => _ReadViewState();
}

class _ReadViewState extends State<ReadView> {
  late final ReadPageController pageController = ReadPageController(
    initialPage: ReadControllerImpl.initialPage,
    onAttachCallback: (position) {
      position.disableLeft = widget.readController.disableLeft.value;
      position.disableRight = widget.readController.disableRight.value;
    },
  );
  int? animPreviousPageIndex;
  int? animNextPageIndex;
  StreamSubscription? _onPageIndexChangedSubscription;
  Timer? _refreshTimer;
  bool _clampScheduled = false;

  @override
  void initState() {
    widget.readController.currentPageIndexCallback = () {
      if (pageController.hasClients && pageController.page?.round() != null) {
        return pageController.page!.round();
      }
      return pageController.initialPage;
    };
    widget.readController.refreshCallback = () {
      _onPageIndexChanged(
          widget.readController.currentPageIndexCallback!.call());
      setState(() {});
    };
    widget.readController.resetCallback = () {
      pageController.jumpToPage(pageController.initialPage);
    };
    widget.readController.jumpToPageCallback = (int index, {bool pre = false}) {
      pageController.jumpToPage(index);
    };
    _onPageIndexChangedSubscription =
        widget.readController.onPageIndexChanged.listen((event) async {
      widget.readController.currentProgress_ = event;
      int originalFirstIndex = widget.readController.firstIndex;
      int originalLength = widget.readController.pageTotal();
      await widget.readController.addBeforeChapter(event.chapterIndex - 1);
      await widget.readController.addAfterChapter(event.chapterIndex + 1);
      widget.readController.disableLeft.value =
          event.pageIndex + originalFirstIndex <=
              widget.readController.firstIndex;
      widget.readController.disableRight.value =
          event.pageIndex + originalFirstIndex >=
              widget.readController.firstIndex +
                  widget.readController.pageTotal() -
                  1;
      if (originalFirstIndex != widget.readController.firstIndex ||
          originalLength != widget.readController.pageTotal()) {
        setState(() {});
      }
    });
    widget.readController.disableLeft.addListener(() {
      pageController.position.disableLeft =
          widget.readController.disableLeft.value;
    });
    widget.readController.disableRight.addListener(() {
      pageController.position.disableRight =
          widget.readController.disableRight.value;
    });
    widget.readController.scrollToPageCallback = (int go, {bool pre = false}) {
      if (go < 0) {
        _previousPage(false);
      } else if (go > 0) {
        _nextPage(false);
      } else {
        widget.onMenu?.call();
      }
    };
    super.initState();
  }

  void _scheduleClampToValidPage(int targetIndex) {
    if (_clampScheduled) return;
    _clampScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _clampScheduled = false;
      if (!mounted) return;
      if (!pageController.hasClients) return;
      pageController.jumpToPage(targetIndex);
    });
  }

  int? _validMinIndex() {
    final total = widget.readController.pageTotal();
    if (total <= 0) return null;
    return widget.readController.firstIndex;
  }

  int? _validMaxIndex() {
    final total = widget.readController.pageTotal();
    if (total <= 0) return null;
    return widget.readController.firstIndex + total - 1;
  }

  bool _hasPageData(int index) {
    final diff = widget.readController.findChapterIndex(index);
    if (diff[0] < 0 || diff[1] < 0) return false;
    final list = widget.readController.bookPageList[diff[0]];
    if (list == null) return false;
    return diff[1] < list.length;
  }

  @override
  void dispose() {
    _onPageIndexChangedSubscription?.cancel();
    _refreshTimer?.cancel();
    widget.readController.isAttach.value = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (widget.readController.contentSize != size &&
            !widget.readController.contentSize.isEmpty) {
          widget.readController.contentSize = size;
          if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
            widget.readController.refresh();
          } else {
            _refreshTimer?.cancel();
            _refreshTimer = Timer(const Duration(milliseconds: 100), () {
              widget.readController.refresh();
            });
          }
        } else {
          widget.readController.contentSize = size;
        }
        widget.readController.isAttach.value = true;
        Widget current = ReadPageView(
          pageController: pageController,
          itemBuilder: (BuildContext context, int index) {
            return _contentWidget(index);
          },
          onEdgeCallback: widget.readController.onEdgeCallback_,
          onScrollCallback: widget.onScroll,
          onPageIndexChanged: _onPageIndexChanged,
          onVerticalDrag:
              widget.readController.enableVerticalDrag ? widget.onMenu : null,
        );
        if (widget.readController.enableTapPage) {
          Offset tapPosition = Offset.zero;
          double tapWidth = size.width / 3;
          Rect leftTap = Rect.fromLTWH(0, 0, tapWidth, size.height);
          Rect midTap = Rect.fromLTWH(tapWidth, 0, tapWidth, size.height);
          Rect rightTap = Rect.fromLTWH(2 * tapWidth, 0, tapWidth, size.height);
          current = GestureDetector(
            onTap: () {
              if (leftTap.contains(tapPosition)) {
                _previousPage(true);
              } else if (midTap.contains(tapPosition)) {
                widget.onMenu?.call();
              } else if (rightTap.contains(tapPosition)) {
                _nextPage(true);
              }
            },
            onTapDown: (details) {
              tapPosition = details.globalPosition;
            },
            child: current,
          );
        }
        return current;
      },
    );
  }

  Widget _contentWidget(int index) {
    List<int> chapterIndexDiff = widget.readController.findChapterIndex(index);
    List<PaintData>? bookDataList =
        widget.readController.bookPageList[chapterIndexDiff[0]];
    PaintData? data = bookDataList?[chapterIndexDiff[1]];
    Widget? child;
    if (data != null) {
      if (data.widget != null) {
        child = data.widget;
      } else {
        int pageIndex = chapterIndexDiff[1];
        int pageTotal = bookDataList!.length;
        if (chapterIndexDiff[0] == 0 &&
            bookDataList.isNotEmpty &&
            widget.readController.summaryWidget != null &&
            bookDataList.first.widget == widget.readController.summaryWidget) {
          pageIndex--;
          pageTotal--;
        }
        child = Stack(
          fit: StackFit.expand,
          children: [
            ReadPaint(
              data: data,
              loadingWidget: widget.readController.loadingWidget,
            ),
            if (widget.itemBuilder != null)
              widget.itemBuilder!.call(
                context,
                (data.bookPage?.lines.first.isTitle ?? false) ? "" : data.title,
                pageIndex,
                pageTotal,
              ),
          ],
        );
      }
    } else {
      final minIndex = _validMinIndex();
      final maxIndex = _validMaxIndex();
      if (minIndex != null && maxIndex != null) {
        if (index < minIndex) {
          widget.readController.disableLeft.value = true;
          _scheduleClampToValidPage(minIndex);
        } else if (index > maxIndex) {
          widget.readController.disableRight.value = true;
          _scheduleClampToValidPage(maxIndex);
        }
      }
      child = widget.readController.loadingWidget;
    }
    return Container(
      decoration: BoxDecoration(
        color: widget.readController.readStyle_.bgColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            spreadRadius: 0.2,
            blurRadius: 10.0,
          ),
        ],
      ),
      child: child,
    );
  }

  Future<void> _previousPage(bool notify) async {
    if (animNextPageIndex != null) {
      return;
    }
    final cur = pageController.page?.round();
    final minIndex = _validMinIndex();
    final target = cur == null ? null : cur - 1;
    if (target != null && minIndex != null && target < minIndex) {
      widget.readController.disableLeft.value = true;
      if (notify) {
        widget.readController.onEdgeCallback_?.call(true);
      }
      _scheduleClampToValidPage(minIndex);
      return;
    }
    if (target != null && !_hasPageData(target)) {
      widget.readController.disableLeft.value = true;
      if (notify) {
        widget.readController.onEdgeCallback_?.call(true);
      }
      final clamp = minIndex ?? pageController.initialPage;
      _scheduleClampToValidPage(clamp);
      return;
    }
    if (widget.readController.disableLeft.value) {
      if (notify) {
        widget.readController.onEdgeCallback_?.call(true);
      }
      return;
    }
    if (animPreviousPageIndex == null) {
      widget.onScroll?.call();
      animPreviousPageIndex = pageController.page!.round() - 1;
      await pageController.animateToPage(
        animPreviousPageIndex!,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
      if (pageController.page!.round() == animPreviousPageIndex) {
        animPreviousPageIndex = null;
      }
    } else {
      pageController.jumpToPage(
        animPreviousPageIndex!,
      );
      animPreviousPageIndex = null;
      _previousPage(notify);
    }
  }

  Future<void> _nextPage(bool notify) async {
    if (animPreviousPageIndex != null) {
      return;
    }
    final cur = pageController.page?.round();
    final maxIndex = _validMaxIndex();
    final target = cur == null ? null : cur + 1;
    if (target != null && maxIndex != null && target > maxIndex) {
      widget.readController.disableRight.value = true;
      if (notify) {
        widget.readController.onEdgeCallback_?.call(false);
      }
      _scheduleClampToValidPage(maxIndex);
      return;
    }
    if (target != null && !_hasPageData(target)) {
      widget.readController.disableRight.value = true;
      if (notify) {
        widget.readController.onEdgeCallback_?.call(false);
      }
      final clamp = maxIndex ?? pageController.initialPage;
      _scheduleClampToValidPage(clamp);
      return;
    }
    if (widget.readController.disableRight.value) {
      if (notify) {
        widget.readController.onEdgeCallback_?.call(false);
      }
      return;
    }
    if (animNextPageIndex == null) {
      widget.onScroll?.call();
      animNextPageIndex = pageController.page!.round() + 1;
      await pageController.animateToPage(
        animNextPageIndex!,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
      if (pageController.page!.round() == animNextPageIndex) {
        animNextPageIndex = null;
      }
    } else {
      pageController.jumpToPage(
        animNextPageIndex!,
      );
      animNextPageIndex = null;
      _nextPage(notify);
    }
  }

  void _onPageIndexChanged(int index, {bool pre = false}) {
    List<int> chapterIndexDiff = widget.readController.findChapterIndex(index);
    PaintData? data = widget.readController.bookPageList[chapterIndexDiff[0]]
        ?[chapterIndexDiff[1]];
    if (data == null) {
      return;
    }
    if (!pre) {
      int chapterIndex = data.chapterIndex;
      int pageIndex = index - widget.readController.firstIndex;
      int pageTotal = widget.readController.pageTotal();
      if (data.bookPage == null) {
        bool isSnapshot = data.widget == widget.readController.summaryWidget;
        widget.readController.onPageIndexChangedController.add(
          BookProgress(data.title, chapterIndex, pageIndex, pageTotal, 0, 0, 0,
              null, !isSnapshot, isSnapshot),
        );
      } else {
        BookLine bookLine = data.bookPage!.lines.first;
        int sentenceIndex = bookLine.sentence.index;
        int originalIndex = bookLine.sentence.originalIndex;
        int wordIndex = bookLine.startIndex;
        widget.readController.onPageIndexChangedController.add(
          BookProgress(
            data.title,
            chapterIndex,
            pageIndex,
            pageTotal,
            max(0, sentenceIndex),
            max(0, originalIndex),
            max(0, wordIndex),
            data.bookPage,
          ),
        );
      }
    }
    pageController.position.firstIndex = widget.readController.firstIndex;
    widget.readController.edge(index, data, pre);
  }
}
