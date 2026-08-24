part of '../video_player_controller.dart';

extension PlayerStreamInfo on PlayerController {
  String currentSourcePathForInfo() {
    if (playlist.isEmpty ||
        currentIndex.value < 0 ||
        currentIndex.value >= playlist.length) {
      return '';
    }
    final item = playlist[currentIndex.value];
    final internal = item['internalPath']?.toString().trim() ?? '';
    final pathValue = item['path']?.toString().trim() ?? '';
    return internal.isNotEmpty ? internal : pathValue;
  }

  Future<void> addAndSelectExternalSubtitle({
    required String subtitlePath,
    required String filename,
    String? source,
  }) async {
    final p = subtitlePath.trim();
    final name = filename.trim().isEmpty ? path.basename(p) : filename.trim();
    if (p.isEmpty || name.isEmpty) return;

    // 去重：如果已存在同路径的外挂字幕，不重复添加
    final exists = _rawSubtitleTracks.any(
      (e) =>
          e['isExternal'] == true &&
          (e['path']?.toString().trim() ?? '') == p,
    );
    if (!exists) {
      final label = name;
      _rawSubtitleTracks.insert(0, {
        'index': -1,
        'label': label,
        'isExternal': true,
        'path': p,
        'filename': name,
        'language': null,
        'source': source,
        'tags': {'title': name},
        'codec_name': path.extension(name).toLowerCase(),
      });
      // Display list: index 0 是“无字幕”，外挂字幕从 1 开始插入
      subtitleTracks.insert(1, label);
    }

    // 选中该字幕（即使已存在也强制切换一次）
    await Future<void>.delayed(Duration.zero);
    setSubtitleTrack(name, force: true);
  }

  Future<void> deleteExternalSubtitle({
    required String subtitlePath,
  }) async {
    final videoPath = currentSourcePathForInfo();
    if (videoPath.isEmpty) return;
    final sub = subtitlePath.trim();
    if (sub.isEmpty) return;

    // Find the external track entry before any mutation (needed for correct switching logic)
    final Map<String, dynamic>? extTrack = (() {
      for (final e in _rawSubtitleTracks) {
        if (e['isExternal'] == true && (e['path']?.toString().trim() ?? '') == sub) {
          return e;
        }
      }
      return null;
    })();
    final extLabel = extTrack != null ? extTrack['label']?.toString().trim() ?? '' : '';
    final deletingSelected = extLabel.isNotEmpty && currentSubtitleTrack.value == extLabel;

    final baseUrl = ApiController.instance.baseUrl.trim();
    final token = ApiController.instance.accessToken;
    try {
      final res = await HttpUtil.post(
        '$baseUrl/api/videoPlayer/deleteExternalSubtitle',
        body: {
          'filePath': videoPath,
          'subtitlePath': sub,
        },
        headers: token != null ? {'Authorization': 'Bearer $token'} : null,
      );
      if (!res.isOk) {
        ToastUtil.show(res.errorMessage);
        return;
      }

      // If deleting the currently selected external subtitle, switch to "no subtitle" FIRST,
      // while the raw external track still exists, so setSubtitleTrack can correctly detect
      // currentSubtitleIsExternal and re-init player if needed.
      if (deletingSelected) {
        setSubtitleTrack('player_no_subtitle'.tr, force: true);
      }

      // Local remove
      _rawSubtitleTracks.removeWhere(
        (e) => e['isExternal'] == true && (e['path']?.toString().trim() ?? '') == sub,
      );
      subtitleTracks.removeWhere((label) {
        final found = _rawSubtitleTracks.any((e) => e['label'] == label);
        return !found && label != 'player_no_subtitle'.tr;
      });

      ToastUtil.show('player_subtitle_delete_success'.tr);
    } catch (e) {
      ToastUtil.show(e.toString());
    }
  }

  Future<void> _fetchStreamInfo(Map<String, dynamic> fileInfo) async {
    final filePath = fileInfo['path']?.toString() ?? '';
    final internalPath = fileInfo['internalPath']?.toString().trim() ?? '';
    final p = filePath.trim().toLowerCase();
    if (p.startsWith('http://') || p.startsWith('https://')) return;
    final baseUrl = ApiController.instance.baseUrl;
    final token = ApiController.instance.accessToken;
    try {
      var url =
          '$baseUrl/api/videoPlayer/info?filePath=${Uri.encodeComponent(filePath)}&ignoreFindSub=${ignoreFindSub == 0 ? 0 : 1}';
      if (internalPath.isNotEmpty) {
        url += '&internalPath=${Uri.encodeComponent(internalPath)}';
      }
      final res = await HttpUtil.get(
        url,
        headers: token != null ? {'Authorization': 'Bearer $token'} : null,
      );
      if (!res.isOk) return;

      final data = res.json;
      if (data == null) return;
      final payload = data['data'];
      if (payload is! Map) return;
      final body = payload.cast<String, dynamic>();

      final streams = (body['streams'] as List).cast<Map<String, dynamic>>();

      final dur = body['duration'];
      if (dur is num) {
        _sourceDurationSeconds = dur.round();
      } else if (dur != null) {
        final parsed = double.tryParse(dur.toString());
        if (parsed != null) {
          _sourceDurationSeconds = parsed.round();
        }
      }

      final sizeRaw = body['size'];
      if (sizeRaw is num) {
        _sourceFileSizeBytes = sizeRaw.toInt();
      } else if (sizeRaw != null) {
        _sourceFileSizeBytes = int.tryParse(sizeRaw.toString());
      } else {
        _sourceFileSizeBytes = null;
      }

      _applyOpenSkipData(body['openSkip']);

      _rawAudioTracks.clear();
      audioTracks.clear();
      _rawVideoTracks.clear();
      _rawSubtitleTracks.clear();
      subtitleTracks.clear();
      subtitleTracks.add('player_no_subtitle'.tr);
      currentSubtitleTrack.value = 'player_no_subtitle'.tr;
      //解析音频 字幕 视频 轨道
      var audioOrder = 0;
      var subtitleOrder = 0;
      for (final s in streams) {
        if (s['codec_type'] == 'video') {
          _rawVideoTracks.add(s);
        } else if (s['codec_type'] == 'audio') {
          final lang = s['tags']?['language'] ?? 'und';
          final title = s['tags']?['title'] ?? s['codec_name'];
          final label = 'Audio ${s['index']} ($lang) - $title';
          _rawAudioTracks.add({
            'index': s['index'],
            'mapIndex': audioOrder,
            'label': label,
            ...s,
          });
          audioTracks.add(label);
          audioOrder++;
        } else if (s['codec_type'] == 'subtitle') {
          final lang = s['tags']?['language'] ?? 'und';
          final title = s['tags']?['title'] ?? s['codec_name'];
          final label = '($lang) $title';
          _rawSubtitleTracks.add({
            'index': s['index'],
            'mapIndex': subtitleOrder,
            'label': label,
            'isExternal': false,
            ...s,
          });
          subtitleTracks.add(label);
          subtitleOrder++;
        }
      }
    
      if (body['externalSubtitles'] != null) {
        final extSubs = (body['externalSubtitles'] as List)
            .cast<Map<String, dynamic>>();
        for (final sub in extSubs) {
          final label = '${sub['filename']}';
          // 使用特殊的 index 标记外挂字幕，例如负数或者特定结构
          // 这里我们复用 _rawSubtitleTracks 结构，添加 isExternal 标记
          _rawSubtitleTracks.insert(0, {
            // 插入到前面，或者按照需求 "排列在内嵌字幕上方" -> 列表的最前面?
            'index': -1, // 外挂字幕没有流索引
            'label': label,
            'isExternal': true,
            'path': sub['path'],
            'filename': sub['filename'],
            'language': sub['language'],
            'source': sub['source'],
            'tags': {'title': sub['filename']},
            'codec_name': sub['ext'],
          });
          subtitleTracks.insert(1, label); // 0 是 '无字幕'
        }
      }
      // 应用默认音频轨道 为第一个音频轨道
      if (audioTracks.isNotEmpty) {
        currentAudioTrack.value = audioTracks.first;
      }
      // 应用默认字幕轨道 为第一个字幕轨道 索引0是“无字幕”
      if (subtitleTracks.isNotEmpty && subtitleTracks.length > 1) {
        currentSubtitleTrack.value = subtitleTracks[1];
      }
      // 如果是web端 默认设置为“无字幕” 因为目前web端只有转码才支持字幕
      if (kIsWeb) {
        currentSubtitleTrack.value = 'player_no_subtitle'.tr;
      }
      if (body['preference'] != null) {
        final pref = (body['preference'] as Map).cast<String, dynamic>();
        _pendingPreference = pref;
        await applyPreference(pref);
      }
      checkWebIfNeedTranscode();
      checkAndroidIfNeedTranscode();
      applyAndroidFvpEngineIfNeeded();
    } catch (_) {
      return;
    }
  }

}
