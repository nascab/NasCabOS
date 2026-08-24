part of '../video_player_controller.dart';

extension PlayerTranscode on PlayerController {
  void _stopTranscoding({String? playId}) {
    final id = playId ?? _playId;
    if (id == null) return;

    final baseUrl = ApiController.instance.baseUrl;
    final token = ApiController.instance.accessToken;
    try {
      final url = '$baseUrl/api/videoPlayer/stop';
      HttpUtil.post(
        url,
        body: {'playId': id},
        headers: {if (token != null) 'Authorization': 'Bearer $token'},
      );
    } catch (_) {}

    if (playId == null || playId == _playId) {
      _playId = null;
      // 仅彻底停止转码时重置时间轴；seek/换源时只停旧 playId，保留进度锚点。
      if (playId == null) {
        _transcodeBaseSeconds = 0;
        _pendingTranscodeSeekSeconds = null;
      }
    }
  }
}
