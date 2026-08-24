part of '../file_controller.dart';

final RegExp _fileNameNaturalSplitRe = RegExp(r'\d+|\D+');

extension FileControllerSort on FileController {
  int _naturalFileNameCompare(String a, String b) {
    if (identical(a, b)) return 0;
    if (a.isEmpty) return b.isEmpty ? 0 : -1;
    if (b.isEmpty) return 1;

    final al = a.toLowerCase();
    final bl = b.toLowerCase();

    final ap = _fileNameNaturalSplitRe
        .allMatches(al)
        .map((m) => m.group(0) ?? '')
        .toList(growable: false);
    final bp = _fileNameNaturalSplitRe
        .allMatches(bl)
        .map((m) => m.group(0) ?? '')
        .toList(growable: false);

    bool isDigits(String s) => s.isNotEmpty && s.codeUnits.every((c) => c >= 48 && c <= 57);

    int cmpDigits(String x, String y) {
      final xn0 = x.replaceFirst(RegExp(r'^0+'), '');
      final yn0 = y.replaceFirst(RegExp(r'^0+'), '');
      final xn = xn0.isEmpty ? '0' : xn0;
      final yn = yn0.isEmpty ? '0' : yn0;

      if (xn.length != yn.length) return xn.length.compareTo(yn.length);
      final c = xn.compareTo(yn);
      if (c != 0) return c;
      return x.length.compareTo(y.length);
    }

    final len = ap.length < bp.length ? ap.length : bp.length;
    for (var i = 0; i < len; i++) {
      final as = ap[i];
      final bs = bp[i];
      if (as == bs) continue;

      final aNum = isDigits(as);
      final bNum = isDigits(bs);
      if (aNum && bNum) {
        final c = cmpDigits(as, bs);
        if (c != 0) return c;
        continue;
      }
      if (aNum != bNum) return aNum ? -1 : 1;

      final c = as.compareTo(bs);
      if (c != 0) return c;
    }

    if (ap.length != bp.length) return ap.length.compareTo(bp.length);

    final c2 = a.compareTo(b);
    if (c2 != 0) return c2;
    return a.length.compareTo(b.length);
  }

  void setSortMode(String mode) {
    sortMode.value = mode;
    if (currentModule.value != 'recent') {
      applySort();
    }
    _saveSortMode(mode);
  }

  /// 设置视图模式（移动端：图标/大图标/列表；PC端未来也可复用）
  void setViewMode(String mode) {
    viewMode.value = mode;
    _saveViewMode(mode);
  }

  void applySort() {
    final mode = sortMode.value;
    final sorted = [...items];
    int cmpByName(Map<String, dynamic> a, Map<String, dynamic> b) {
      final an = a['name']?.toString() ?? '';
      final bn = b['name']?.toString() ?? '';
      return _naturalFileNameCompare(an, bn);
    }

    int cmpBySize(Map<String, dynamic> a, Map<String, dynamic> b) {
      final as = (a['size'] as int?) ?? -1;
      final bs = (b['size'] as int?) ?? -1;
      return as.compareTo(bs);
    }

    int cmpByMtime(Map<String, dynamic> a, Map<String, dynamic> b) {
      final am = (a['mtimeMs'] as num?)?.toInt() ?? 0;
      final bm = (b['mtimeMs'] as num?)?.toInt() ?? 0;
      return am.compareTo(bm);
    }

    int cmpByType(Map<String, dynamic> a, Map<String, dynamic> b) {
      final at = a['type']?.toString() ?? '';
      final bt = b['type']?.toString() ?? '';
      return at.compareTo(bt);
    }

    int Function(Map<String, dynamic>, Map<String, dynamic>) selector;
    bool desc = false;
    switch (mode) {
      case 'name_desc':
        selector = cmpByName;
        desc = true;
        break;
      case 'size_asc':
        selector = cmpBySize;
        break;
      case 'size_desc':
        selector = cmpBySize;
        desc = true;
        break;
      case 'mtime_asc':
        selector = cmpByMtime;
        break;
      case 'mtime_desc':
        selector = cmpByMtime;
        desc = true;
        break;
      case 'type_asc':
        selector = cmpByType;
        break;
      case 'type_desc':
        selector = cmpByType;
        desc = true;
        break;
      case 'name_asc':
      default:
        selector = cmpByName;
        break;
    }
    sorted.sort((a, b) {
      final c = selector(a, b);
      return desc ? -c : c;
    });
    items.assignAll(sorted);
  }

  Future<void> _loadSortMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(FileController._sortKey);
      if (v != null && v.isNotEmpty) {
        sortMode.value = v;
        applySort();
      }
    } catch (_) {}
  }

  Future<void> _saveSortMode(String mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(FileController._sortKey, mode);
    } catch (_) {}
  }

  Future<void> _loadViewMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(FileController._viewKey);
      if (v != null && v.isNotEmpty) {
        viewMode.value = v;
      }
    } catch (_) {}
  }

  Future<void> _saveViewMode(String mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(FileController._viewKey, mode);
    } catch (_) {}
  }

  Future<void> _loadShowHidden() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool(FileController._showHiddenKey);
      if (v == null) return;
      if (showHidden.value == v) return;
      showHidden.value = v;
      // autoLoadRoot=false 时首次列表由页面 postFrame 触发；此时 currentPath 仍为 null，
      // refreshPage 会把 base 当成 '' 去拉根目录，与子目录首屏请求竞态。
      if (currentPath.value == null && !autoLoadRoot) return;
      await refreshPage();
    } catch (_) {}
  }

  Future<void> _saveShowHidden(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(FileController._showHiddenKey, value);
    } catch (_) {}
  }

  Future<void> toggleShowHidden() async {
    showHidden.value = !showHidden.value;
    await _saveShowHidden(showHidden.value);
    await refreshPage();
  }
}
