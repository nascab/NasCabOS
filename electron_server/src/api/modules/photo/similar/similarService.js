const path = require('path');
const config = require('../../../../config/config');

function parseCount(row) {
  if (!row) return 0;
  const v = row.count ?? row['count(*)'] ?? row['COUNT(*)'] ?? row.total ?? row['total'];
  const n = Math.floor(Number(v));
  return Number.isFinite(n) && n >= 0 ? n : 0;
}

function parseFileHashArray(raw) {
  if (!raw) return [];
  if (Array.isArray(raw)) return raw.map(v => String(v)).filter(Boolean);
  try {
    const parsed = JSON.parse(String(raw));
    if (!Array.isArray(parsed)) return [];
    return parsed.map(v => String(v)).filter(Boolean);
  } catch (_) {
    return [];
  }
}

function rawShowExt(item) {
  if (!item || !item.ext) return '';
  const ext = String(item.ext || '');
  if (config.rawImgTypeList && config.rawImgTypeList.includes(ext)) {
    return ext.toUpperCase().replace('.', '');
  }
  const rawFilename = item.raw_filename ? String(item.raw_filename) : '';
  if (rawFilename && rawFilename.includes('.')) {
    return `${ext.toUpperCase().replace('.', '')} +${path.extname(rawFilename).toUpperCase().replace('.', '')}`;
  }
  return '';
}

class SimilarService {
  constructor(knex) {
    this.knex = knex;
  }

  async listSimilarGroups(params = {}) {
    const page = Math.max(1, Number(params.page) || 1);
    const pageSize = Math.max(1, Math.min(200, Number(params.pageSize ?? params.page_size) || 20));
    const offset = (page - 1) * pageSize;

    const totalRow = await this.knex('photo_similar')
      .count({ count: '*' })
      .first()
      .catch(() => null);
    const total = parseCount(totalRow);

    const rows = await this.knex('photo_similar')
      .select('id', 'index_id', 'similar_file_hash', 'create_time')
      .orderBy('id', 'desc')
      .limit(pageSize)
      .offset(offset)
      .catch(() => []);

    const items = [];
    for (const r of rows) {
      const id = Number(r && r.id) || 0;
      if (!id) continue;

      const fileHashes = parseFileHashArray(r && r.similar_file_hash);
      if (fileHashes.length === 0) {
        await this.knex('photo_similar')
          .where({ id })
          .del()
          .catch(() => {});
        continue;
      }

      const photoRows = await this.knex('photo_index')
        .whereIn('file_hash', fileHashes)
        .andWhere({ is_file: 1, in_trash: 0, type: 1 })
        .select('id', 'path', 'filename', 'size', 'is_lvp', 'type', 'width', 'height', 'original_date', 'original_time', 'duration', 'file_hash', 'live_filename', 'raw_filename', 'ext')
        .orderBy('original_time', 'desc')
        .orderBy('id', 'desc')
        .catch(() => []);

      if (!photoRows || photoRows.length < 2) {
        await this.knex('photo_similar')
          .where({ id })
          .del()
          .catch(() => {});
        continue;
      }

      const photos = photoRows.map(p => ({
        ...p,
        fullpath: path.join(p.path, p.filename),
        is_favorite: 0,
        raw_show_ext: rawShowExt(p),
      }));

      items.push({
        id,
        index_id: Number(r && r.index_id) || 0,
        file_hashes: fileHashes,
        photos,
        create_time: r && r.create_time ? r.create_time : null,
      });
    }

    return {
      items,
      pagination: {
        total,
        page,
        pageSize,
      },
    };
  }

  async batchDeleteSimilarRecords(ids = []) {
    const cleanIds = (Array.isArray(ids) ? ids : []).map(v => Number(v)).filter(v => Number.isFinite(v) && v > 0);
    if (cleanIds.length === 0) return 0;
    const deleted = await this.knex('photo_similar')
      .whereIn('id', cleanIds)
      .del()
      .catch(() => 0);
    return Number(deleted) || 0;
  }

  async resetSimilarScan() {
    await this.knex.transaction(async trx => {
      await trx('photo_similar')
        .del()
        .catch(() => {});
      await trx('photo_index')
        .where({ type: 1, is_file: 1, in_trash: 0 })
        .whereNotNull('phash')
        .andWhere('phash', '!=', '')
        .update({ gen_phash: 1 })
        .catch(() => {});

      await trx('photo_index')
        .where({ type: 1, is_file: 1, in_trash: 0 })
        .where(builder => builder.whereNull('phash').orWhere('phash', ''))
        .update({ gen_phash: 0 })
        .catch(() => {});
    });
    return true;
  }
}

module.exports = SimilarService;
