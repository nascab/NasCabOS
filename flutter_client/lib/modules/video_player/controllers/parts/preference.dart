part of '../video_player_controller.dart';

/// 保存和读取用户对当前视频的偏好 如字幕索引 声轨索引
extension PlayerPreference on PlayerController {
  Future<void> saveProgress() async {
    if (playlist.isEmpty || currentIndex.value >= playlist.length) return;
    final fileInfo = playlist[currentIndex.value];
    final path = fileInfo['path']?.toString();
    final internalPath = fileInfo['internalPath']?.toString().trim() ?? '';
    if (path == null) return;
    final p = path.trim().toLowerCase();
    if (p.startsWith('http://') || p.startsWith('https://')) return;

    final baseUrl = ApiController.instance.baseUrl;
    final token = ApiController.instance.accessToken;

    try {
      await HttpUtil.post(
        '$baseUrl/api/videoPlayer/preference',
        body: {
          'filePath': path,
          if (internalPath.isNotEmpty) 'internalPath': internalPath,
          'playback_position': position.value.inSeconds.toString(),
          'subtitle_label': currentSubtitleTrack.value,
          'audio_label': currentAudioTrack.value,
        },
        headers: token != null ? {'Authorization': 'Bearer $token'} : null,
      );
    } catch (_) {}
  }

  /// 保存音频偏好
  void savePreference() {
    saveProgress();
  }

  /// 应用用户上次观看设置的偏好
  Future<void> applyPreference(Map<String, dynamic> pref) async {
    int? asInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    final audioLabel = pref['audio_label']?.toString();
    if (audioLabel != null && audioLabel.isNotEmpty) {
      for (final t in _rawAudioTracks) {
        if (t['label']?.toString() == audioLabel) {
          currentAudioTrack.value = audioLabel;
          break;
        }
      }
    }

    /// 恢复上次看的字幕
    final subtitleLabel = pref['subtitle_label']?.toString();
    if (subtitleLabel != null && subtitleLabel.isNotEmpty) {
      for (final t in _rawSubtitleTracks) {
        if (t['label']?.toString() == subtitleLabel) {
          currentSubtitleTrack.value = subtitleLabel;
          break;
        }
      }
    }

    // 观看进度：在拉流 URL 生成之前就要可用，否则首包总是从 0 开始再 seek，服务端会起两次 ffmpeg。
    final resumeSeconds = asInt(pref['playback_position']);
    if (resumeSeconds != null && resumeSeconds > 10) {
      if (_resumeSeekBakedIntoUrlSeconds != null &&
          _resumeSeekBakedIntoUrlSeconds == resumeSeconds) {
        // 已在 transcode 的 seek 参数中带上该偏移
      } else {
        _pendingResumePosition = Duration(seconds: resumeSeconds);
      }
    }

  }
}
