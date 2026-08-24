'use strict';

const path = require('path');
const crypto = require('crypto');
const { getFirstLetter } = require('../../utils/firstLetterUtil');

function computeFileHash(fullPath, stat) {
  const resolvedPath = path.resolve(fullPath);
  const hashStr = path.basename(resolvedPath) + (stat && stat.size ? stat.size : 0) + (stat && stat.mtimeMs ? stat.mtimeMs : 0);
  return crypto.createHash('sha256').update(hashStr).digest('hex');
}

function parseArtistTitleFromFilename(filename) {
  const name = filename ? String(filename) : '';
  if (!name) return { artist: '', title: '' };
  const base = name.replace(/\.[^.]+$/, '');
  const stripTrackPrefix = s =>
    String(s || '')
      .replace(/^\s*\d{1,3}\s*[-._]?\s+/, '')
      .trim();
  const parts = base
    .split(' - ')
    .map(s => s.trim())
    .filter(Boolean);
  if (parts.length >= 2) {
    return { artist: parts[0], title: parts.slice(1).join(' - ') };
  }
  return { artist: '', title: stripTrackPrefix(base) };
}

function buildMusicIndexRow({ fullPath, stat, tags, probe, tagReader }) {
  const p = fullPath ? path.resolve(String(fullPath)) : '';
  if (!p) return null;
  const st = stat || null;
  if (!st) return null;

  const dir = path.dirname(p);
  const name = path.basename(p);
  if (!dir || !name) return null;

  const ext = path.extname(name).toLowerCase();
  const filenameMeta = parseArtistTitleFromFilename(name);
  const probeTags = probe && probe.meta && probe.meta.format && probe.meta.format.tags && typeof probe.meta.format.tags === 'object' ? probe.meta.format.tags : {};

  const albumFromJs = tagReader._extractTextFromTags(tags, 'album', 'album', 'TALB', 'album') || tagReader._extractTextFromTags(tags, 'album', 'album', 'TXXX', 'album');
  const albumFromProbe = tagReader.normalizeTagText(probeTags.album || probeTags.ALBUM || '');
  let album = tagReader._pickBestText(albumFromJs, albumFromProbe);
  if (tagReader._isGarbledText(album)) album = '';
  if (!album) album = path.basename(dir);

  const titleFromJs = tagReader._extractTextFromTags(tags, 'title', 'title', 'TIT2', 'title') || tagReader._extractTextFromTags(tags, 'title', 'title', 'TXXX', 'title');
  const titleFromProbe = tagReader.normalizeTagText(probeTags.title || probeTags.TITLE || '');
  let title = tagReader._pickBestText(titleFromJs, titleFromProbe);
  if (tagReader._isGarbledText(title)) title = '';
  const usedFilenameTitle = !title;
  if (!title) title = filenameMeta.title || '';

  const artistFromJs = tagReader._extractTextFromTags(tags, 'artist', 'artist', 'TPE1', 'performer') || tagReader._extractTextFromTags(tags, 'artist', 'artist', 'TXXX', 'artist');
  const artistFromProbe = tagReader.normalizeTagText(probeTags.artist || probeTags.ARTIST || '');
  let artist = tagReader._pickBestText(artistFromJs, artistFromProbe);
  if (tagReader._isGarbledText(artist)) artist = '';
  const usedFilenameArtist = !artist;
  if (!artist) artist = filenameMeta.artist || '';
  if (!artist) {
    const parentDirName = path.basename(path.dirname(dir));
    if (parentDirName && !tagReader._isGarbledText(parentDirName)) artist = parentDirName;
    const albumDirName = path.basename(dir);
    const sameAsAlbum = albumDirName && artist && albumDirName === artist;
    const looksLikeDateAlbum = artist && (/^\d{4}\b/.test(artist) || /\d{4}\.\d{2}\.\d{2}/.test(artist));
    if ((sameAsAlbum || looksLikeDateAlbum) && path.dirname(path.dirname(dir))) {
      const grandParentDirName = path.basename(path.dirname(path.dirname(dir)));
      if (grandParentDirName && !tagReader._isGarbledText(grandParentDirName)) artist = grandParentDirName;
    }
  }
  if (usedFilenameTitle && filenameMeta.artist && !usedFilenameArtist) {
    artist = filenameMeta.artist;
  }

  const yearFromJs = tagReader._extractTextFromTags(tags, 'year', 'year', 'TYER', 'year') || tagReader._extractTextFromTags(tags, 'year', 'year', 'TDRC', 'year');
  const dateFromProbe = tagReader.normalizeTagText(probeTags.date || probeTags.DATE || probeTags.year || probeTags.YEAR || '');
  const yearFromProbe = dateFromProbe ? String(dateFromProbe).trim().slice(0, 4) : '';
  const year = tagReader._pickBestText(yearFromJs, yearFromProbe);

  const genreFromJs = tagReader._extractTextFromTags(tags, 'genre', 'genre', 'TCON', 'content') || tagReader._extractTextFromTags(tags, 'genre', 'genre', 'TXXX', 'genre');
  const genreFromProbe = tagReader.normalizeTagText(probeTags.genre || probeTags.GENRE || '');
  const genre = tagReader._pickBestText(genreFromJs, genreFromProbe);

  const lyricsFromJs =
    tagReader._extractTextFromTags(tags, 'lyrics', 'lyrics', 'USLT', 'lyrics') ||
    tagReader._extractTextFromTags(tags, 'lyrics', 'lyrics', 'SYLT', 'lyrics') ||
    tagReader.normalizeTagText(tags && typeof tags === 'object' ? tags.lyrics : '');
  const lyricsFromProbe = tagReader.normalizeTagText(probeTags.lyrics || probeTags.LYRICS || '');
  const lyrics = tagReader._pickBestText(lyricsFromJs, lyricsFromProbe);

  const audioStream = probe && Array.isArray(probe.streams) ? probe.streams.find(s => s && s.codec_type === 'audio') : null;
  const formatMeta = probe && probe.meta && probe.meta.format && typeof probe.meta.format === 'object' ? probe.meta.format : null;
  const toPositiveIntString = v => {
    const n = Number(v);
    if (!Number.isFinite(n) || n <= 0) return '';
    return String(Math.trunc(n));
  };
  const bitrate = toPositiveIntString((audioStream && audioStream.bit_rate) || (formatMeta && formatMeta.bit_rate));
  const sampleRate = toPositiveIntString(audioStream && audioStream.sample_rate);
  const bitDepth = toPositiveIntString((audioStream && audioStream.bits_per_sample) || (audioStream && audioStream.bits_per_raw_sample));

  const duration = probe && probe.duration ? tagReader._toInt(probe.duration) : 0;
  const streamInfo = probe && Array.isArray(probe.streams) ? tagReader._safeJsonStringify(probe.streams) : '';

  return {
    path: dir,
    filename: name,
    ext,
    size: st.size ? Number(st.size) : 0,
    file_hash: computeFileHash(p, st),
    ctime: st.ctimeMs ? new Date(st.ctimeMs) : null,
    mtime: st.mtimeMs ? new Date(st.mtimeMs) : null,
    birthtime: st.birthtimeMs ? new Date(st.birthtimeMs) : null,
    duration,
    title: title || '',
    title_fl: getFirstLetter(title || ''),
    artist: artist || '',
    artist_fl: getFirstLetter(artist || ''),
    album: album || '',
    album_fl: getFirstLetter(album || ''),
    year: year || '',
    genre: genre || '',
    lyrics: lyrics || '',
    stream_info: streamInfo || '',
    lyrics_get_state: lyrics ? 1 : 0,
    bitrate: bitrate || '',
    sample_rate: sampleRate || '',
    bit_depth: bitDepth || '',
  };
}

module.exports = {
  buildMusicIndexRow,
  parseArtistTitleFromFilename,
  computeFileHash,
};
