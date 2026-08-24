import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'read_compat.dart';
import 'read_controller.dart';

class ReadPagePosition extends ScrollPositionWithSingleContext
    implements PageMetrics {
  ReadPagePosition({
    required super.physics,
    required super.context,
    this.initialPage = 0,
    bool keepPage = true,
    double viewportFraction = 1.0,
    super.oldPosition,
    this.onEdgeCallback,
  })  : assert(viewportFraction > 0.0),
        _viewportFraction = viewportFraction,
        _pageToUseOnStartup = initialPage.toDouble(),
        super(
          initialPixels: null,
          keepScrollOffset: keepPage,
        );

  final int initialPage;
  double _pageToUseOnStartup;

  // When the viewport has a zero-size, the `page` can not
  // be retrieved by `getPageFromPixels`, so we need to cache the page
  // for use when resizing the viewport to non-zero next time.
  double? cachedPage;

  @override
  Future<void> ensureVisible(
    RenderObject object, {
    double alignment = 0.0,
    Duration duration = Duration.zero,
    Curve curve = Curves.ease,
    ScrollPositionAlignmentPolicy alignmentPolicy =
        ScrollPositionAlignmentPolicy.explicit,
    RenderObject? targetRenderObject,
  }) {
    // Since the _PagePosition is intended to cover the available space within
    // its viewport, stop trying to move the target render object to the center
    // - otherwise, could end up changing which page is visible and moving the
    // targetRenderObject out of the viewport.
    return super.ensureVisible(
      object,
      alignment: alignment,
      duration: duration,
      curve: curve,
      alignmentPolicy: alignmentPolicy,
    );
  }

  @override
  double get viewportFraction => _viewportFraction;
  double _viewportFraction;

  set viewportFraction(double value) {
    if (_viewportFraction == value) {
      return;
    }
    final double? oldPage = page;
    _viewportFraction = value;
    if (oldPage != null) {
      forcePixels(getPixelsFromPage(oldPage));
    }
  }

  // The amount of offset that will be added to [minScrollExtent] and subtracted
  // from [maxScrollExtent], such that every page will properly snap to the center
  // of the viewport when viewportFraction is greater than 1.
  //
  // The value is 0 if viewportFraction is less than or equal to 1, larger than 0
  // otherwise.
  double get _initialPageOffset =>
      math.max(0, viewportDimension * (viewportFraction - 1) / 2);

  double getPageFromPixels(double pixels, double viewportDimension) {
    assert(viewportDimension > 0.0);
    final double actual = math.max(0.0, pixels - _initialPageOffset) /
        (viewportDimension * viewportFraction);
    final double round = actual.roundToDouble();
    if ((actual - round).abs() < precisionErrorTolerance) {
      return round;
    }
    return actual;
  }

  double getPixelsFromPage(double page) {
    return page * viewportDimension * viewportFraction + _initialPageOffset;
  }

  @override
  double? get page {
    assert(
      !hasPixels || hasContentDimensions,
      'Page value is only available after content dimensions are established.',
    );
    return !hasPixels || !hasContentDimensions
        ? null
        : cachedPage ??
            getPageFromPixels(pixels.clamp(minScrollExtent, maxScrollExtent),
                viewportDimension);
  }

  @override
  void saveScrollOffset() {
    final PageStorage? widget =
        context.storageContext.findAncestorWidgetOfExactType<PageStorage>();
    final PageStorageBucket? bucket = widget?.bucket;
    bucket?.writeState(context.storageContext,
        cachedPage ?? getPageFromPixels(pixels, viewportDimension));
  }

  @override
  void restoreScrollOffset() {
    if (!hasPixels) {
      final PageStorage? widget =
          context.storageContext.findAncestorWidgetOfExactType<PageStorage>();
      final PageStorageBucket? bucket = widget?.bucket;
      final double? value =
          bucket?.readState(context.storageContext) as double?;
      if (value != null) {
        _pageToUseOnStartup = value;
      }
    }
  }

  @override
  void saveOffset() {
    context
        .saveOffset(cachedPage ?? getPageFromPixels(pixels, viewportDimension));
  }

  @override
  void restoreOffset(double offset, {bool initialRestore = false}) {
    if (initialRestore) {
      _pageToUseOnStartup = offset;
    } else {
      jumpTo(getPixelsFromPage(offset));
    }
  }

  @override
  bool applyViewportDimension(double viewportDimension) {
    final double? oldViewportDimensions =
        hasViewportDimension ? this.viewportDimension : null;
    if (viewportDimension == oldViewportDimensions) {
      return true;
    }
    final bool result = super.applyViewportDimension(viewportDimension);
    final double? oldPixels = hasPixels ? pixels : null;
    double page;
    if (oldPixels == null) {
      page = _pageToUseOnStartup;
    } else if (oldViewportDimensions == 0.0) {
      // If resize from zero, we should use the _cachedPage to recover the state.
      page = cachedPage!;
    } else {
      page = getPageFromPixels(oldPixels, oldViewportDimensions!);
    }
    final double newPixels = getPixelsFromPage(page);

    // If the viewportDimension is zero, cache the page
    // in case the viewport is resized to be non-zero.
    cachedPage = (viewportDimension == 0.0) ? page : null;

    if (newPixels != oldPixels) {
      correctPixels(newPixels);
      return false;
    }
    return result;
  }

  @override
  void absorb(ScrollPosition other) {
    super.absorb(other);
    assert(cachedPage == null);

    if (other is! ReadPagePosition) {
      return;
    }

    if (other.cachedPage != null) {
      cachedPage = other.cachedPage;
    }
  }

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final double newMinScrollExtent = minScrollExtent + _initialPageOffset;
    return super.applyContentDimensions(
      newMinScrollExtent,
      math.max(newMinScrollExtent, maxScrollExtent - _initialPageOffset),
    );
  }

  @override
  PageMetrics copyWith(
      {double? minScrollExtent,
      double? maxScrollExtent,
      double? pixels,
      double? viewportDimension,
      AxisDirection? axisDirection,
      double? viewportFraction,
      double? devicePixelRatio}) {
    Function pageMetrics = PageMetrics.new;
    if (ReadCompat().isDartVersionAtLeast300()) {
      dynamic it = this;
      return pageMetrics(
        minScrollExtent: minScrollExtent ??
            (hasContentDimensions ? this.minScrollExtent : null),
        maxScrollExtent: maxScrollExtent ??
            (hasContentDimensions ? this.maxScrollExtent : null),
        pixels: pixels ?? (hasPixels ? this.pixels : null),
        viewportDimension: viewportDimension ??
            (hasViewportDimension ? this.viewportDimension : null),
        axisDirection: axisDirection ?? this.axisDirection,
        viewportFraction: viewportFraction ?? this.viewportFraction,
        devicePixelRatio: devicePixelRatio ?? it.devicePixelRatio,
      );
    } else {
      return pageMetrics(
        minScrollExtent: minScrollExtent ??
            (hasContentDimensions ? this.minScrollExtent : null),
        maxScrollExtent: maxScrollExtent ??
            (hasContentDimensions ? this.maxScrollExtent : null),
        pixels: pixels ?? (hasPixels ? this.pixels : null),
        viewportDimension: viewportDimension ??
            (hasViewportDimension ? this.viewportDimension : null),
        axisDirection: axisDirection ?? this.axisDirection,
        viewportFraction: viewportFraction ?? this.viewportFraction,
      );
    }
  }

  // 处理滑动边缘
  int firstIndex = -1;
  double minBeginPixels = -1;
  double beginPixels = 0;
  bool isLeft = false;
  bool isRight = false;
  bool isBreak = false;
  bool leftEdge = false;
  bool rightEdge = false;
  bool disableLeft = true;
  bool disableRight = true;
  final EdgeCallback? onEdgeCallback;

  @override
  void beginActivity(ScrollActivity? newActivity) {
    super.beginActivity(newActivity);
    if (newActivity is IdleScrollActivity &&
        !activity!.isScrolling &&
        hasPixels) {
      beginPixels = pixels;
      if (beginPixels < minBeginPixels || minBeginPixels < 0) {
        minBeginPixels = beginPixels;
      }
      isLeft = false;
      isRight = false;
      isBreak = false;
      leftEdge = false;
      rightEdge = false;
    }
  }

  @override
  void applyUserOffset(double delta) {
    updateUserScrollDirection(
        delta > 0.0 ? ScrollDirection.forward : ScrollDirection.reverse);
    double value = pixels - physics.applyPhysicsToUserOffset(this, delta);
    if (delta < 0.0 && (isRight || disableRight)) {
      setPixels(math.min(beginPixels, value));
      if (value > beginPixels && !rightEdge) {
        rightEdge = true;
        if (!isRight && disableRight) {
          onEdgeCallback?.call(false);
        }
      }
    } else if (delta > 0.0 &&
        (isLeft || disableLeft || ((page ?? 0) < firstIndex))) {
      if ((page ?? 0) < firstIndex) {
        setPixels(minBeginPixels);
        leftEdge = true;
      } else {
        setPixels(math.max(beginPixels, value));
      }
      if (value < beginPixels && !leftEdge) {
        leftEdge = true;
        if (!isLeft && disableLeft) {
          onEdgeCallback?.call(true);
        }
      }
    } else {
      setPixels(value);
    }
    if (!isBreak) {
      double diff = beginPixels - pixels;
      if (diff > 0 && !isLeft) {
        isRight = true;
      } else if (!isRight) {
        isLeft = true;
      }
    }
  }

  @override
  void goBallistic(double velocity) {
    if (((page ?? 0) < firstIndex) ||
        (disableLeft && velocity < 0) ||
        (disableRight && velocity > 0)) {
      velocity = 0;
    }
    super.goBallistic(velocity);
    if (userScrollDirection != ScrollDirection.idle) {
      isLeft = isRight = false;
      isBreak = true;
    }
  }
}
