part of '../file_controller.dart';

extension FileControllerDirectory on FileController {
  Future<bool> removeCustomPath(String path) async {
    final p = path.trim();
    if (p.isEmpty) return false;
    final res = await _api.removeCustomPath(path: p, showLoading: false);
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return false;
    }
    ToastUtil.show('operation_success'.tr);
    await listDirectory('', null, sourceType: currentSourceType.value);
    return true;
  }

  /// 设置搜索关键字（仅影响本地展示列表，不影响服务端拉取）
  void setSearchQuery(String q) {
    searchQuery.value = q;
    final keyword = q.trim();
    if (keyword.isEmpty) {
      _globalSearchDebounce?.cancel();
      _globalSearchDebounce = null;
      searchScope.value = 'current';
      filterType.value = 'all';
      globalSearchItems.clear();
      globalSearchLoading.value = false;
      return;
    }
    if (searchScope.value != 'current') {
      _scheduleGlobalSearch();
    }
  }

  void exitSearchMode() {
    setSearchQuery('');
    filterType.value = 'all';
  }

  /// 设置筛选类型（仅影响本地展示列表）
  void setFilterType(String type) {
    filterType.value = type;
    if (searchScope.value != 'current' && searchQuery.value.trim().isNotEmpty) {
      _scheduleGlobalSearch();
    }
  }

  void setSearchScope(String scope) {
    final next = scope == 'global'
        ? 'global'
        : scope == 'subtree'
        ? 'subtree'
        : 'current';
    if (searchScope.value == next) return;
    searchScope.value = next;
    if (next == 'current') {
      _globalSearchDebounce?.cancel();
      _globalSearchDebounce = null;
      globalSearchItems.clear();
      globalSearchLoading.value = false;
      return;
    }
    if (searchQuery.value.trim().isNotEmpty) {
      _scheduleGlobalSearch();
    }
  }

  void _scheduleGlobalSearch() {
    _globalSearchDebounce?.cancel();
    _globalSearchDebounce = Timer(const Duration(milliseconds: 280), () async {
      await _performGlobalSearch();
    });
  }

  Future<void> _performGlobalSearch() async {
    final keyword = searchQuery.value.trim();
    if (keyword.isEmpty) return;

    final type = filterType.value;
    final scope = searchScope.value;
    String? mode;
    List<String>? suffixes;
    if (type == 'dir') {
      mode = 'dir';
    } else if (type == 'file') {
      mode = 'file';
    } else if (type == 'image') {
      suffixes = _imageSuffixes;
    } else if (type == 'video') {
      suffixes = _videoSuffixes;
    } else if (type == 'archive') {
      suffixes = _archiveSuffixes;
    } else if (type == 'audio') {
      suffixes = _audioSuffixes;
    } else if (type == 'document') {
      suffixes = _documentSuffixes;
    }

    final rawDir = currentPath.value?.trim() ?? '';
    final dir = (scope == 'subtree' && rawDir.isNotEmpty) ? rawDir : null;

    globalSearchLoading.value = true;
    try {
      final res = await _api.searchGlobal(
        keyword: keyword,
        directory: dir,
        suffixes: suffixes,
        mode: mode,
        limit: 500,
        sourceType: currentSourceType.value,
        apiPath: searchApiPath,
        showLoading: false,
      );
      if (!res.success) {
        globalSearchItems.clear();
        return;
      }
      final data = (res.data ?? {}).cast<String, dynamic>();
      final itemsListRaw = ((data['items'] as List?) ?? [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList(growable: false);
      final uniq = <String, Map<String, dynamic>>{};
      for (final it in itemsListRaw) {
        final p = it['path']?.toString() ?? '';
        if (p.isEmpty) continue;
        uniq.putIfAbsent(p, () => it);
      }
      globalSearchItems.assignAll(uniq.values.toList(growable: false));
    } finally {
      globalSearchLoading.value = false;
    }
  }

  /// 获取用于显示的文件列表（应用搜索与类型筛选）
  List<Map<String, dynamic>> get displayItems {
    final q = searchQuery.value.trim().toLowerCase();
    final list = (searchScope.value != 'current' && q.isNotEmpty)
        ? globalSearchItems.toList(growable: false)
        : items.toList(growable: false);
    final type = filterType.value;

    bool isVideo(Map<String, dynamic> e) {
      final ext = e['ext']?.toString().toLowerCase() ?? '';
      return _videoSuffixes.contains(ext);
    }

    bool isImage(Map<String, dynamic> e) {
      final ext = e['ext']?.toString().toLowerCase() ?? '';
      return _imageSuffixes.contains(ext);
    }

    bool isArchive(Map<String, dynamic> e) {
      final ext = e['ext']?.toString().toLowerCase() ?? '';
      return _archiveSuffixes.contains(ext);
    }

    bool isAudio(Map<String, dynamic> e) {
      final ext = e['ext']?.toString().toLowerCase() ?? '';
      return _audioSuffixes.contains(ext);
    }

    bool isDocument(Map<String, dynamic> e) {
      final ext = e['ext']?.toString().toLowerCase() ?? '';
      return _documentSuffixes.contains(ext);
    }

    final filtered = list
        .where((e) {
          final name = e['name']?.toString().toLowerCase() ?? '';
          final p = e['path']?.toString().toLowerCase() ?? '';
          if (q.isNotEmpty) {
            if (searchScope.value != 'current') {
              if (!name.contains(q)) return false;
            } else {
              if (!(name.contains(q) || p.contains(q))) return false;
            }
          }

          if (type == 'all') return true;
          if (type == 'dir') return e['type'] == 'dir';
          if (type == 'image') return e['type'] == 'image' || isImage(e);
          if (type == 'video') return isVideo(e);
          if (type == 'audio') return isAudio(e);
          if (type == 'document') return isDocument(e);
          if (type == 'archive') return isArchive(e);
          if (type == 'file') return e['type'] != 'dir';
          return true;
        })
        .toList(growable: false);

    final atRoot = (currentPath.value?.trim() ?? '').isEmpty;
    final inNormal = currentModule.value == 'normal';
    if (showRootCustomPathEntry &&
        atRoot &&
        inNormal &&
        q.isEmpty &&
        searchScope.value == 'current') {
      return [
        ...filtered,
        {
          'path': '__custom_path_add__',
          'name': 'file_custom_path_entry'.tr,
          'type': 'dir',
          'virtualType': 'custom_add',
          'mtimeMs': null,
          'size': null,
          'ext': '',
        },
      ];
    }
    return filtered;
  }

  /// 刷新当前页面，根据当前模块重新加载目录列表
  Future<void> refreshPage() async {
    final base = currentPath.value ?? '';
    var source = 'normal';
    if (currentModule.value == 'favorites') {
      source = 'favorites';
    } else if (currentModule.value == 'recent') {
      source = 'recent';
    }
    listDirectory(base, source);
  }

  Future<void> listDirectory(
    String path,
    String? listSource, {
    String? sourceType,
  }) async {
    listSource = listSource ?? 'normal';
    final sourceTypeToUse = listSource == 'normal'
        ? (sourceType ?? currentSourceType.value)
        : null;
    currentSourceType.value = sourceTypeToUse;
    // 进入新目录时清空当前选中状态
    clearSelect();
    final seq = ++_listDirectorySeq;
    loading.value = true;
    try {
      final res = await _api.listDirectory(
        path,
        onlyDir: onlyShowDir.value,
        includeHidden: showHidden.value,
        source: listSource,
        sourceType: sourceTypeToUse,
        apiPath: listApiPath,
      );
      if (seq != _listDirectorySeq) return;
      currentPath.value = (res['base'] as String?) ?? path;
      items.assignAll(
        ((res['items'] as List?) ?? []).cast<Map<String, dynamic>>(),
      );
      segments.assignAll(
        ((res['segments'] as List?) ?? []).cast<Map<String, dynamic>>(),
      );
      sep.value = (res['sep']?.toString()) ?? sep.value;
      if (path == '' && listSource == 'normal') {
        // 更新服务器根目录列表，只包含文件夹
        serverRoots.assignAll(
          ((res['items'] as List?) ?? []).cast<Map<String, dynamic>>(),
        );
      }
      if (listSource != 'recent') {
        applySort();
      }

      // 切换为普通文件列表状态
      currentModule.value = listSource;
      loading.value = false;

      if (path.isNotEmpty && listSource == 'normal') {
        print("开始配置ws链接");
        _fileWatcher.connect(path);
        print("ws链接配置完成");
      } else {
        _fileWatcher.disconnect();
      }

      if (searchScope.value != 'current' &&
          searchQuery.value.trim().isNotEmpty) {
        _scheduleGlobalSearch();
      }
    } catch (e) {
      print("e$e");
      if (seq != _listDirectorySeq) return;
      loading.value = false;
      DialogUtil.showErrorDialog(message: 'operation_failed'.tr);
    }
  }

  Future<void> goUp() async {
    if (segments.isEmpty) {
      await listDirectory('', null, sourceType: currentSourceType.value);
      return;
    }
    if (segments.length <= 1) {
      await listDirectory('', null, sourceType: currentSourceType.value);
      return;
    }
    final parent = segments[segments.length - 2]['path']?.toString() ?? '';
    await listDirectory(parent, null, sourceType: currentSourceType.value);
  }

  Future<void> navigateTo(String path) async {
    await listDirectory(path, null, sourceType: currentSourceType.value);
  }

  bool get isRoot => segments.isEmpty;
}

const _videoSuffixes = [
  '.mov',
  '.mp4',
  '.avi',
  '.rm',
  '.mkv',
  '.f4v',
  '.vob',
  '.mpg',
  '.rmvb',
  '.asf',
  '.mts',
  '.ts',
  '.wmv',
  '.m4v',
  '.m2ts',
  '.ogg',
  '.3gp',
  '.flv',
];

const _imageSuffixes = [
  '.jpeg',
  '.jpg',
  '.png',
  '.heic',
  '.heif',
  '.hif',
  '.gif',
  '.webp',
  '.tiff',
  '.svg',
  '.bmp',
  '.dng',
  '.cr2',
  '.nef',
  '.orf',
  '.raf',
  '.raw',
  '.x3f',
  '.rw2',
  '.nrw',
  '.arw',
];

const _archiveSuffixes = ['.zip', '.rar', '.7z', '.tar', '.gz', '.bz2', '.xz'];

const _audioSuffixes = [
  '.mp3',
  '.flac',
  '.aac',
  '.wav',
  '.ogg',
  '.opus',
  '.wma',
  '.ape',
  '.m4a'
];

const _documentSuffixes = [
  '.pdf',
  '.txt',
  '.md',
  '.doc',
  '.docx',
  '.ppt',
  '.pptx',
  '.xls',
  '.xlsx',
  '.csv',
  '.epub',
  '.mobi',
  '.azw3',
];
