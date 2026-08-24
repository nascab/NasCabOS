'use strict';

const fs = require('fs');
const { XMLParser } = require('fast-xml-parser');

function _cleanText(s) {
  const str = s === undefined || s === null ? '' : String(s);
  return str.replace(/`+/g, '').replace(/\s+/g, ' ').trim();
}

function _toArray(v) {
  if (v === undefined || v === null) return [];
  return Array.isArray(v) ? v : [v];
}

function _pickFirstText(v) {
  const list = _toArray(v);
  for (const item of list) {
    if (item === undefined || item === null) continue;
    if (typeof item === 'string' || typeof item === 'number' || typeof item === 'boolean') {
      const t = _cleanText(item);
      if (t) return t;
      continue;
    }
    if (typeof item === 'object') {
      const t = _cleanText(item['#text']);
      if (t) return t;
    }
  }
  return '';
}

function _pickAllText(v) {
  const out = [];
  const list = _toArray(v);
  for (const item of list) {
    const t = _pickFirstText(item);
    if (t) out.push(t);
  }
  return out;
}

function _pickUniqueId(root, type) {
  const want = String(type || '')
    .trim()
    .toLowerCase();
  if (!want) return '';
  const ids = _toArray(root && (root.uniqueid || root.uniqueId));
  for (const it of ids) {
    if (!it || typeof it !== 'object') continue;
    const t = _cleanText(it['@_type']);
    if (!t || t.toLowerCase() !== want) continue;
    const val = _pickFirstText(it['#text'] !== undefined ? it['#text'] : it);
    if (val) return val;
  }
  return '';
}

function _pickPeopleObjects(v) {
  const list = [];
  const blocks = _toArray(v);
  for (const b of blocks) {
    if (!b || typeof b !== 'object') continue;
    const name = _pickFirstText(b.name);
    const originalName = _pickFirstText(b.originalname);
    const thumb = _pickFirstText(b.thumb);
    const tmdbId = _pickFirstText(b.tmdbid);
    if (!name && !originalName && !thumb && !tmdbId) continue;
    list.push({ name, originalName, thumb, tmdbId });
  }

  const seen = new Set();
  const deduped = [];
  for (const p of list) {
    const key = p.tmdbId ? `tmdb:${p.tmdbId}` : `name:${p.name}||${p.originalName}`;
    if (!key || seen.has(key)) continue;
    seen.add(key);
    deduped.push(p);
  }

  return deduped;
}

function detectNfoRootType(xml) {
  const s = String(xml || '').toLowerCase();
  if (s.includes('<movie')) return 'movie';
  if (s.includes('<tvshow')) return 'tvshow';
  if (s.includes('<season')) return 'season';
  if (s.includes('<episodedetails')) return 'episodedetails';
  return '';
}

function parseNfoXml(xml) {
  const raw = String(xml || '');
  if (!raw.trim()) return null;

  const parser = new XMLParser({
    ignoreAttributes: false,
    attributeNamePrefix: '@_',
    allowBooleanAttributes: true,
    trimValues: true,
    parseTagValue: false,
    parseAttributeValue: false,
    processEntities: true,
  });

  let doc;
  try {
    doc = parser.parse(raw);
  } catch (_) {
    doc = null;
  }

  const rootName =
    doc && typeof doc === 'object'
      ? Object.keys(doc).find(k => {
          const key = k === undefined || k === null ? '' : String(k);
          return key && !key.startsWith('?');
        }) || ''
      : '';
  const root = rootName && doc && doc[rootName] ? doc[rootName] : null;
  const type = rootName ? String(rootName).toLowerCase() : detectNfoRootType(raw);

  if (!root || typeof root !== 'object') {
    return {
      type: type || '',
      title: '',
      originalTitle: '',
      sortTitle: '',
      plot: '',
      premiered: '',
      year: 0,
      rating: 0,
      genres: [],
      tags: [],
      countries: [],
      languages: [],
      imdbId: '',
      tmdbId: '',
      actors: [],
      directors: [],
      actorsDetailed: [],
      directorsDetailed: [],
      seasonNumber: 0,
      episodeNumber: 0,
      aliases: [],
    };
  }

  const title = _pickFirstText(root.title) || _pickFirstText(root.name);
  const originalTitle = _pickFirstText(root.originaltitle);
  const sortTitle = _pickFirstText(root.sorttitle) || _pickFirstText(root.sortname);
  const plot = _pickFirstText(root.plot) || _pickFirstText(root.outline) || _pickFirstText(root.biography);
  const premiered = _pickFirstText(root.premiered) || _pickFirstText(root.releasedate);

  const year = Number(_pickFirstText(root.year) || 0) || 0;

  let ratingText = _pickFirstText(root.rating);
  if (!ratingText && root.rating && typeof root.rating === 'object') {
    ratingText = _pickFirstText(root.rating.value) || _pickFirstText(root.rating['#text']);
  }
  if (!ratingText) ratingText = _pickFirstText(root.value);
  const rating = Number(ratingText || 0) || 0;

  const genres = _pickAllText(root.genre);
  const tags = _pickAllText(root.tag);
  const countries = _pickAllText(root.country);
  const languages = _pickAllText(root.language);

  const imdbId =
    _pickUniqueId(root, 'imdb') ||
    _pickFirstText(root.imdbid) ||
    (() => {
      const id = _pickFirstText(root.id);
      if (id && /^tt\d+$/i.test(id)) return id;
      return '';
    })();

  const tmdbId = _pickUniqueId(root, 'tmdb');

  const actorsDetailed = _pickPeopleObjects(root.actor);
  const directorsDetailed = _pickPeopleObjects(root.director);
  const actors = actorsDetailed.map(p => p.name).filter(Boolean);
  const directors = directorsDetailed.map(p => p.name).filter(Boolean);

  const seasonNumber = Number(_pickFirstText(root.season) || 0) || 0;
  const episodeNumber = Number(_pickFirstText(root.episode) || 0) || 0;

  const aliases = [];
  if (originalTitle && originalTitle !== title) aliases.push(originalTitle);
  if (sortTitle && sortTitle !== title && sortTitle !== originalTitle) aliases.push(sortTitle);

  return {
    type: type || '',
    title,
    originalTitle,
    sortTitle,
    plot,
    premiered,
    year,
    rating,
    genres,
    tags,
    countries,
    languages,
    imdbId,
    tmdbId,
    actors,
    directors,
    actorsDetailed,
    directorsDetailed,
    seasonNumber,
    episodeNumber,
    aliases,
  };
}

async function readAndParseNfo(nfoPath) {
  if (!nfoPath) return null;
  let txt;
  try {
    txt = await fs.promises.readFile(String(nfoPath), 'utf8');
  } catch (_) {
    return null;
  }
  const parsed = parseNfoXml(txt);
  if (!parsed || !parsed.type) return parsed || null;
  return parsed;
}

async function hasValidNfo(nfoPath, expectedType) {
  const wantType = String(expectedType || '')
    .trim()
    .toLowerCase();
  if (!nfoPath || !wantType) return false;
  const parsed = await readAndParseNfo(nfoPath);
  if (!parsed || !parsed.type) return false;
  if (String(parsed.type).toLowerCase() !== wantType) return false;
  const tmdbId = parsed.tmdbId ? String(parsed.tmdbId).trim() : '';
  return !!tmdbId;
}

module.exports = {
  detectNfoRootType,
  parseNfoXml,
  readAndParseNfo,
  hasValidNfo,
};
