part of '../video_player_controller.dart';

// 恢复播放进度：直接续播 + 进度条上方提示，可点击从头播放
extension PlayerResume on PlayerController {
  /// 显示「已为您继续播放」提示，倒计时 [seconds] 秒后自动消失
  void startResumeTip(int seconds) {
    _resumeTipTimer?.cancel();
    resumeTipCountdown.value = seconds;
    _resumeTipTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isClosed) {
        cancelResumeTip();
        return;
      }
      if (resumeTipCountdown.value <= 1) {
        cancelResumeTip();
        return;
      }
      resumeTipCountdown.value = resumeTipCountdown.value - 1;
    });
  }

  /// 取消恢复播放提示并释放定时器
  void cancelResumeTip() {
    _resumeTipTimer?.cancel();
    _resumeTipTimer = null;
    resumeTipCountdown.value = 0;
  }

  /// 用户点击「点我从头开始」
  void onResumeTipTap() {
    seekTo(Duration.zero);
    cancelResumeTip();
  }
}
