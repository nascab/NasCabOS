'use strict';

const fs = require('fs');
const path = require('path');

function _xmlEscape(s) {
  const str = s === undefined || s === null ? '' : String(s);
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&apos;');
}

function _tag(name, value) {
  const v = value === undefined || value === null ? '' : String(value);
  if (!v.trim()) return '';
  return `<${name}>${_xmlEscape(v)}</${name}>`;
}

function _tagNumber(name, value) {
  const n = Number(value || 0);
  if (!Number.isFinite(n) || n === 0) return '';
  return `<${name}>${n}</${name}>`;
}

function _tagDate(name, value) {
  const v = value === undefined || value === null ? '' : String(value);
  const s = v.trim().slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return '';
  return `<${name}>${s}</${name}>`;
}

function _uniqueId(type, value, isDefault) {
  const v = value === undefined || value === null ? '' : String(value).trim();
  if (!v) return '';
  const t = String(type || '').trim();
  if (!t) return '';
  const def = isDefault ? ' default="true"' : '';
  return `<uniqueid type="${_xmlEscape(t)}"${def}>${_xmlEscape(v)}</uniqueid>`;
}

function _listTags(name, arr) {
  const list = Array.isArray(arr) ? arr : [];
  return list
    .map(v => (v === undefined || v === null ? '' : String(v).trim()))
    .filter(Boolean)
    .map(v => `<${name}>${_xmlEscape(v)}</${name}>`)
    .join('');
}

function _actors(actors) {
  const list = Array.isArray(actors) ? actors : [];
  const out = [];
  for (const a of list) {
    if (!a) continue;
    const name = a.name ? String(a.name).trim() : '';
    const role = a.role ? String(a.role).trim() : '';
    const thumb = a.thumb ? String(a.thumb).trim() : '';
    const tmdbId = a.tmdbId ? String(a.tmdbId).trim() : '';
    if (!name && !role && !thumb && !tmdbId) continue;
    out.push(`<actor>${_tag('name', name)}${_tag('role', role)}${_tag('thumb', thumb)}${_tag('tmdbid', tmdbId)}</actor>`);
  }
  return out.join('');
}

function _directors(directors) {
  const list = Array.isArray(directors) ? directors : [];
  const out = [];
  for (const a of list) {
    if (!a) continue;
    const name = a.name ? String(a.name).trim() : '';
    const thumb = a.thumb ? String(a.thumb).trim() : '';
    const tmdbId = a.tmdbId ? String(a.tmdbId).trim() : '';
    if (!name && !thumb && !tmdbId) continue;
    out.push(`<director>${_tag('name', name)}${_tag('thumb', thumb)}${_tag('tmdbid', tmdbId)}</director>`);
  }
  return out.join('');
}

function buildMovieNfo(data) {
  const d = data && typeof data === 'object' ? data : {};
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<movie>${_tag('title', d.title)}${_tag(
    'originaltitle',
    d.originalTitle
  )}${_tag('sorttitle', d.sortTitle)}${_tagNumber('year', d.year)}${_tagDate('premiered', d.premiered)}${_tag(
    'plot',
    d.plot
  )}${_tagNumber('rating', d.rating)}${_listTags('genre', d.genres)}${_listTags('tag', d.tags)}${_listTags(
    'country',
    d.countries
  )}${_listTags('language', d.languages)}${_uniqueId('tmdb', d.tmdbId, true)}${_uniqueId('imdb', d.imdbId, false)}${_actors(d.actors)}${_directors(d.directors)}</movie>\n`;
}

function buildTvShowNfo(data) {
  const d = data && typeof data === 'object' ? data : {};
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<tvshow>${_tag('title', d.title)}${_tag(
    'originaltitle',
    d.originalTitle
  )}${_tag('sorttitle', d.sortTitle)}${_tagNumber('year', d.year)}${_tagDate('premiered', d.premiered)}${_tag(
    'plot',
    d.plot
  )}${_tagNumber('rating', d.rating)}${_listTags('genre', d.genres)}${_listTags('tag', d.tags)}${_listTags(
    'country',
    d.countries
  )}${_listTags('language', d.languages)}${_tag('studio', d.studio)}${_uniqueId('tmdb', d.tmdbId, true)}${_uniqueId('imdb', d.imdbId, false)}${_actors(d.actors)}${_directors(d.directors)}</tvshow>\n`;
}

function buildSeasonNfo(data) {
  const d = data && typeof data === 'object' ? data : {};
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<season>${_tag('title', d.title)}${_tagNumber(
    'season',
    d.seasonNumber
  )}${_tagNumber('year', d.year)}${_tagDate('premiered', d.premiered)}${_tag('plot', d.plot)}${_tagNumber(
    'rating',
    d.rating
  )}${_uniqueId('tmdb', d.tmdbId, true)}${_actors(d.actors)}${_directors(d.directors)}</season>\n`;
}

function buildEpisodeNfo(data) {
  const d = data && typeof data === 'object' ? data : {};
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<episodedetails>${_tag('title', d.title)}${_tagNumber(
    'season',
    d.seasonNumber
  )}${_tagNumber('episode', d.episodeNumber)}${_tagDate('aired', d.aired)}${_tag('plot', d.plot)}${_tagNumber(
    'rating',
    d.rating
  )}${_uniqueId('tmdb', d.tmdbId, true)}${_actors(d.actors)}${_directors(d.directors)}</episodedetails>\n`;
}

async function writeTextIfChanged(targetPath, content) {
  const p = String(targetPath || '').trim();
  if (!p) return false;
  await fs.promises.mkdir(path.dirname(p), { recursive: true });
  let old = '';
  try {
    old = await fs.promises.readFile(p, 'utf8');
  } catch (_) {}
  const next = String(content || '');
  if (old === next) return false;
  await fs.promises.writeFile(p, next, 'utf8');
  return true;
}

module.exports = {
  buildMovieNfo,
  buildTvShowNfo,
  buildSeasonNfo,
  buildEpisodeNfo,
  writeTextIfChanged,
};
