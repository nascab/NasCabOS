part of '../video_player_controller.dart';

extension PlayerWindow on PlayerController {
  Future<void> _setDesktopFullscreen(bool enabled) async {
    if (!DeviceUtils.isDesktop || isClosed) return;
    if (enabled) {
      bool wasMaximized = false;
      try {
        wasMaximized = await windowManager.isMaximized();
      } catch (_) {}
      _restoreMaximizedAfterExitFullscreen = wasMaximized;
      final isWindows = defaultTargetPlatform == TargetPlatform.windows;
      if (isWindows && wasMaximized) {
        try {
          await windowManager.unmaximize();
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      try {
        await windowManager.setFullScreen(true);
      } catch (_) {}
      try {
        await windowManager.focus();
      } catch (_) {}
    } else {
      try {
        await windowManager.setFullScreen(false);
      } catch (_) {}
      if (_restoreMaximizedAfterExitFullscreen) {
        _restoreMaximizedAfterExitFullscreen = false;
        final isWindows = defaultTargetPlatform == TargetPlatform.windows;
        if (isWindows) {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        }
        try {
          await windowManager.maximize();
        } catch (_) {}
      }
    }
  }

  Future<void> _initWindow() async {
    if (!DeviceUtils.isDesktop || isClosed) return;
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(const Size(800, 600));
    try {
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
    } catch (_) {}
    try {
      await windowManager.show();
    } catch (_) {}
    try {
      await windowManager.focus();
    } catch (_) {}
  }

  /// 切换全屏
  void toggleFullscreen() async {
    if (DeviceUtils.isWeb) {
      final next = !isFullscreen.value;
      isFullscreen.value = next;
      try {
        FullScreen.setFullScreen(next);
        print("切换全屏: $next");
      } catch (err) {
        print('切换全屏失败: $err');
      }
      isFullscreen.value = FullScreen.isFullScreen;
    } else if (DeviceUtils.isDesktop) {
      final next = !isFullscreen.value;
      isFullscreen.value = next;
      await _setDesktopFullscreen(next);
    } else {
      final next = !isFullscreen.value;
      isFullscreen.value = next;
      try {
        FullScreen.setFullScreen(next);
      } catch (_) {}
      isFullscreen.value = FullScreen.isFullScreen;
    }
  }

  /// 退出全屏（用于页面退出时）
  void exitFullscreen() async {
    if (DeviceUtils.isWeb && isFullscreen.value) {
      isFullscreen.value = false;
      try {
        FullScreen.setFullScreen(false);
      } catch (_) {}
      isFullscreen.value = FullScreen.isFullScreen;
    } else if (DeviceUtils.isDesktop && isFullscreen.value) {
      isFullscreen.value = false;
      await _setDesktopFullscreen(false);
    } else if (isFullscreen.value) {
      isFullscreen.value = false;
      try {
        FullScreen.setFullScreen(false);
      } catch (_) {}
      isFullscreen.value = FullScreen.isFullScreen;
    }
  }

  void handlePlayerTap() {
    if (isLocked.value) {
      _showLockedIcon();
      ToastUtil.show('屏幕已锁定');
      return;
    }
    toggleControls();
  }

  void lockScreen() {
    if (isLocked.value) return;
    isLocked.value = true;
    showControls.value = false;
    showLockedIcon.value = false;
    _hideTimer?.cancel();
    ToastUtil.show('屏幕已锁定');
  }

  void unlockScreen() {
    if (!isLocked.value) return;
    isLocked.value = false;
    showLockedIcon.value = false;
    showControls.value = true;
    resetControlsTimer();
  }

  void _showLockedIcon() {
    showLockedIcon.value = true;
    _lockIconTimer?.cancel();
    _lockIconTimer = Timer(const Duration(seconds: 3), () {
      if (isClosed) return;
      showLockedIcon.value = false;
    });
  }

  Future<void> toggleOrientation() async {
    final next = !isLandscape.value;
    isLandscape.value = next;
    if (DeviceUtils.isMobile) {
      if (next) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
        ]);
      }
    }
  }

  Future<void> restoreOrientation() async {
    _lockIconTimer?.cancel();
    _lockIconTimer = null;
    showLockedIcon.value = false;
    isLocked.value = false;
    if (DeviceUtils.isMobile) {
      isLandscape.value = false;
      try {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
        ]);
      } catch (_) {}
    }
  }

  Future<void> prepareExitIfLandscape() async {
    if (!DeviceUtils.isMobile) return;
    if (!isLandscape.value) return;
    await restoreOrientation();
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  /// 显示/隐藏控制栏
  void toggleControls() {
    if (isLocked.value) return;
    showControls.value = !showControls.value;
    if (showControls.value) {
      resetControlsTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  /// 鼠标移动时显示控制栏
  void onMouseHover() {
    if (!showControls.value) {
      showControls.value = true;
    }
    resetControlsTimer();
  }

  /// 重置控制栏隐藏计时器
  void resetControlsTimer() {
    if (isLocked.value) return;
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (isLocked.value) return;
      if (isPlaying.value) {
        showControls.value = false;
      }
    });
  }
}
