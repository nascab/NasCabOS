import '../../../core/api/base_api_service.dart';

class EditorUserConfig {
  final int fontSize;

  const EditorUserConfig({required this.fontSize});

  static const EditorUserConfig defaults = EditorUserConfig(fontSize: 14);

  factory EditorUserConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return defaults;
    final fontSize =
        int.tryParse(json['fontSize']?.toString() ?? '') ?? defaults.fontSize;
    return EditorUserConfig(fontSize: fontSize);
  }

  Map<String, dynamic> toJson() {
    return {'fontSize': fontSize};
  }
}

class EditorOpenResult {
  final String docId;
  final String path;
  final String text;
  final int rev;
  final int? size;
  final int? mtimeMs;
  final EditorUserConfig config;
  final bool canWrite;

  EditorOpenResult({
    required this.docId,
    required this.path,
    required this.text,
    required this.rev,
    this.size,
    this.mtimeMs,
    this.config = EditorUserConfig.defaults,
    this.canWrite = true,
  });

  factory EditorOpenResult.fromJson(Map<String, dynamic> json) {
    return EditorOpenResult(
      docId: json['docId']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      rev: int.tryParse(json['rev']?.toString() ?? '') ?? 0,
      size: int.tryParse(json['size']?.toString() ?? ''),
      mtimeMs: int.tryParse(json['mtimeMs']?.toString() ?? ''),
      config: EditorUserConfig.fromJson(
        (json['config'] is Map)
            ? Map<String, dynamic>.from(json['config'])
            : null,
      ),
      canWrite: json['canWrite'] == true,
    );
  }
}

class EditorApiService extends BaseApiService {
  Future<EditorOpenResult> open({required String path}) async {
    final res = await apiPost<EditorOpenResult>(
      '/api/editor/open',
      body: {'path': path},
      dataParser: (json, _) => EditorOpenResult.fromJson(json),
    );
    if (!res.success || res.data == null) {
      throw Exception(res.message ?? 'error');
    }
    return res.data!;
  }

  Future<void> save({required String path, required String text}) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/editor/save',
      body: {'path': path, 'text': text},
      dataParser: (json, _) => json,
      showLoading: false,
    );
    if (!res.success) {
      throw Exception(res.message ?? 'error');
    }
  }

  Future<EditorUserConfig> getConfig() async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/editor/config/get',
      body: const {},
      dataParser: (json, _) => json,
      showLoading: false,
    );
    if (!res.success || res.data == null) {
      throw Exception(res.message ?? 'error');
    }
    final cfg = res.data?['config'];
    if (cfg is Map) {
      return EditorUserConfig.fromJson(Map<String, dynamic>.from(cfg));
    }
    return EditorUserConfig.defaults;
  }

  Future<EditorUserConfig> setConfig(EditorUserConfig config) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/editor/config/set',
      body: {'config': config.toJson()},
      dataParser: (json, _) => json,
      showLoading: false,
    );
    if (!res.success || res.data == null) {
      throw Exception(res.message ?? 'error');
    }
    final cfg = res.data?['config'];
    if (cfg is Map) {
      return EditorUserConfig.fromJson(Map<String, dynamic>.from(cfg));
    }
    return EditorUserConfig.defaults;
  }

  Future<EditorUserConfig> resetConfig() async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/editor/config/reset',
      body: const {},
      dataParser: (json, _) => json,
      showLoading: false,
    );
    if (!res.success || res.data == null) {
      throw Exception(res.message ?? 'error');
    }
    final cfg = res.data?['config'];
    if (cfg is Map) {
      return EditorUserConfig.fromJson(Map<String, dynamic>.from(cfg));
    }
    return EditorUserConfig.defaults;
  }
}
