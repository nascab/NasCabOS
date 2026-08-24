function normalizeIceServers(raw) {
  const list = Array.isArray(raw) ? raw : [];
  const out = [];
  for (const item of list) {
    if (!item || typeof item !== 'object') continue;
    const s = item;

    const username = s.username == null ? '' : String(s.username);
    const credential = s.credential == null ? '' : String(s.credential);
    const password = s.password == null ? '' : String(s.password);
    const credentialOrPassword = credential || password;

    const urlsRaw = s.urls != null ? s.urls : s.url;
    const urls = [];
    if (typeof urlsRaw === 'string') {
      const u = String(urlsRaw).trim();
      if (u) urls.push(u);
    } else if (Array.isArray(urlsRaw)) {
      for (const u0 of urlsRaw) {
        const u = u0 == null ? '' : String(u0).trim();
        if (u) urls.push(u);
      }
    }

    if (!urls.length) continue;
    for (const u of urls) {
      const next = { urls: u };
      if (username) next.username = username;
      if (credentialOrPassword) {
        next.credential = credentialOrPassword;
        next.password = credentialOrPassword;
      }
      out.push(next);
    }
  }
  return out;
}

module.exports = { normalizeIceServers };
