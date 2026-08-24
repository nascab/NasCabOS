part of '../file_controller.dart';

extension FileControllerOpen on FileController {
  /// Web：开发时为 /assets/web/...，打包后为 /assets/assets/web/...，按模式区分。
  String _webAssetUrl(String assetPath) {
    final p = assetPath.trim();
    if (p.isEmpty) return Uri.base.resolve('').toString();
    String normalized = p.startsWith('/') ? p.substring(1) : p;
    if (kIsWeb && kReleaseMode && normalized.startsWith('assets/web/')) {
      normalized = 'assets/$normalized';
    }
    return Uri.base.resolve(normalized).toString();
  }

  String _proxyUrlToLocal(Uri localBase, String remoteUrl) {
    final u = Uri.parse(remoteUrl);
    return localBase.replace(path: u.path, query: u.query).toString();
  }

  Future<({String url, bool needsRelease})> _buildEbookReaderUrl({
    required String remoteFileUrl,
    required String lang,
    required String accessToken,
    String? fileHash,
    String? fileName,
  }) async {
    final qp = <String, String>{
      'url': remoteFileUrl,
      'lang': lang,
      'accessToken': accessToken,
      if ((fileHash ?? '').trim().isNotEmpty) 'file_hash': fileHash!.trim(),
      if ((fileName ?? '').trim().isNotEmpty) 'filename': fileName!.trim(),
    };

    if (DeviceUtils.isWeb) {
      final apiBase = ApiController.instance.baseUrl.trim();
      if (apiBase.isNotEmpty) qp['apiBase'] = apiBase;
      // 实际 URL 由 _webAssetUrl 按 debug/release 区分（release 为 /assets/assets/web/...）
      return (
        url: Uri.parse(
          _webAssetUrl('/assets/web/reader/reader.html'),
        ).replace(queryParameters: qp).toString(),
        needsRelease: false,
      );
    }

    final localBase = await LocalWebAssetServer.instance.acquire();
    final proxied = _proxyUrlToLocal(localBase, remoteFileUrl);
    qp['url'] = proxied;
    qp['apiBase'] = localBase.toString();
    return (
      url: localBase
          .replace(path: '/reader/reader.html', queryParameters: qp)
          .toString(),
      needsRelease: true,
    );
  }

  Future<({String url, bool needsRelease})> _buildOfficeViewerUrl({
    required String officeType,
    required String remoteFileUrl,
  }) async {
    final t = officeType.trim().toLowerCase();
    final endpoint = switch (t) {
      'docx' => '/web/viewer/docx.html',
      'xlsx' => '/web/viewer/excel.html',
      _ => '',
    };
    if (endpoint.isEmpty) return (url: '', needsRelease: false);

    if (DeviceUtils.isWeb) {
      final fileName = endpoint.substring('/web/viewer/'.length);
      final pageUrl = _webAssetUrl('/assets/web/viewer/$fileName');
      return (
        url: Uri.parse(pageUrl)
            .replace(
              queryParameters: <String, String>{'fileUrl': remoteFileUrl},
            )
            .toString(),
        needsRelease: false,
      );
    }

    final localBase = await LocalWebAssetServer.instance.acquire();
    final proxied = _proxyUrlToLocal(localBase, remoteFileUrl);
    return (
      url: localBase
          .replace(path: endpoint, queryParameters: {'fileUrl': proxied})
          .toString(),
      needsRelease: true,
    );
  }

  String _normalizeExt(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.startsWith('.')) s = s.substring(1);
    return s;
  }

  String _extForItem(Map<String, dynamic> item) {
    final extRaw = item['ext']?.toString() ?? '';
    final ext = _normalizeExt(extRaw);
    if (ext.isNotEmpty) return ext;

    final name = item['name']?.toString() ?? '';
    final dot = name.lastIndexOf('.');
    if (dot >= 0 && dot < name.length - 1) {
      return _normalizeExt(name.substring(dot + 1));
    }
    return '';
  }

  bool _isEbookItem(Map<String, dynamic> item) {
    if (item['type']?.toString() == 'dir') return false;
    final ext = _extForItem(item);
    return ext == 'epub' || ext == 'mobi' || ext == 'azw3';
  }

  String _officeTypeForItem(Map<String, dynamic> item) {
    if (item['type']?.toString() == 'dir') return '';
    final rawType = item['type']?.toString().trim().toLowerCase() ?? '';
    if (rawType == 'docx' || rawType == 'xlsx') {
      return rawType;
    }
    final ext = _extForItem(item);
    if (ext == 'docx' || ext == 'xlsx') return ext;
    return '';
  }

  bool _isPdfItem(Map<String, dynamic> item) {
    if (item['type']?.toString() == 'dir') return false;
    final ext = _extForItem(item);
    return ext == 'pdf';
  }

  bool _isTxtItem(Map<String, dynamic> item) {
    if (item['type']?.toString() == 'dir') return false;
    return _extForItem(item) == 'txt';
  }

  bool _isTextItem(Map<String, dynamic> item) {
    if (item['type']?.toString() == 'dir') return false;
    final ext = _extForItem(item);
    const textExts = <String>{
      'txt',
      'md',
      'markdown',
      'vue',
      'properties',
      'js',
      'jsx',
      'ts',
      'tsx',
      'py',
      'dart',
      'java',
      'c',
      'cc',
      'cpp',
      'h',
      'hpp',
      'go',
      'rs',
      'php',
      'rb',
      'lua',
      'sql',
      'toml',
      'env',
      'gradle',
      'kt',
      'swift',
      'scss',
      'less',
      'svelte',
      'gitignore',
      'json',
      'yaml',
      'yml',
      'xml',
      'html',
      'css',
      'sh',
      'log',
      'ini',
      'conf',
    };
    return textExts.contains(ext);
  }

  bool _isArchiveItem(Map<String, dynamic> item) {
    if (item['type']?.toString() == 'dir') return false;
    final ext = _extForItem(item);
    return ext == 'zip' || ext == 'rar' || ext == 'tar';
  }

  String _basenameFromPath(String path) {
    final idx = path.lastIndexOf('/');
    if (idx < 0) return path;
    if (idx >= path.length - 1) return path;
    return path.substring(idx + 1);
  }

  String _editorWindowIdForPath(String path) {
    final digest = md5.convert(utf8.encode(path)).toString();
    return 'editor_${digest.substring(0, 12)}';
  }

  Future<void> _openTextEditorFromItem(Map<String, dynamic> item) async {
    final path = item['path']?.toString() ?? '';
    if (path.trim().isEmpty) {
      ToastUtil.show('operation_failed'.tr);
      return;
    }

    final sizeValue = item['size'];
    final size = (sizeValue is num)
        ? sizeValue.toInt()
        : int.tryParse(sizeValue?.toString() ?? '') ?? 0;
    const maxBytes = 80 * 1024;
    if (size > maxBytes) {
      ToastUtil.show('editor_file_too_large'.tr);
      return;
    }

    if (DeviceUtils.isDesktop && Get.isRegistered<PcHomeController>()) {
      final home = Get.find<PcHomeController>();
      final windowId = _editorWindowIdForPath(path);
      final fileName = _basenameFromPath(path);
      home.openApp(
        windowId: windowId,
        viewBuilder: (_) => PcTextEditorView(filePath: path),
        title: '${'editor_window'.tr} - $fileName',
        icon: Image.asset(
          'assets/app_icons/editor.webp',
          errorBuilder: (c, e, s) {
            return const Icon(Icons.apps);
          },
        ),
        initialSize: const Size(980, 720),
        minSize: const Size(520, 360),
      );
    } else {
      Get.to(() => TextEditorPage(filePath: path), preventDuplicates: false);
    }
  }

  Future<void> openTextEditorForItem(Map<String, dynamic> item) async {
    await _openTextEditorFromItem(item);
  }

  Future<void> _openTxtReaderFromItem(Map<String, dynamic> item) async {
    void toast(String message) {
      final ctx = Get.context;
      if (ctx == null) return;
      ToastUtil.show(message);
    }

    final filePath = item['path']?.toString().trim() ?? '';
    if (filePath.isEmpty) {
      toast('operation_failed'.tr);
      return;
    }

    final title = item['name']?.toString().trim();
    final safeTitle = (title == null || title.isEmpty) ? filePath : title;
    final fileName = _basenameFromPath(filePath);

    var fileHash = (item['file_hash'] ?? item['fileHash'] ?? '')
        .toString()
        .trim();
    if (fileHash.isEmpty) {
      fileHash = md5.convert(utf8.encode(filePath)).toString();
    }

    final sizeValue = item['size'];
    final size = (sizeValue is num)
        ? sizeValue.toInt()
        : int.tryParse(sizeValue?.toString() ?? '') ?? 0;

    final scopedRes = await UserApiService.instance.createScopedToken(
      allowApi: const <String>[
        '/api/book/history',
        '/api/book/preference',
        '/api/file/rawFile',
      ],
      allowPath: <String>[filePath],
    );
    if (!scopedRes.success) {
      toast(scopedRes.message ?? 'network_failure'.tr);
      return;
    }

    final scopedToken = scopedRes.data?['accessToken']?.toString().trim() ?? '';
    if (scopedToken.isEmpty) {
      toast('network_failure'.tr);
      return;
    }

    final fileUrl = ApiController.instance.getRawFileUrl(
      filePath,
      withAccessToken: true,
      accessTokenOverride: scopedToken,
      isRawFile: true,
      p2pChannel: 'download',
    );

    if (!DeviceUtils.isWeb) {
      final ok = await BookLocalCacheService.instance.ensureCached(
        fileHash: fileHash,
        fileName: fileName.isNotEmpty ? fileName : safeTitle,
        ext: 'txt',
        remoteUrl: fileUrl,
        expectedSize: size,
      );
      if (!ok) {
        toast('operation_failed'.tr);
        return;
      }
      final cachedPath = BookLocalCacheService.instance.cachedFilePathOf(
        fileHash,
      );
      if (cachedPath != null && cachedPath.trim().isNotEmpty) {
        Get.to(
          () => BookTxtReaderPage(
            fileHash: fileHash,
            title: safeTitle,
            localFilePath: cachedPath,
            expectedSize: size,
          ),
          preventDuplicates: false,
        );
        return;
      }
    }

    Get.to(
      () => BookTxtReaderPage(
        fileHash: fileHash,
        title: safeTitle,
        url: fileUrl,
        expectedSize: size,
      ),
      preventDuplicates: false,
    );
  }

  Future<void> _openEbookFromItem(Map<String, dynamic> item) async {
    void toast(String message) {
      final ctx = Get.context;
      if (ctx == null) return;
      ToastUtil.show(message);
    }

    final filePath = item['path']?.toString().trim() ?? '';
    if (filePath.isEmpty) {
      toast('operation_failed'.tr);
      return;
    }

    final title = item['name']?.toString().trim();
    final safeTitle = (title == null || title.isEmpty) ? filePath : title;
    final fileName = _basenameFromPath(filePath);

    final fileHash = (item['file_hash'] ?? item['fileHash'] ?? '')
        .toString()
        .trim();

    final scopedRes = await UserApiService.instance.createScopedToken(
      allowApi: const <String>[
        '/api/book/history',
        '/api/book/preference',
        '/api/file/rawFile',
      ],
      allowPath: <String>[filePath],
    );
    if (!scopedRes.success) {
      toast(scopedRes.message ?? 'network_failure'.tr);
      return;
    }

    final scopedToken = scopedRes.data?['accessToken']?.toString().trim() ?? '';
    if (scopedToken.isEmpty) {
      toast('network_failure'.tr);
      return;
    }

    final fileUrl = ApiController.instance.getRawFileUrl(
      filePath,
      withAccessToken: true,
      accessTokenOverride: scopedToken,
      isRawFile: true,
      p2pChannel: 'download',
    );
    final lang = LanguageService.to.currentLocale.replaceAll('_', '-');
    final built = await _buildEbookReaderUrl(
      remoteFileUrl: fileUrl,
      lang: lang,
      accessToken: scopedToken,
      fileHash: fileHash,
      fileName: fileName,
    );

    Get.to(
      () => BookWebReaderPage(
        url: built.url,
        title: safeTitle,
        onDispose: built.needsRelease
            ? () => LocalWebAssetServer.instance.release()
            : null,
      ),
      preventDuplicates: false,
    );
  }

  Future<void> _openOfficeFromItem(Map<String, dynamic> item) async {
    void toast(String message) {
      final ctx = Get.context;
      if (ctx == null) return;
      ToastUtil.show(message);
    }

    final filePath = item['path']?.toString().trim() ?? '';
    if (filePath.isEmpty) {
      toast('operation_failed'.tr);
      return;
    }

    final officeType = _officeTypeForItem(item);
    if (officeType.isEmpty) {
      toast('operation_failed'.tr);
      return;
    }

    final title = item['name']?.toString().trim();
    final safeTitle = (title == null || title.isEmpty) ? filePath : title;

    final fileUrl = ApiController.instance.getRawFileUrl(
      filePath,
      withAccessToken: true,
      isRawFile: true,
    );
    final built = await _buildOfficeViewerUrl(
      officeType: officeType,
      remoteFileUrl: fileUrl,
    );
    if (built.url.isEmpty) {
      toast('operation_failed'.tr);
      return;
    }

    Get.to(
      () => BookWebReaderPage(
        url: built.url,
        title: safeTitle,
        onDispose: built.needsRelease
            ? () => LocalWebAssetServer.instance.release()
            : null,
      ),
      preventDuplicates: false,
    );
  }

  Future<void> _openPdfFromItem(Map<String, dynamic> item) async {
    void toast(String message) {
      final ctx = Get.context;
      if (ctx == null) return;
      ToastUtil.show(message);
    }

    final filePath = item['path']?.toString().trim() ?? '';
    if (filePath.isEmpty) {
      toast('operation_failed'.tr);
      return;
    }

    final title = item['name']?.toString().trim();
    final safeTitle = (title == null || title.isEmpty) ? filePath : title;
    final fileHash =
        (item['file_hash'] ?? item['fileHash'] ?? '').toString().trim();
    final sizeValue = item['size'];
    final expectedSize = (sizeValue is num)
        ? sizeValue.toInt()
        : int.tryParse(sizeValue?.toString() ?? '') ?? 0;

    await PdfViewerUtil.openPdfInViewer(
      filePath: filePath,
      title: safeTitle,
      fileHash: fileHash.isNotEmpty ? fileHash : null,
      expectedSize: expectedSize,
    );
  }

  Future<void> _openArchiveFromItem(Map<String, dynamic> item) async {
    void toast(String message) {
      final ctx = Get.context;
      if (ctx == null) return;
      ToastUtil.show(message);
    }

    final filePath = item['path']?.toString().trim() ?? '';
    if (filePath.isEmpty) {
      toast('operation_failed'.tr);
      return;
    }
    final fileHash = (item['file_hash'] ?? item['fileHash'] ?? '')
        .toString()
        .trim();
    final title = item['name']?.toString().trim();
    final safeTitle = (title == null || title.isEmpty) ? filePath : title;

    await Get.dialog(
      _ArchivePreviewDialog(
        archiveFilePath: filePath,
        archiveFileHash: fileHash,
        archiveTitle: safeTitle,
      ),
      barrierDismissible: true,
    );
  }

  Future<void> handleAudioIconTap(Map<String, dynamic> item) async {
    if (!DeviceUtils.isDesktop) return;

    final path = item['path']?.toString() ?? '';
    if (path.isEmpty) return;
    if (!selected.contains(path)) {
      selectOnly(path);
      return;
    }

    final audioExts = <String>{
      'mp3',
      'flac',
      'aac',
      'wav',
      'ogg',
      'opus',
      'wma',
      'ape',
      'm4a'
    };

    String normalizeExt(String raw) {
      var s = raw.trim().toLowerCase();
      if (s.startsWith('.')) s = s.substring(1);
      return s;
    }

    String extFor(Map<String, dynamic> e) {
      final extRaw = e['ext']?.toString() ?? '';
      final ext = normalizeExt(extRaw);
      if (ext.isNotEmpty) return ext;
      final name = e['name']?.toString() ?? '';
      final parts = name.split('.');
      if (parts.length <= 1) return '';
      return normalizeExt(parts.last);
    }

    bool isAudio(Map<String, dynamic> e) {
      if (e['type']?.toString() == 'dir') return false;
      final ext = extFor(e);
      return audioExts.contains(ext);
    }

    final src =
        (searchScope.value != 'current' && searchQuery.value.trim().isNotEmpty)
        ? globalSearchItems
        : items;
    final playlistSrc = src.where(isAudio).toList(growable: false);
    if (playlistSrc.isEmpty) return;

    final startSrcIndex = playlistSrc.indexWhere(
      (e) => (e['path']?.toString() ?? '') == path,
    );
    if (startSrcIndex < 0) return;

    MusicListItem toMusicItem(Map<String, dynamic> e) {
      final name = e['name']?.toString() ?? '';
      final fullPath = e['path']?.toString() ?? '';
      final ext = extFor(e);
      final slash = fullPath.lastIndexOf('/');
      final basePath = slash > 0 ? fullPath.substring(0, slash) : '';
      return MusicListItem(
        id: 0,
        path: basePath,
        filename: name,
        fileHash: '',
        title: '',
        artist: '',
        album: '',
        year: '',
        genre: '',
        duration: 0,
        size: (e['size'] as num?)?.toInt() ?? 0,
        ext: ext,
        hasInnerCover: 0,
        showType: 'file_browser',
        musicCount: 0,
        isFavorite: false,
        isFromFile: true,
        ctime: null,
        mtime: null,
        birthtime: null,
        firstFilePath: '',
        fullPath: fullPath,
        bitrate: null,
        sampleRate: null,
        bitDepth: null,
      );
    }

    final musicPlaylist = playlistSrc.map(toMusicItem).toList(growable: false);
    final startItem = musicPlaylist[startSrcIndex];

    if (Get.isRegistered<PcHomeController>()) {
      final home = Get.find<PcHomeController>();
      home.openApp(
        windowId: 'music',
        viewBuilder: home.builtinAppViewBuilder('music'),
        title: 'app_music'.tr,
        icon: home.buildAppIcon('music'),
      );
    }

    await MusicPlayServiceController.instance.playFromList(
      items: musicPlaylist,
      startItem: startItem,
      autoPlay: true,
    );
  }

  /// 处理文件或文件夹的点击事件
  Future<void> handleItemTap(
    Map<String, dynamic> item,
    List<Map<String, dynamic>> data, {
    bool forceEnter = false,
  }) async {
    print('处理点击事件: $item');
    final virtualType = item['virtualType']?.toString() ?? '';
    if (virtualType == 'custom_add') {
      await _showAddCustomPathDialog();
      return;
    }
    final path = item['path']?.toString() ?? '';
    final type = item['type']?.toString() ?? '';

    final now = DateTime.now();
    final isDouble =
        _lastTappedPath == path &&
        _lastTapAt != null &&
        now.difference(_lastTapAt!).inMilliseconds <= 500;
    _lastTappedPath = path;
    _lastTapAt = now;

    if (isDouble || forceEnter) {
      if (type == 'dir') {
        if (searchScope.value != 'current' &&
            searchQuery.value.trim().isNotEmpty) {
          exitSearchMode();
        }
        await navigateTo(path);
      } else if (type == 'image' || type == 'raw') {
        final images = data
            .where((e) => e['type'] == 'image' || e['type'] == 'raw')
            .toList();
        final index = images.indexOf(item);
        if (index >= 0) {
          // PC端：复用桌面窗口的图片浏览器
          if (DeviceUtils.isDesktop && Get.isRegistered<PcHomeController>()) {
            final homeController = Get.find<PcHomeController>();
            homeController.openImageViewer(images, index);
          } else {
            // App端：使用独立页面打开图片浏览器
            if (!Get.isRegistered<CustomGalleryController>()) {
              Get.put(CustomGalleryController());
            }
            final galleryCtrl = CustomGalleryController.instance;
            galleryCtrl.configure();
            galleryCtrl.isControlsVisible.value = true;
            galleryCtrl.galleryItems = images;
            galleryCtrl.galleryInitialIndex.value = index;
            Get.to(() => const CustomGallery());
          }
        }
      } else if (_isVideo(item)) {
        final videos = data.where((e) => _isVideo(e)).toList();
        final index = videos.indexOf(item);
        if (index >= 0) {
          AppRoutes.toVideoPlayer(playlist: videos, initialIndex: index);
        }
      } else if (_isTxtItem(item)) {
        await _openTxtReaderFromItem(item);
      } else if (_isTextItem(item)) {
        await _openTextEditorFromItem(item);
      } else if (_isEbookItem(item)) {
        await _openEbookFromItem(item);
      } else if (_isPdfItem(item)) {
        await _openPdfFromItem(item);
      } else if (_officeTypeForItem(item).isNotEmpty) {
        await _openOfficeFromItem(item);
      } else if (_isArchiveItem(item)) {
        await _openArchiveFromItem(item);
      }
      return;
    }

    final additive = isAdditiveSelectionActive;
    if (additive) {
      toggleSelect(path);
    } else {
      selectOnly(path);
    }
  }

  Future<void> _showAddCustomPathDialog() async {
    final nameCtrl = TextEditingController();
    final pathCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    bool saving = false;
    String normalizeUiPath(String input) {
      var p = input.trim();
      if (p.isEmpty) return '';
      p = p.replaceAll('\\', '/');
      while (p.length > 1 && p.endsWith('/')) {
        p = p.substring(0, p.length - 1);
      }
      return p;
    }

    final existingNameLower = items
        .where((e) => e['isCustomPath'] == true)
        .map((e) => (e['name']?.toString() ?? '').trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();
    final existingRootPaths = items
        .map((e) => normalizeUiPath(e['path']?.toString() ?? ''))
        .where((e) => e.isNotEmpty)
        .toSet();
    await showDialog<void>(
      context: Get.overlayContext!,
      builder: (context) {
        final theme = Theme.of(context);
        return StatefulBuilder(
          builder: (context, setState) {
            return DialogUtil.createAlertDialog(
              title: Text('file_custom_path_add_title'.tr),
              contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      enabled: !saving,
                      decoration: InputDecoration(
                        labelText: 'file_custom_path_name_label'.tr,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.isEmpty)
                          return 'file_custom_path_name_required'.tr;
                        if (existingNameLower.contains(t.toLowerCase())) {
                          return 'file_custom_path_name_exists'.tr;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: pathCtrl,
                      enabled: !saving,
                      decoration: InputDecoration(
                        labelText: 'file_custom_path_path_label'.tr,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.isEmpty)
                          return 'file_custom_path_path_required'.tr;
                        if (existingRootPaths.contains(normalizeUiPath(t))) {
                          return 'file_custom_path_path_exists'.tr;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'file_custom_path_path_hint'.tr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.65,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(context).pop(),
                  child: Text('cancel'.tr),
                ),
                TextButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false)) {
                            return;
                          }
                          setState(() => saving = true);
                          try {
                            final res = await _api.addCustomPath(
                              name: nameCtrl.text,
                              path: pathCtrl.text,
                              showLoading: false,
                            );
                            if (!res.success) {
                              ToastUtil.show(
                                res.message ?? 'operation_failed'.tr,
                              );
                              return;
                            }
                            if (!context.mounted) return;
                            Navigator.of(context).pop();
                            ToastUtil.show('operation_success'.tr);
                            await listDirectory(
                              '',
                              null,
                              sourceType: currentSourceType.value,
                            );
                          } finally {
                            if (context.mounted) {
                              setState(() => saving = false);
                            }
                          }
                        },
                  child: saving
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : Text('ok'.tr),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void openShareManage({String pageKey = 'share.webdav'}) {
    final key = pageKey.trim().isEmpty ? 'share.webdav' : pageKey.trim();

    if (!DeviceUtils.isDesktop || !Get.isRegistered<PcHomeController>()) {
      Get.toNamed(AppRoutes.fileShareServer, arguments: {'pageKey': key});
      return;
    }

    final home = PcHomeController.instance;
    home.openApp(
      windowId: 'share',
      viewBuilder: (_) => FileShareServerView(initialPageKey: key),
      title: 'app_share'.tr,
      icon: home.buildAppIcon('share'),
    );
  }

  void openQuickShareCreateAt(String targetPath) {
    final p = targetPath.trim();
    if (p.isEmpty) return;

    if (!DeviceUtils.isDesktop || !Get.isRegistered<PcHomeController>()) {
      Get.toNamed(
        AppRoutes.fileShareServer,
        arguments: {'pageKey': 'share.quick', 'quickShareCreatePath': p},
      );
      return;
    }

    final home = PcHomeController.instance;
    home.quickShareCreatePath.value = p;
    home.quickShareCreateNonce.value += 1;
    home.openApp(
      windowId: 'share',
      viewBuilder: (_) =>
          const FileShareServerView(initialPageKey: 'share.quick'),
      title: 'app_share'.tr,
      icon: home.buildAppIcon('share'),
    );
  }
}

class PcWebPreviewView extends StatefulWidget {
  final String url;

  const PcWebPreviewView({super.key, required this.url});

  @override
  State<PcWebPreviewView> createState() => _PcWebPreviewViewState();
}

class DesktopOfficePreviewDialog extends StatefulWidget {
  final String url;
  final String title;

  const DesktopOfficePreviewDialog({
    super.key,
    required this.url,
    required this.title,
  });

  @override
  State<DesktopOfficePreviewDialog> createState() =>
      _DesktopOfficePreviewDialogState();
}

class _DesktopOfficePreviewDialogState
    extends State<DesktopOfficePreviewDialog> {
  WebViewController? _webCtrl;
  bool _loading = true;
  bool _openingExternally = false;
  String _errorText = '';

  bool get _useExternalBrowser => DeviceUtils.isWindows;

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;
    Get.back();
    return true;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    if (_useExternalBrowser) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openInExternalBrowser();
        }
      });
      return;
    }
    _webCtrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _loading = true;
              _errorText = '';
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() {
              _loading = false;
            });
          },
          onWebResourceError: (err) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _errorText = err.description;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _openInExternalBrowser() async {
    if (_openingExternally) return;
    final uri = Uri.tryParse(widget.url);
    if (uri == null) {
      setState(() {
        _loading = false;
        _errorText = 'Invalid URL';
      });
      return;
    }

    setState(() {
      _loading = true;
      _openingExternally = true;
      _errorText = '';
    });

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      if (launched) {
        Get.back();
        return;
      }
      setState(() {
        _loading = false;
        _openingExternally = false;
        _errorText = 'Failed to open in external browser';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _openingExternally = false;
        _errorText = error.toString();
      });
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_useExternalBrowser) {
      return Focus(
        autofocus: true,
        child: Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            width: 420,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  if (_loading) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(
                      'Opening in external browser...',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ] else ...[
                    Text(
                      _errorText.isEmpty
                          ? 'Opening in external browser...'
                          : _errorText,
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Get.back(),
                      child: Text('close'.tr),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Focus(
      autofocus: true,
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.escape): ActivateIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                Get.back();
                return null;
              },
            ),
          },
          child: Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: SizedBox(
              width: 980,
              height: 720,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      border: Border(
                        bottom: BorderSide(
                          color: theme.dividerColor.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: 'close'.tr,
                          onPressed: () => Get.back(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        WebViewWidget(controller: _webCtrl!),
                        if (_loading)
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            child: IgnorePointer(
                              child: LinearProgressIndicator(
                                minHeight: 2,
                                color: theme.colorScheme.primary,
                                backgroundColor: theme.colorScheme.surface
                                    .withValues(alpha: 0.1),
                              ),
                            ),
                          ),
                        if (_errorText.isNotEmpty)
                          Positioned(
                            left: 12,
                            right: 12,
                            bottom: 12,
                            child: Material(
                              color: theme.colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Text(
                                  _errorText,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onErrorContainer,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PcWebPreviewViewState extends State<PcWebPreviewView> {
  WebViewController? _webCtrl;
  bool _loading = true;
  bool _openingExternally = false;
  String _errorText = '';

  bool get _useExternalBrowser => DeviceUtils.isWindows;

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;
    final wid = PcWindowScope.of(context)?.windowId ?? '';
    if (wid.isNotEmpty) {
      PcHomeController.instance.closeApp(wid);
    } else {
      Get.back();
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    if (_useExternalBrowser) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openInExternalBrowser();
        }
      });
      return;
    }
    _webCtrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _loading = true;
              _errorText = '';
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() {
              _loading = false;
            });
          },
          onWebResourceError: (err) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _errorText = err.description;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _openInExternalBrowser() async {
    if (_openingExternally) return;
    final uri = Uri.tryParse(widget.url);
    if (uri == null) {
      setState(() {
        _loading = false;
        _errorText = 'Invalid URL';
      });
      return;
    }

    setState(() {
      _loading = true;
      _openingExternally = true;
      _errorText = '';
    });

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      if (launched) {
        final wid = PcWindowScope.of(context)?.windowId ?? '';
        if (wid.isNotEmpty) {
          PcHomeController.instance.closeApp(wid);
        } else {
          Get.back();
        }
        return;
      }
      setState(() {
        _loading = false;
        _openingExternally = false;
        _errorText = 'Failed to open in external browser';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _openingExternally = false;
        _errorText = error.toString();
      });
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_useExternalBrowser) {
      return Column(
        children: [
          SizedBox(height: PcAppWindow.titleBarHeight),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_loading) ...[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        'Opening in external browser...',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ] else ...[
                      Text(
                        _errorText.isEmpty
                            ? 'Opening in external browser...'
                            : _errorText,
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Focus(
      autofocus: true,
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.escape): ActivateIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                final wid = PcWindowScope.of(context)?.windowId ?? '';
                if (wid.isNotEmpty) {
                  PcHomeController.instance.closeApp(wid);
                } else {
                  Get.back();
                }
                return null;
              },
            ),
          },
          child: Column(
            children: [
              SizedBox(height: PcAppWindow.titleBarHeight),
              Expanded(
                child: Stack(
                  children: [
                    WebViewWidget(
                      controller: _webCtrl!,
                      gestureRecognizers:
                          <Factory<OneSequenceGestureRecognizer>>{
                            Factory<OneSequenceGestureRecognizer>(
                              () => EagerGestureRecognizer(),
                            ),
                          },
                    ),
                    if (_loading)
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        child: IgnorePointer(
                          child: LinearProgressIndicator(
                            minHeight: 2,
                            color: theme.colorScheme.primary,
                            backgroundColor: theme.colorScheme.surface
                                .withValues(alpha: 0.1),
                          ),
                        ),
                      ),
                    if (_errorText.isNotEmpty)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: Material(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Text(
                              _errorText,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArchiveNode {
  _ArchiveNode.dir(this.name, this.innerPath)
    : isDir = true,
      size = 0,
      children = <String, _ArchiveNode>{};

  _ArchiveNode.file(this.name, this.innerPath, this.size)
    : isDir = false,
      children = <String, _ArchiveNode>{};

  final String name;
  final String innerPath;
  final bool isDir;
  int size;
  final Map<String, _ArchiveNode> children;
}

class _ArchivePreviewDialog extends StatefulWidget {
  const _ArchivePreviewDialog({
    required this.archiveFilePath,
    required this.archiveFileHash,
    required this.archiveTitle,
  });

  final String archiveFilePath;
  final String archiveFileHash;
  final String archiveTitle;

  @override
  State<_ArchivePreviewDialog> createState() => _ArchivePreviewDialogState();
}

class _ArchivePreviewDialogState extends State<_ArchivePreviewDialog> {
  final _stack = <_ArchiveNode>[];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = '';
      _stack
        ..clear()
        ..add(_ArchiveNode.dir('', ''));
    });

    final api = FileApiService.instance;
    final body = <String, dynamic>{
      'only_img': false,
      if (widget.archiveFileHash.trim().isNotEmpty)
        'file_hash': widget.archiveFileHash.trim()
      else
        'file_path': widget.archiveFilePath,
    };

    try {
      final res = await api.apiPost<Map<String, dynamic>>(
        '/api/book/archive/list',
        body: body,
        showLoading: false,
      );
      if (!res.success) {
        setState(() {
          _loading = false;
          _error = res.message?.trim().isNotEmpty == true
              ? res.message!.trim()
              : 'archive_load_failed'.tr;
        });
        return;
      }
      final data = res.data ?? <String, dynamic>{};
      final itemsRaw = data['items'];
      final items = <Map<String, dynamic>>[];
      if (itemsRaw is List) {
        for (final e in itemsRaw) {
          if (e is Map) items.add(Map<String, dynamic>.from(e));
        }
      }
      _buildTree(items);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'archive_load_failed'.tr;
      });
    }
  }

  void _buildTree(List<Map<String, dynamic>> files) {
    final root = _stack.first;
    for (final f in files) {
      final rawPath = (f['path'] ?? '').toString();
      var inner = rawPath.replaceAll('\\', '/').trim();
      inner = inner.replaceFirst(RegExp(r'^/+'), '');
      if (inner.isEmpty) continue;

      final sizeRaw = f['size'];
      final size = sizeRaw is num
          ? sizeRaw.toInt()
          : int.tryParse('$sizeRaw') ?? 0;

      final parts = inner.split('/').where((s) => s.trim().isNotEmpty).toList();
      if (parts.isEmpty) continue;

      var current = root;
      var prefix = '';
      for (int i = 0; i < parts.length; i++) {
        final seg = parts[i];
        final isLast = i == parts.length - 1;
        if (isLast) {
          final p = '$prefix$seg';
          final existing = current.children[seg];
          if (existing != null && !existing.isDir) {
            existing.size = size;
          } else if (existing == null) {
            current.children[seg] = _ArchiveNode.file(seg, p, size);
          }
          continue;
        }

        prefix = '$prefix$seg/';
        final existing = current.children[seg];
        if (existing != null && existing.isDir) {
          current = existing;
          continue;
        }
        final dir = _ArchiveNode.dir(seg, prefix);
        current.children[seg] = dir;
        current = dir;
      }
    }
  }

  _ArchiveNode get _current =>
      _stack.isNotEmpty ? _stack.last : _ArchiveNode.dir('', '');

  String _currentPathText() {
    final parts = _stack
        .map((e) => e.name)
        .where((e) => e.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) return '/';
    return '/${parts.join('/')}';
  }

  String _innerBasename(String innerPath) {
    final s = innerPath.replaceAll('\\', '/');
    final idx = s.lastIndexOf('/');
    if (idx < 0) return s;
    if (idx >= s.length - 1) return s;
    return s.substring(idx + 1);
  }

  Future<void> _downloadInnerFile(_ArchiveNode node) async {
    if (node.isDir) return;
    final baseUrl = ApiController.instance.baseUrl;
    final token = ApiController.instance.accessToken;
    final fileName = _innerBasename(node.innerPath);
    final qp = <String, String>{
      'inner_path': node.innerPath,
      'fileName': fileName,
      if (widget.archiveFileHash.trim().isNotEmpty)
        'file_hash': widget.archiveFileHash.trim()
      else
        'file_path': widget.archiveFilePath,
      if (token != null) 'accessToken': token,
    };
    final url = Uri.parse(
      '$baseUrl/api/book/archive/file',
    ).replace(queryParameters: qp).toString();

    if (!Get.isRegistered<DownloadController>()) {
      Get.put(DownloadController(), permanent: true);
    }
    await Get.find<DownloadController>().handleDownload([url]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dialogThemeShape = theme.dialogTheme.shape;
    final BorderRadius dialogRadius = dialogThemeShape is RoundedRectangleBorder
        ? dialogThemeShape.borderRadius.resolve(Directionality.of(context))
        : const BorderRadius.all(Radius.circular(28));
    final media = MediaQuery.of(context);
    final maxWidth = (media.size.width - 32).clamp(320.0, 920.0);
    final maxHeight = (media.size.height - 64).clamp(320.0, 820.0);
    final canUp = _stack.length > 1;

    final entries = _current.children.values.toList(growable: false)
      ..sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return Focus(
      autofocus: true,
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.escape): ActivateIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                if (_stack.length > 1) {
                  setState(() => _stack.removeLast());
                } else {
                  Get.back();
                }
                return null;
              },
            ),
          },
          child: Dialog(
            insetPadding: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: dialogRadius),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: maxHeight,
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.only(
                        topLeft: dialogRadius.topLeft,
                        topRight: dialogRadius.topRight,
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: theme.dividerColor.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (canUp)
                          IconButton(
                            tooltip: 'archive_up'.tr,
                            onPressed: () {
                              if (_stack.length <= 1) return;
                              setState(() => _stack.removeLast());
                            },
                            icon: const Icon(Icons.arrow_upward),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'archive_preview_title'.tr,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${widget.archiveTitle}  ${_currentPathText()}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'close'.tr,
                          onPressed: () => Get.back(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _error.isNotEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _error,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton(
                                    onPressed: _fetch,
                                    child: Text('retry'.tr),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : entries.isEmpty
                        ? Center(
                            child: Text(
                              'archive_empty'.tr,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            itemCount: entries.length,
                            separatorBuilder: (context, index) => Divider(
                              height: 1,
                              color: theme.dividerColor.withValues(alpha: 0.6),
                            ),
                            itemBuilder: (context, index) {
                              final node = entries[index];
                              final iconAsset = node.isDir
                                  ? 'assets/icons/file/folder.png'
                                  : 'assets/icons/file/file.png';
                              final subtitle = node.isDir
                                  ? null
                                  : (node.size > 0
                                        ? FileUtil.formatSize(node.size)
                                        : null);
                              return ListTile(
                                leading: Image.asset(
                                  iconAsset,
                                  width: 22,
                                  height: 22,
                                ),
                                title: Text(
                                  node.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: subtitle == null
                                    ? null
                                    : Text(
                                        subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                trailing: node.isDir
                                    ? const Icon(Icons.chevron_right)
                                    : IconButton(
                                        tooltip: 'download'.tr,
                                        onPressed: () =>
                                            _downloadInnerFile(node),
                                        icon: const Icon(Icons.download),
                                      ),
                                onTap: () async {
                                  if (node.isDir) {
                                    setState(() => _stack.add(node));
                                    return;
                                  }
                                  await _downloadInnerFile(node);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
