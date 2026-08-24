/** P2P download / stream retry heuristics */
export function isP2pRetryableFailure({ status, text }) {
  const s = Number(status);
  if (s === 401 || s === 403 || s === 408) return true;
  if (s >= 500 && s < 600) return true;
  const t = String(text || '').toLowerCase();
  if (t.includes('unauthorized') || t.includes('forbidden')) return true;
  return false;
}

export function isP2pTransportError(err) {
  const m = err && err.message ? String(err.message) : String(err || '');
  return /p2p_|timeout|abort|closed|failed|network|not.*open|backpressure/i.test(m);
}
