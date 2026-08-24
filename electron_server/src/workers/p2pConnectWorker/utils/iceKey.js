function iceServersKey(list) {
  const arr = Array.isArray(list) ? list : [];
  const parts = [];
  for (const s of arr) {
    if (!s || typeof s !== 'object') continue;
    const urls = s.urls == null ? '' : String(s.urls);
    const username = s.username == null ? '' : String(s.username);
    const credRaw = s.credential == null ? (s.password == null ? '' : String(s.password)) : String(s.credential);
    const credLen = credRaw ? String(credRaw.length) : '';
    parts.push(`${urls}|${username}|${credLen}`);
  }
  return parts.join(';');
}

module.exports = { iceServersKey };
