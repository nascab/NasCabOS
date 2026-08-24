'use strict';

const fs = require('fs');
const path = require('path');
const config = require('../../config/config');

function makeCandidateNames(baseName, exts) {
  const res = [];
  for (const ext of exts) {
    res.push(`${baseName}${ext.toLowerCase()}`);
    res.push(`${baseName}${ext.toUpperCase()}`);
  }
  return Array.from(new Set(res));
}

function isRawExt(ext) {
  const e = String(ext || '').toLowerCase();
  return !!(e && config.rawImgTypeList && config.rawImgTypeList.includes(e));
}

async function handleRawFile({ knex, dirPath, filename }) {
  const baseName = path.parse(filename).name;
  const photoNames = makeCandidateNames(baseName, ['.jpg', '.jpeg', '.heic', '.heif']);
  const photoNamesLower = photoNames.map(n => String(n).toLowerCase());

  const pairedPhoto = await knex('photo_index')
    .select('id', 'raw_filename')
    .where({ path: dirPath, is_file: 1, type: 1 })
    .whereIn(knex.raw('lower(filename)'), photoNamesLower)
    .orderBy('id', 'asc')
    .first()
    .catch(() => null);

  let photoExistsOnDisk = false;
  if (!pairedPhoto || !pairedPhoto.id) {
    for (const name of photoNames) {
      const full = path.join(dirPath, name);
      try {
        if (fs.existsSync(full)) {
          photoExistsOnDisk = true;
          break;
        }
      } catch (_) {}
    }
  }

  if ((!pairedPhoto || !pairedPhoto.id) && !photoExistsOnDisk) {
    return { handled: false };
  }

  if (pairedPhoto && pairedPhoto.id && !pairedPhoto.raw_filename) {
    await knex('photo_index')
      .where({ id: pairedPhoto.id })
      .update({ raw_filename: filename, check_time: Date.now() })
      .catch(() => {});
  }

  await knex('photo_index')
    .where({ path: dirPath, filename, is_file: 1 })
    .delete()
    .catch(() => {});

  return { handled: true };
}

async function attachRawToPhotoBase({ knex, dirPath, filename, base }) {
  if (!base) return { rawIndexIdsToDelete: [] };
  if (base.raw_filename) return { rawIndexIdsToDelete: [] };

  const baseName = path.parse(filename).name;
  const rawExts = Array.isArray(config.rawImgTypeList) ? config.rawImgTypeList : [];
  const rawNames = makeCandidateNames(baseName, rawExts);
  const rawNamesLower = rawNames.map(n => String(n).toLowerCase());

  const row = await knex('photo_index')
    .select('id', 'filename')
    .where({ path: dirPath, is_file: 1, type: 1 })
    .whereIn(knex.raw('lower(filename)'), rawNamesLower)
    .orderBy('id', 'asc')
    .first()
    .catch(() => null);

  if (row && row.filename) {
    base.raw_filename = row.filename;
    return { rawIndexIdsToDelete: row.id ? [row.id] : [] };
  }

  for (const name of rawNames) {
    const full = path.join(dirPath, name);
    try {
      if (fs.existsSync(full)) {
        base.raw_filename = name;
        break;
      }
    } catch (_) {}
  }

  return { rawIndexIdsToDelete: [] };
}

module.exports = {
  isRawExt,
  handleRawFile,
  attachRawToPhotoBase,
  makeCandidateNames,
};
