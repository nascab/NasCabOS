part of '../api_controller.dart';

extension ApiControllerUrls on ApiController {
  /// 获取文件的缩略图URL
  String getTinyUrl(String filePath, {int? size}) {
    // 构建参数Map
    final Map<String, dynamic> params = {};
    params['path'] = filePath;
    if (size != null) {
      params['size'] = size.toString();
    }
    if (_state.accessToken != null && kIsWeb) {
      params['accessToken'] = _state.accessToken;
    }
    // 加密参数
    final aesParam = _encryptParams(params);
    // 如果加密成功，使用aes参数；否则回退到明文（或处理错误）
    if (aesParam.isNotEmpty) {
      var url =
          '${_state.baseUrl}/api/file/tiny?aes=${Uri.encodeComponent(aesParam)}';
      if (_state.baseUrl.trim() == ApiController.p2pBaseUrl) {
        url += '&path=${Uri.encodeComponent(filePath)}';
        url += '&p2pChannel=file';
        if (_state.accessToken != null &&
            _state.accessToken!.trim().isNotEmpty) {
          url += '&accessToken=${Uri.encodeComponent(_state.accessToken!)}';
        }
        if (size != null) {
          url += '&size=${Uri.encodeComponent(size.toString())}';
        }
      }
      return url;
    }
    var url =
        '${_state.baseUrl}/api/file/tiny?path=${Uri.encodeComponent(filePath)}';
    if (_state.baseUrl.trim() == ApiController.p2pBaseUrl) {
      url += '&p2pChannel=file';
    }
    if (_state.accessToken != null && _state.accessToken!.trim().isNotEmpty) {
      url += '&accessToken=${Uri.encodeComponent(_state.accessToken!)}';
    }
    if (size != null) {
      url += '&size=${Uri.encodeComponent(size.toString())}';
    }
    return url;
  }

  /// 获取书籍的缩略图URL
  String getBookTinyUrl({required String fileHash, int size = 500}) {
    final fh = fileHash.trim();
    if (fh.isEmpty) return '';
    final safeSize = size.clamp(50, 2000);
    final token = (_state.accessToken ?? '').trim();
    final Map<String, dynamic> params = {};
    params['file_hash'] = fh;
    params['size'] = safeSize.toString();
    if (token.isNotEmpty) {
      params['accessToken'] = token;
    }
    final aesParam = _encryptParams(params);
    if (aesParam.isNotEmpty) {
      var url =
          '${_state.baseUrl}/api/book/tiny?aes=${Uri.encodeComponent(aesParam)}';
      if (_state.baseUrl.trim() == ApiController.p2pBaseUrl) {
        url += '&p2pChannel=file';
        url += '&file_hash=${Uri.encodeComponent(fh)}';
        url += '&size=${Uri.encodeComponent(safeSize.toString())}';
        if (token.isNotEmpty) {
          url += '&accessToken=${Uri.encodeComponent(token)}';
        }
      }
      return url;
    }
    var url =
        '${_state.baseUrl}/api/book/tiny?file_hash=${Uri.encodeComponent(fh)}&size=${Uri.encodeComponent(safeSize.toString())}';
    if (_state.baseUrl.trim() == ApiController.p2pBaseUrl) {
      url += '&p2pChannel=file';
    }
    if (token.isNotEmpty) {
      url += '&accessToken=${Uri.encodeComponent(token)}';
    }
    return url;
  }

  String getMusicCoverUrl({required String filePath, int size = 500}) {
    final p = filePath.trim();
    if (p.isEmpty) return '';
    final Map<String, dynamic> params = {};
    params['file_path'] = p;
    params['size'] = size.toString();
    if (_state.accessToken != null) {
      params['accessToken'] = _state.accessToken;
    }
    final aesParam = _encryptParams(params);
    if (aesParam.isNotEmpty) {
      return '${_state.baseUrl}/api/music/cover?aes=${Uri.encodeComponent(aesParam)}';
    }
    var url =
        '${_state.baseUrl}/api/music/cover?file_path=${Uri.encodeComponent(p)}&size=${Uri.encodeComponent(size.toString())}';
    if (_state.accessToken != null) {
      url += '&accessToken=${Uri.encodeComponent(_state.accessToken!)}';
    }
    return url;
  }

  /// 为URL添加认证参数
  /// [url] 原始URL
  /// 返回添加了认证参数的URL
  String getAuthedUrl(String url) {
    final raw = url.trim();
    if (raw.isEmpty) return '';

    final token = (_state.accessToken ?? '').trim();
    if (token.isEmpty) return raw;

    Uri uri;
    try {
      uri = Uri.parse(raw);
    } catch (_) {
      return raw;
    }

    final qp = Map<String, String>.from(uri.queryParameters);

    final Map<String, dynamic> params = {'accessToken': token};
    final aesParam = _encryptParams(params);
    if (aesParam.isNotEmpty) {
      qp.remove('accessToken');
      qp['aes'] = aesParam;
    } else {
      qp['accessToken'] = token;
    }

    return uri.replace(queryParameters: qp.isEmpty ? null : qp).toString();
  }

  String buildAuthedApiUrl(
    String apiPath, {
    Map<String, dynamic> queryParameters = const {},
    bool withAccessToken = true,
    String? p2pChannel,
  }) {
    final base = _state.baseUrl.trim();
    final path = apiPath.trim();
    if (base.isEmpty || path.isEmpty) return '';

    final token = (_state.accessToken ?? '').trim();
    final params = <String, dynamic>{};
    params.addAll(queryParameters);
    if (withAccessToken && token.isNotEmpty) {
      params['accessToken'] = token;
    }

    final aesParam = _encryptParams(params);
    final isP2p = base == ApiController.p2pBaseUrl;
    final resolvedPath = path.startsWith('/') ? path : '/$path';

    if (aesParam.isNotEmpty) {
      var url = '$base$resolvedPath?aes=${Uri.encodeComponent(aesParam)}';
      if (isP2p) {
        final mark = (p2pChannel ?? '').trim();
        if (mark.isNotEmpty) {
          url += '&p2pChannel=${Uri.encodeComponent(mark)}';
        }
        for (final entry in queryParameters.entries) {
          final key = entry.key.trim();
          if (key.isEmpty) continue;
          final value = entry.value;
          if (value == null) continue;
          if (value is Iterable) {
            for (final item in value) {
              if (item == null) continue;
              url +=
                  '&${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(item.toString())}';
            }
            continue;
          }
          url +=
              '&${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value.toString())}';
        }
        if (withAccessToken && token.isNotEmpty) {
          url += '&accessToken=${Uri.encodeComponent(token)}';
        }
      }
      return url;
    }

    final plainParams = <String, dynamic>{};
    plainParams.addAll(queryParameters);
    if (withAccessToken && token.isNotEmpty) {
      plainParams['accessToken'] = token;
    }
    if (isP2p) {
      final mark = (p2pChannel ?? '').trim();
      if (mark.isNotEmpty) {
        plainParams['p2pChannel'] = mark;
      }
    }
    return Uri.parse('$base$resolvedPath')
        .replace(queryParameters: plainParams.map((key, value) => MapEntry(key, value.toString())))
        .toString();
  }

  String getWallpaperAssetUrl(String url) {
    final raw = url.trim();
    if (raw.isEmpty) return '';
    final resolved = _resolveWithBaseUrl(raw);
    if (resolved.isEmpty) return '';
    return getAuthedUrl(resolved);
  }

  String _resolveWithBaseUrl(String url) {
    final raw = url.trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }
    final base = _state.baseUrl.trim();
    if (base.isEmpty) return raw;
    if (base.endsWith('/') && raw.startsWith('/')) {
      return '${base.substring(0, base.length - 1)}$raw';
    }
    if (!base.endsWith('/') && !raw.startsWith('/')) {
      return '$base/$raw';
    }
    return '$base$raw';
  }

  void refreshFaceImageTimestamp() {
    faceImageTimestamp = DateTime.now().millisecondsSinceEpoch;
  }

  String getFaceImageUrl({
    required int faceId,
    String? fileHash,
    int size = 240,
    int quality = 85,
  }) {
    // 构建参数Map
    final Map<String, dynamic> params = {};
    params['face_id'] = faceId.toString();
    if (fileHash != null && fileHash.trim().isNotEmpty) {
      params['file_hash'] = fileHash.trim();
    }
    params['size'] = size.toString();
    params['quality'] = quality.toString();
    params['t'] = faceImageTimestamp.toString();
    if (_state.accessToken != null) {
      params['accessToken'] = _state.accessToken;
    }
    // 加密参数
    final aesParam = _encryptParams(params);
    return '${_state.baseUrl}/api/photo/face/image?aes=${Uri.encodeComponent(aesParam)}';
  }

  String getFaceDownloadUrl(List<int> faceIds) {
    final ids = faceIds.where((e) => e > 0).toSet().toList()..sort();
    final name = ids.length == 1
        ? 'face_${ids.first}.zip'
        : 'faces_${ids.length}.zip';
    final Map<String, dynamic> params = {};
    params['face_ids'] = ids.join(',');
    if (_state.accessToken != null) {
      params['accessToken'] = _state.accessToken!;
    }
    final aesParam = _encryptParams(params);
    if (aesParam.isNotEmpty) {
      return '${_state.baseUrl}/api/photo/face/download/$name?aes=${Uri.encodeComponent(aesParam)}';
    }
    final qp = <String, String>{
      'face_ids': ids.join(','),
      if (_state.accessToken != null) 'accessToken': _state.accessToken!,
    };
    final uri = Uri.parse(
      '${_state.baseUrl}/api/photo/face/download/$name',
    ).replace(queryParameters: qp);
    return uri.toString();
  }

  String getAlbumDownloadUrl(List<int> albumIds) {
    final ids = albumIds.where((e) => e > 0).toSet().toList()..sort();
    final name = ids.length == 1
        ? 'album_${ids.first}.zip'
        : 'albums_${ids.length}.zip';
    final Map<String, dynamic> params = {};
    params['album_ids'] = ids.join(',');
    if (_state.accessToken != null) {
      params['accessToken'] = _state.accessToken!;
    }
    final aesParam = _encryptParams(params);
    if (aesParam.isNotEmpty) {
      return '${_state.baseUrl}/api/photo/album/download/$name?aes=${Uri.encodeComponent(aesParam)}';
    }
    final qp = <String, String>{
      'album_ids': ids.join(','),
      if (_state.accessToken != null) 'accessToken': _state.accessToken!,
    };
    final uri = Uri.parse(
      '${_state.baseUrl}/api/photo/album/download/$name',
    ).replace(queryParameters: qp);
    return uri.toString();
  }

  String getVideoPersonImageUrl({
    required String tmdbId,
    int size = 240,
    String? thumb,
  }) {
    final id = tmdbId.trim();
    final th = (thumb ?? '').trim();
    final Map<String, dynamic> params = {};
    params['tmdb_id'] = id;
    params['size'] = size.toString();
    if (th.isNotEmpty) params['thumb'] = th;
    if (_state.accessToken != null) {
      params['accessToken'] = _state.accessToken!;
    }
    final aesParam = _encryptParams(params);
    if (aesParam.isNotEmpty) {
      return '${_state.baseUrl}/api/video/person/image?aes=${Uri.encodeComponent(aesParam)}';
    }
    final qp = <String, String>{
      'tmdb_id': id,
      'size': size.toString(),
      if (th.isNotEmpty) 'thumb': th,
      if (_state.accessToken != null) 'accessToken': _state.accessToken!,
    };
    final uri = Uri.parse(
      '${_state.baseUrl}/api/video/person/image',
    ).replace(queryParameters: qp);
    return uri.toString();
  }

  String getVideoPosterImageUrl({
    required String tmdbId,
    required String mediaType,
    int size = 342,
    String? thumb,
  }) {
    final id = tmdbId.trim();
    final mt = mediaType.trim();
    final th = (thumb ?? '').trim();
    final Map<String, dynamic> params = {};
    params['tmdb_id'] = id;
    params['media_type'] = mt;
    params['size'] = size.toString();
    if (th.isNotEmpty) params['thumb'] = th;
    if (_state.accessToken != null) {
      params['accessToken'] = _state.accessToken!;
    }
    final aesParam = _encryptParams(params);
    if (aesParam.isNotEmpty) {
      return '${_state.baseUrl}/api/video/poster/image?aes=${Uri.encodeComponent(aesParam)}';
    }
    final qp = <String, String>{
      'tmdb_id': id,
      'media_type': mt,
      'size': size.toString(),
      if (th.isNotEmpty) 'thumb': th,
      if (_state.accessToken != null) 'accessToken': _state.accessToken!,
    };
    final uri = Uri.parse(
      '${_state.baseUrl}/api/video/poster/image',
    ).replace(queryParameters: qp);
    return uri.toString();
  }

  /// 获取文件的原始文件URL
  String getRawFileUrl(
    String filePath, {
    bool withAccessToken = false,
    String? accessTokenOverride,
    bool isRawFile = true,
    int? size,
    String? p2pChannel,
    String? code,
  }) {
    // 构建参数Map
    final Map<String, dynamic> params = {};
    params['path'] = filePath;
    final token = (accessTokenOverride ?? _state.accessToken)?.trim();
    if (withAccessToken && token != null && token.isNotEmpty) {
      params['accessToken'] = token;
    }
    if (size != null) {
      params['size'] = size.toString();
    }
    if (isRawFile) {
      params['raw'] = '1';
    }
    final c = (code ?? '').trim();
    if (c.isNotEmpty) {
      params['code'] = c;
    }
    // 加密参数
    final aesParam = _encryptParams(params);
    // 如果加密成功，使用aes参数；否则回退到明文（或处理错误）
    if (aesParam.isNotEmpty) {
      var url =
          '${_state.baseUrl}/api/file/rawFile?aes=${Uri.encodeComponent(aesParam)}';
      if (_state.baseUrl.trim() == ApiController.p2pBaseUrl) {
        url += '&path=${Uri.encodeComponent(filePath)}';
        final mark = (p2pChannel ?? 'file').trim();
        if (mark.isNotEmpty) {
          url += '&p2pChannel=${Uri.encodeComponent(mark)}';
        }
        if (isRawFile) {
          url += '&raw=1';
        }
        if (c.isNotEmpty) {
          url += '&code=${Uri.encodeComponent(c)}';
        }
        if (withAccessToken && token != null && token.isNotEmpty) {
          url += '&accessToken=${Uri.encodeComponent(token)}';
        }
        if (size != null) {
          url += '&size=${Uri.encodeComponent(size.toString())}';
        }
      }
      return url;
    }
    var url =
        '${_state.baseUrl}/api/file/rawFile?path=${Uri.encodeComponent(filePath)}';
    if (_state.baseUrl.trim() == ApiController.p2pBaseUrl) {
      final mark = (p2pChannel ?? 'file').trim();
      if (mark.isNotEmpty) {
        url += '&p2pChannel=${Uri.encodeComponent(mark)}';
      }
    }
    if (isRawFile) {
      url += '&raw=1';
    }
    if (c.isNotEmpty) {
      url += '&code=${Uri.encodeComponent(c)}';
    }
    if (withAccessToken && token != null && token.isNotEmpty) {
      url += '&accessToken=${Uri.encodeComponent(token)}';
    }
    if (size != null) {
      url += '&size=${Uri.encodeComponent(size.toString())}';
    }
    return url;
  }

  String getMusicTranscodeUrl(
    String filePath, {
    bool withAccessToken = true,
    String? accessTokenOverride,
    String? p2pChannel,
  }) {
    final Map<String, dynamic> params = {};
    params['path'] = filePath;
    final token = (accessTokenOverride ?? _state.accessToken)?.trim();
    if (withAccessToken && token != null && token.isNotEmpty) {
      params['accessToken'] = token;
    }
    final aesParam = _encryptParams(params);
    if (aesParam.isNotEmpty) {
      var url =
          '${_state.baseUrl}/api/music/transcode?aes=${Uri.encodeComponent(aesParam)}';
      if (_state.baseUrl.trim() == ApiController.p2pBaseUrl) {
        url += '&path=${Uri.encodeComponent(filePath)}';
        final mark = (p2pChannel ?? 'music').trim();
        if (mark.isNotEmpty) {
          url += '&p2pChannel=${Uri.encodeComponent(mark)}';
        }
        if (withAccessToken && token != null && token.isNotEmpty) {
          url += '&accessToken=${Uri.encodeComponent(token)}';
        }
      }
      return url;
    }

    var url =
        '${_state.baseUrl}/api/music/transcode?path=${Uri.encodeComponent(filePath)}';
    if (_state.baseUrl.trim() == ApiController.p2pBaseUrl) {
      final mark = (p2pChannel ?? 'music').trim();
      if (mark.isNotEmpty) {
        url += '&p2pChannel=${Uri.encodeComponent(mark)}';
      }
    }
    if (withAccessToken && token != null && token.isNotEmpty) {
      url += '&accessToken=${Uri.encodeComponent(token)}';
    }
    return url;
  }

  String getOfficePreviewUrl({required String filePath, required String type}) {
    final base = _state.baseUrl.trim();
    final p = filePath.trim();
    if (base.isEmpty || p.isEmpty) return '';

    final t = type.trim().toLowerCase();
    final endpoint = switch (t) {
      'docx' => '/web/viewer/docx.html',
      'xlsx' => '/web/viewer/excel.html',
      'pdf' => '/web/viewer/pdf.html',
      _ => '',
    };
    if (endpoint.isEmpty) return '';

    final fileUrl = getRawFileUrl(p, withAccessToken: true, isRawFile: true);
    final uri = Uri.parse(
      '$base$endpoint',
    ).replace(queryParameters: <String, String>{'fileUrl': fileUrl});
    return uri.toString();
  }

  String? getWallPapperUrl() {
    final wp = CurrentUserController.instance.wallpaper;
    final raw = wp?.url?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    final resolved = _resolveWithBaseUrl(raw);
    if (resolved.isEmpty) return null;
    return getAuthedUrl(resolved);
  }

  /// 壁纸静态资源由 [authenticateJWT] 校验 Bearer，无需在 URL 中嵌入 aes/accessToken。
  String? getWallpaperResolvedUrl() {
    final wp = CurrentUserController.instance.wallpaper;
    final raw = wp?.url?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    final resolved = _resolveWithBaseUrl(raw);
    if (resolved.isEmpty) return null;
    return resolved;
  }

  /// 加密参数
  String _encryptParams(Map<String, dynamic> params) {
    final serverId = _state.serverId;
    if (serverId.isEmpty) {
      return '';
    }

    try {
      // 使用SHA-256处理serverId作为密钥
      final keyBytes = sha256.convert(utf8.encode(serverId)).bytes;
      final key = encrypt.Key(Uint8List.fromList(keyBytes));

      final jsonStr = jsonEncode(params);

      // 使用参数内容的哈希前16位作为IV，保证由于内容相同时URL一致，避免UI重复刷新
      // 之前使用 fromSecureRandom(16) 会导致每次生成的URL都不同，引起图片闪烁
      final ivBytes = sha256.convert(utf8.encode(jsonStr)).bytes.sublist(0, 16);
      final iv = encrypt.IV(Uint8List.fromList(ivBytes));

      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );

      final encrypted = encrypter.encrypt(jsonStr, iv: iv);

      // 组合IV和密文 (IV + Ciphertext)
      final combined = Uint8List.fromList(iv.bytes + encrypted.bytes);
      return base64Encode(combined);
    } catch (e) {
      print('加密失败: $e');
      return '';
    }
  }

  /// [shell] 仅当服务器为 win32 时生效，如 'powershell' | 'cmd'，默认 powershell
  String getTerminalConnectUrl({
    int cols = 100,
    int rows = 30,
    String? shell,
    String? clientDeviceId,
    String? terminalSlotId,
    String? terminalConnId,
    bool forceNew = false,
  }) {
    final base = _state.baseUrl.trim();
    if (base.isEmpty) return '';

    final token = (_state.accessToken ?? '').trim();
    final safeCols = cols < 20 ? 20 : (cols > 400 ? 400 : cols);
    final safeRows = rows < 5 ? 5 : (rows > 200 ? 200 : rows);

    final Map<String, dynamic> params = {
      'cols': safeCols.toString(),
      'rows': safeRows.toString(),
      if (token.isNotEmpty) 'accessToken': token,
      if (shell != null && shell.isNotEmpty) 'shell': shell,
      if (clientDeviceId != null && clientDeviceId.isNotEmpty)
        'clientDeviceId': clientDeviceId,
      if (terminalSlotId != null && terminalSlotId.isNotEmpty)
        'terminalSlotId': terminalSlotId,
      if (terminalConnId != null && terminalConnId.isNotEmpty)
        'terminalConnId': terminalConnId,
      if (forceNew) 'forceNew': '1',
    };

    final aesParam = _encryptParams(params);

    Uri wsBase;
    if (kIsWeb) {
      // Web 端：开发模式下运行地址与服务器地址不同，用 baseUrl（如 127.0.0.1:9000）；否则从地址栏取
      if (kDebugMode && base.isNotEmpty) {
        Uri baseUri;
        try {
          baseUri = Uri.parse(base);
        } catch (_) {
          return '';
        }
        final scheme = baseUri.scheme == 'https' ? 'wss' : 'ws';
        final port = baseUri.hasPort
            ? baseUri.port
            : (scheme == 'wss' ? 443 : 80);
        wsBase = Uri(scheme: scheme, host: baseUri.host, port: port, path: '');
      } else {
        final scheme = Uri.base.scheme == 'https' ? 'wss' : 'ws';
        final port = Uri.base.hasPort
            ? Uri.base.port
            : (scheme == 'wss' ? 443 : 80);
        wsBase = Uri(scheme: scheme, host: Uri.base.host, port: port, path: '');
      }
    } else {
      // 非 Web 端：登录接口返回了 https 端口时，用 wss + 该端口；否则用 baseUrl 的协议与端口
      Uri baseUri;
      try {
        baseUri = Uri.parse(base);
      } catch (_) {
        return '';
      }
      final httpsPortStr = (_state.httpsPort ?? '').trim();
      if (httpsPortStr.isNotEmpty) {
        final port = int.tryParse(httpsPortStr) ?? 443;
        wsBase = baseUri.replace(
          scheme: 'wss',
          port: port,
          path: '',
          query: '',
          fragment: null,
        );
      } else {
        final useTls = baseUri.scheme == 'https';
        final wsScheme = useTls ? 'wss' : 'ws';
        final port = baseUri.hasPort ? baseUri.port : (useTls ? 443 : 80);
        wsBase = baseUri.replace(
          scheme: wsScheme,
          port: port,
          path: '',
          query: '',
          fragment: null,
        );
      }
    }

    if (aesParam.isNotEmpty) {
      final uri = wsBase.replace(
        path: '/api/terminal/connect',
        queryParameters: {'aes': aesParam},
      );
      return uri.toString();
    }

    final uri = wsBase.replace(
      path: '/api/terminal/connect',
      queryParameters: {
        'cols': safeCols.toString(),
        'rows': safeRows.toString(),
        if (token.isNotEmpty) 'accessToken': token,
        if (shell != null && shell.isNotEmpty) 'shell': shell,
        if (clientDeviceId != null && clientDeviceId.isNotEmpty)
          'clientDeviceId': clientDeviceId,
        if (terminalSlotId != null && terminalSlotId.isNotEmpty)
          'terminalSlotId': terminalSlotId,
        if (terminalConnId != null && terminalConnId.isNotEmpty)
          'terminalConnId': terminalConnId,
        if (forceNew) 'forceNew': '1',
      },
    );
    return uri.toString();
  }

  /// 获取文件下载URL
  String getDownloadUrl(List<String> paths) {
    // 构建参数Map
    final Map<String, dynamic> params = {};
    if (paths.length == 1) {
      params['path'] = paths.first;
    } else {
      params['paths'] = paths;
    }

    if (_state.accessToken != null) {
      params['accessToken'] = _state.accessToken;
    }
    print(params);
    // 加密参数
    final aesParam = _encryptParams(params);

    // 如果加密成功，使用aes参数；否则回退到明文（或处理错误）
    if (aesParam.isNotEmpty) {
      var url =
          '$baseUrl/api/file/download?aes=${Uri.encodeComponent(aesParam)}';
      if (baseUrl.trim() == ApiController.p2pBaseUrl) {
        url += '&p2pChannel=download';
      }
      return url;
    }

    // Fallback logic (original implementation)
    String url;
    if (paths.length == 1) {
      url =
          '$baseUrl/api/file/download?path=${Uri.encodeComponent(paths.first)}';
    } else {
      final query = paths
          .map((p) => 'paths=${Uri.encodeComponent(p)}')
          .join('&');
      url = '$baseUrl/api/file/download?$query';
    }

    if (_state.accessToken != null) {
      url += '&accessToken=${_state.accessToken}';
    }
    if (baseUrl.trim() == ApiController.p2pBaseUrl) {
      url += '&p2pChannel=download';
    }
    return url;
  }

  /// 获取HLS转码播放URL
  String getHlsTranscodeUrl(
    String filePath,
    String playId, {
    int seek = 0,
    int? width,
    String? bitrate,
    int? audioIndex,
    int? subtitleIndex,
    bool subtitleBurn = false,
  }) {
    final baseUrl = ApiController.instance.baseUrl;
    final token = ApiController.instance.accessToken;

    final query = <String, String>{
      'filePath': filePath,
      'playId': playId,
      'seek': seek.toString(),
      if (width != null) 'width': width.toString(),
      if (bitrate != null) 'bitrate': bitrate,
      if (audioIndex != null) 'audioIndex': audioIndex.toString(),
      if (subtitleIndex != null) 'subtitleIndex': subtitleIndex.toString(),
      'subtitleBurn': subtitleBurn.toString(),
    };
    //添加web标记
    if (kIsWeb) {
      query['client'] = 'web';
    }
    // Add token if needed (for HLS m3u8 request itself)
    if (token != null) {
      query['accessToken'] = token;
    }

    final uri = Uri.parse(
      '$baseUrl/api/videoPlayer/transcode',
    ).replace(queryParameters: query);
    return uri.toString();
  }

  /// 获取 merge LVP (OPPO 实况照片) 嵌入视频的提取播放 URL
  String getMergeLvpVideoUrl(String filePath, {bool withAccessToken = true}) {
    final p = filePath.trim();
    if (p.isEmpty) return '';
    final token = (withAccessToken ? _state.accessToken : null)?.trim();
    var url =
        '${_state.baseUrl}/api/file/mergeLvpVideo?path=${Uri.encodeComponent(p)}';
    if (token != null && token.isNotEmpty) {
      url += '&accessToken=${Uri.encodeComponent(token)}';
    }
    return url;
  }

  /// 获取视频转 MP4 流式播放 URL（用于 Web 或源格式不支持时，如 Live Photo 视频）
  String getVideoStreamMp4Url(String filePath, {bool withAccessToken = true}) {
    final p = filePath.trim();
    if (p.isEmpty) return '';
    final token = (withAccessToken ? _state.accessToken : null)?.trim();
    var url =
        '${_state.baseUrl}/api/videoPlayer/stream-mp4?filePath=${Uri.encodeComponent(p)}';
    if (token != null && token.isNotEmpty) {
      url += '&accessToken=${Uri.encodeComponent(token)}';
    }
    return url;
  }
}
