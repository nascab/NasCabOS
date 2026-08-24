part of '../video_player_controller.dart';

extension PlayerWebSubtitle on PlayerController {
  /// 客户端 VTT 叠层距底部的留白（横屏控制条较矮，避免字幕偏高）。
  double transcodeSubtitleBottomPadding(BuildContext context) {
    final mq = MediaQuery.of(context);
    final safe = mq.padding.bottom;
    if (mq.orientation == Orientation.landscape) {
      return safe + 24;
    }
    return safe + 88;
  }

  /// Web 全场景；非 Web 转码时文本字幕；原画仅文本外挂——均走 [WebSubtitleOverlay]。
  bool _useClientSubtitleOverlay() {
    if (currentIsNoSubtitle) return false;
    if (kIsWeb) return true;
    if (currentQuality.value != 'original') return true;
    return isTextExternalSubtitleLabel(currentSubtitleTrack.value);
  }

  bool _webIsBitmapSubtitleCodecName(String? codecName) {
    final v = (codecName ?? '').toLowerCase().trim();
    return v == 'pgssub' ||
        v == 'hdmv_pgs_subtitle' ||
        v == 'vobsub' ||
        v == 'dvd_subtitle' ||
        v == 'dvdsub' ||
        v == 'dvb_subtitle' ||
        v == 'xsub';
  }

  bool _webIsBitmapExternalSubtitleExtension(String ext) {
    final v = ext.toLowerCase().trim();
    return v == '.sup' || v == '.sub' || v == '.idx';
  }

  void _webClearSubtitle() {
    webSubtitleCues.clear();
    webActiveSubtitleText.value = '';
    _webSubtitleCacheKey = '';
  }

  void _webUpdateActiveCue() {
    if (!_useClientSubtitleOverlay()) {
      if (webActiveSubtitleText.value.isNotEmpty) {
        webActiveSubtitleText.value = '';
      }
      return;
    }
    if (currentIsNoSubtitle) {
      if (webActiveSubtitleText.value.isNotEmpty) {
        webActiveSubtitleText.value = '';
      }
      return;
    }
    final cues = webSubtitleCues;
    if (cues.isEmpty) {
      if (webActiveSubtitleText.value.isNotEmpty) {
        webActiveSubtitleText.value = '';
      }
      return;
    }
    final cue = findActiveCue(cues, position.value);
    final text = cue?.text ?? '';
    if (webActiveSubtitleText.value != text) {
      webActiveSubtitleText.value = text;
    }
  }

  Future<void> loadWebSubtitleIfNeeded({bool force = false}) async {
    if (!_useClientSubtitleOverlay()) {
      _webClearSubtitle();
      return;
    }
    if (playlist.isEmpty || currentIndex.value < 0 || currentIndex.value >= playlist.length) {
      _webClearSubtitle();
      return;
    }
    if (currentIsNoSubtitle) {
      _webClearSubtitle();
      return;
    }

    final fileInfo = playlist[currentIndex.value];
    final videoPath = fileInfo['path']?.toString().trim() ?? '';
    if (videoPath.isEmpty) {
      _webClearSubtitle();
      return;
    }

    final label = currentSubtitleTrack.value;
    final track = _rawSubtitleTracks.firstWhere(
      (e) => e['label'] == label,
      orElse: () => <String, dynamic>{},
    );
    if (track.isEmpty) {
      _webClearSubtitle();
      return;
    }

    final isExternal = track['isExternal'] == true;
    final codecName = track['codec_name']?.toString();
    if (isExternal) {
      final ext = path.extension(track['path']?.toString() ?? '');
      if (_webIsBitmapExternalSubtitleExtension(ext)) {
        _webClearSubtitle();
        return;
      }
    } else if (_webIsBitmapSubtitleCodecName(codecName)) {
      // Bitmap subtitles must be burned-in via transcode.
      _webClearSubtitle();
      return;
    }
    final subtitleIndex = track['mapIndex'] is int ? (track['mapIndex'] as int) : null;
    final subtitlePath = track['path']?.toString().trim() ?? '';
    final idx = subtitleIndex ?? 0;

    final key = isExternal ? 'ext:$subtitlePath#$idx' : 'emb:$videoPath#$idx';
    if (!force && key == _webSubtitleCacheKey && webSubtitleCues.isNotEmpty) {
      _webUpdateActiveCue();
      return;
    }
    if (_webSubtitleLoading) return;
    _webSubtitleLoading = true;
    _webSubtitleCacheKey = key;

    try {
      final api = ApiController.instance;
      final baseUrl = api.baseUrl;
      final token = api.accessToken;

      var url = '$baseUrl/api/videoPlayer/subtitle-vtt?subtitleIndex=$idx';
      if (isExternal) {
        if (subtitlePath.isEmpty) {
          _webClearSubtitle();
          return;
        }
        url += '&subtitlePath=${Uri.encodeComponent(subtitlePath)}';
      } else {
        url += '&filePath=${Uri.encodeComponent(videoPath)}';
      }
      if (token != null) {
        url += '&accessToken=$token';
      }

      final resp = await HttpUtil.get(
        url,
        timeout: const Duration(seconds: 30),
        maxRetries: 0,
      );
      if (!resp.isSuccess || resp.body == null || resp.body!.isEmpty) {
        webSubtitleCues.clear();
        webActiveSubtitleText.value = '';
        return;
      }
      final cues = parseWebVtt(resp.body!);
      webSubtitleCues.assignAll(cues);
      _webUpdateActiveCue();
    } catch (_) {
      webSubtitleCues.clear();
      webActiveSubtitleText.value = '';
    } finally {
      _webSubtitleLoading = false;
    }
  }
}

