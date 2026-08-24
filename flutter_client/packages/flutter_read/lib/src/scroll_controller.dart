import 'package:flutter/animation.dart';

import 'page_position.dart'  ;

class ReadPageController {
  final int initialPage;
  final List<ReadPagePosition> _positions = <ReadPagePosition>[];
  final void Function(ReadPagePosition position)? onAttachCallback;
  final void Function(ReadPagePosition position)? onDetachCallback;
  bool _isAnimateScrolling = false;

  ReadPageController({
    this.initialPage = 0,
    this.onAttachCallback,
    this.onDetachCallback,
  });

  ReadPagePosition get position {
    assert(_positions.isNotEmpty,
        'ScrollController not attached to any scroll views.');
    assert(_positions.length == 1,
        'ScrollController attached to multiple scroll views.');
    return _positions.single;
  }

  double? get page {
    return position.page;
  }

  bool get hasClients => _positions.isNotEmpty;

  void attach(ReadPagePosition position) {
    _positions.add(position);
    onAttachCallback?.call(position);
  }

  void detach(ReadPagePosition position) {
    _positions.remove(position);
    onDetachCallback?.call(position);
  }

  bool isSafeScrolling() {
    return position.isScrollingNotifier.value && _isAnimateScrolling;
  }

  Future<void> animateToPage(
    int page, {
    required Duration duration,
    required Curve curve,
  }) {
    if (position.cachedPage != null) {
      position.cachedPage = page.toDouble();
      return Future<void>.value();
    }
    _isAnimateScrolling = true;
    return position
        .animateTo(
          position.getPixelsFromPage(page.toDouble()),
          duration: duration,
          curve: curve,
        )
        .then((value) => _isAnimateScrolling = false);
  }

  void jumpToPage(int page) {
    if (position.cachedPage != null) {
      position.cachedPage = page.toDouble();
      return;
    }
    position.jumpTo(position.getPixelsFromPage(page.toDouble()));
  }
}
