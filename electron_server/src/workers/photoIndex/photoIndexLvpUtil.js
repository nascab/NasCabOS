'use strict';

const lvpUtil = require('../../utils/lvpUtil');

function makeCandidateNames(baseName, exts) {
  const res = [];
  for (const ext of exts) {
    res.push(`${baseName}${ext.toLowerCase()}`);
    res.push(`${baseName}${ext.toUpperCase()}`);
  }
  return Array.from(new Set(res));
}

function pickBestByTime(rows, targetMs) {
  let best = null;
  let bestDiff = Number.POSITIVE_INFINITY;
  for (const r of rows) {
    const t = new Date(r.original_time || 0).getTime();
    if (!Number.isFinite(t) || t <= 0) continue;
    const diff = Math.abs(t - targetMs);
    if (diff <= 10_000 && diff < bestDiff) {
      best = r;
      bestDiff = diff;
    }
  }
  return best;
}

function applyMergeLvpFlags(base, exifData) {
  if (!base || !exifData) return;
  if (lvpUtil && typeof lvpUtil.isMergeLvp === 'function' && lvpUtil.isMergeLvp(exifData)) {
    base.is_lvp = 1;
    base.is_merge_lvp = 1;
  }
}

async function findPairedVideoIndex({ knex, dirPath, baseName, photoOriginalTimeMs }) {
  const names = makeCandidateNames(baseName, ['.mp4', '.mov']);
  const rows = await knex('photo_index')
    .select('id', 'filename', 'original_time', 'duration')
    .where({ path: dirPath, is_file: 1, type: 2 })
    .whereIn('filename', names)
    .andWhere('duration', '>', 0)
    .andWhere('duration', '<', 5)
    .limit(20)
    .catch(() => []);
  if (!rows || rows.length === 0) return null;
  return pickBestByTime(rows, photoOriginalTimeMs);
}

async function findPairedPhotoIndex({ knex, dirPath, baseName, videoOriginalTimeMs }) {
  const names = makeCandidateNames(baseName, ['.jpg', '.jpeg', '.heic', '.heif']);
  const rows = await knex('photo_index')
    .select('id', 'filename', 'original_time', 'is_lvp', 'live_filename')
    .where({ path: dirPath, is_file: 1, type: 1 })
    .whereIn('filename', names)
    .andWhere(qb => {
      qb.whereNull('live_filename').orWhere('live_filename', '');
    })
    .limit(20)
    .catch(() => []);
  if (!rows || rows.length === 0) return null;

  const candidates = rows.filter(r => !(r.is_lvp === 1 && r.live_filename));
  if (candidates.length === 0) return null;
  return pickBestByTime(candidates, videoOriginalTimeMs);
}

async function handleSeparatedLvpForPhoto({ knex, dirPath, filename, ext, photoOriginalTimeMs, base }) {
  if (!base || base.is_merge_lvp === 1) return { pairedVideo: null };
  if (!(ext === '.jpg' || ext === '.jpeg' || ext === '.heic' || ext === '.heif')) {
    return { pairedVideo: null };
  }

  const baseName = require('path').parse(filename).name;
  const pairedVideo = await findPairedVideoIndex({
    knex,
    dirPath,
    baseName,
    photoOriginalTimeMs,
  });
  if (!pairedVideo) return { pairedVideo: null };

  base.is_lvp = 1;
  base.is_merge_lvp = 0;
  base.live_filename = pairedVideo.filename;
  return { pairedVideo };
}

async function handleSeparatedLvpForVideo({ knex, dirPath, filename, ext, videoOriginalTimeMs, duration }) {
  if (!(ext === '.mp4' || ext === '.mov')) return { matched: false };
  if (!Number.isFinite(duration) || duration <= 0 || duration >= 5) return { matched: false };

  const baseName = require('path').parse(filename).name;
  const pairedPhoto = await findPairedPhotoIndex({
    knex,
    dirPath,
    baseName,
    videoOriginalTimeMs,
  });
  if (!pairedPhoto) return { matched: false };

  await knex('photo_index')
    .where({ id: pairedPhoto.id })
    .update({
      is_lvp: 1,
      is_merge_lvp: 0,
      live_filename: filename,
      check_time: Date.now(),
    })
    .catch(() => {});

  return { matched: true, pairedPhotoId: pairedPhoto.id };
}

module.exports = {
  applyMergeLvpFlags,
  handleSeparatedLvpForPhoto,
  handleSeparatedLvpForVideo,
  makeCandidateNames,
};
