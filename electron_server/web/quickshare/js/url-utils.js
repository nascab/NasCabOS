/** URL helpers (no app state) */
export function buildUrl(pathname, params) {
  const u = new URL(pathname, location.origin);
  for (const [k, v] of Object.entries(params || {})) {
    if (v == null) continue;
    const s = String(v);
    if (!s) continue;
    u.searchParams.set(k, s);
  }
  return u.toString();
}

export function urlToPath(url) {
  try {
    const u = new URL(String(url || ''), location.origin);
    return `${u.pathname}${u.search || ''}`;
  } catch (_) {
    const s = String(url || '');
    if (s.startsWith('/')) return s;
    return '/';
  }
}
