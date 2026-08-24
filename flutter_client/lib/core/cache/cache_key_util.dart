/// 缓存 key 用 URL 规范化：去掉会随登录/刷新变化的认证参数，
/// 使同一资源在 token 变化后仍能命中缓存。
String normalizeUrlForCacheKey(String url) {
  final s = url.trim();
  if (s.isEmpty) return s;
  try {
    final uri = Uri.parse(s);
    final q = Map<String, String>.from(uri.queryParameters);
    q.remove('accessToken');
    q.remove('token');
    return uri.replace(queryParameters: q.isEmpty ? null : q).toString();
  } catch (_) {
    return s;
  }
}
