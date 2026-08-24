const path = require('path');
const lyricUtils = require('./lyricUtils');

function _safeText(v) {
  return String(v ?? '').trim();
}

function _formatDuration(ms) {
  const n = Number(ms);
  if (!Number.isFinite(n) || n <= 0) return 0;
  return Math.floor(n);
}

function _artistNames(ar) {
  if (!Array.isArray(ar)) return '';
  const names = ar.map(a => _safeText(a?.name)).filter(Boolean);
  return names.join(' / ');
}

function _firstLyricLine(lrc) {
  const text = _safeText(lrc);
  if (!text) return '';
  const lines = text.split(/\r?\n/);
  for (const raw of lines) {
    const line = String(raw || '').trim();
    if (!line) continue;
    if (line.startsWith('[') && line.includes(']')) {
      const idx = line.lastIndexOf(']');
      const after = idx >= 0 ? line.slice(idx + 1).trim() : '';
      if (after) return after;
      continue;
    }
    return line;
  }
  return '';
}

class LyricService {
  async search({ keyword }) {
    const searchMusicName = _safeText(keyword);
    const results = await lyricUtils.searchLyric({
      searchMusicName,
      searchMusicArtist: '',
      isSearch: true,
    });
    const list = Array.isArray(results) ? results : [];
    return list.map(it => {
      const weId = _safeText(it?.weId);
      const title = _safeText(it?.name);
      const album = _safeText(it?.album?.name);
      const artist = _artistNames(it?.artist);
      const duration = _formatDuration(it?.duration);
      const lrc = _safeText(it?.lrc);
      return {
        id: weId ? `we:${weId}` : '',
        source: _safeText(it?.type) || 'we',
        title,
        album,
        artist,
        duration,
        preview: _firstLyricLine(lrc),
        lrc,
      };
    });
  }

  static getLrcPathForMusicPath(musicPath) {
    const full = String(musicPath || '').trim();
    if (!full) return '';
    const dir = path.dirname(full);
    const ext = path.extname(full);
    const base = path.basename(full, ext || undefined);
    return path.join(dir, `${base}.lrc`);
  }
}

module.exports = LyricService;
