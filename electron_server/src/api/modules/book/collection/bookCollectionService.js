const path = require('path');
const userUtil = require('../../../../utils/userUtil');

function _parsePathList(pathListText) {
  if (!pathListText) return [];
  try {
    const arr = JSON.parse(String(pathListText));
    return Array.isArray(arr) ? arr.map(v => String(v || '').trim()).filter(Boolean) : [];
  } catch (_) {
    return [];
  }
}

function _applyBookIndexPathPrefixFilter(query, paths) {
  const list = Array.isArray(paths) ? paths.map(p => String(p || '').trim()).filter(Boolean) : [];
  if (list.length === 0) {
    query.whereRaw('1 = 0');
    return;
  }

  const sep = path.sep;
  const folderExactPairs = [];
  for (const raw of list) {
    const p = raw.endsWith(sep) ? raw.slice(0, -1) : raw;
    if (!p) continue;
    if (path.extname(p)) continue;
    const parent = path.dirname(p);
    const name = path.basename(p);
    if (!parent || !name) continue;
    folderExactPairs.push({ parent, name });
  }

  query.where(builder => {
    for (const p of list) {
      const prefix = p.endsWith(sep) ? p : `${p}${sep}`;
      builder.orWhere(function () {
        this.where('b.path', p).orWhere('b.path', 'like', `${prefix}%`);
      });
    }
    for (const pair of folderExactPairs) {
      builder.orWhere(function () {
        this.where('b.is_file', 0).andWhere('b.path', pair.parent).andWhere('b.filename', pair.name);
      });
    }
  });
}

class BookCollectionService {
  _uid(user) {
    return user.id;
  }

  async _getCollectionById(knexBook, collectionId) {
    const id = Number(collectionId);
    if (!Number.isFinite(id) || id <= 0) return null;
    return knexBook('book_collection').where({ id }).first();
  }

  async _getSourcePaths(knexBook) {
    const sources = await knexBook('book_source').select('path');
    return (sources || []).map(s => (s && s.path ? String(s.path).trim() : '')).filter(Boolean);
  }

  async _validateAndNormalizePaths(knexBook, pathList) {
    const input = Array.isArray(pathList) ? pathList : [];
    const cleaned = input.map(p => String(p || '').trim()).filter(Boolean);
    const uniq = [...new Set(cleaned)];
    if (uniq.length === 0) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }

    const sourcePaths = await this._getSourcePaths(knexBook);
    if (sourcePaths.length === 0) {
      const err = new Error('book.BOOK_SOURCE_LIST_EMPTY');
      err.statusCode = 400;
      throw err;
    }

    const invalid = uniq.find(p => !sourcePaths.some(s => p.startsWith(s)));
    if (invalid) {
      const err = new Error('book.BOOK_SOURCE_OUT_OF_RANGE');
      err.statusCode = 400;
      err.args = { path: invalid };
      throw err;
    }

    return uniq;
  }

  async _ensureCollectionAccess({ knexBook, collectionId, user }) {
    const uid = this._uid(user);
    const collection = await this._getCollectionById(knexBook, collectionId);
    if (!collection) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }

    if (userUtil.isAdmin(user)) {
      return { collection, role: 'admin' };
    }

    if (Number(collection.uid) !== Number(uid)) {
      const err = new Error('auth.PERMISSION_DENIED');
      err.statusCode = 403;
      throw err;
    }

    return { collection, role: 'owner' };
  }

  async _getCollectionPreviews(knexBook, pathList) {
    const prefixes = Array.isArray(pathList) ? pathList.filter(Boolean) : [];
    if (prefixes.length === 0) return [];

    const rows = await knexBook('book_index as b')
      .whereIn('b.show_type', ['book', 'series'])
      .modify(qb => _applyBookIndexPathPrefixFilter(qb, prefixes))
      .select('b.id', 'b.path', 'b.filename', 'b.file_hash', 'b.show_type', 'b.cover_state', 'b.create_time')
      .select(
        knexBook.raw(
          `
          case
            when b.show_type = 'series' then (
              select path || ? || filename
              from book_index as s
              where s.show_type = 'subbook'
                and s.is_file = 1
                and s.path = (b.path || ? || b.filename)
              order by s.id asc
              limit 1
            )
            else ''
          end as first_file_path
          `,
          [path.sep, path.sep]
        )
      )
      .orderBy('b.create_time', 'desc')
      .orderBy('b.id', 'desc')
      .limit(4)
      .catch(() => []);

    return (rows || []).map(r => ({
      id: Number(r && r.id) || 0,
      file_hash: r && r.file_hash ? String(r.file_hash) : '',
      show_type: r && r.show_type ? String(r.show_type) : '',
      cover_state: Number(r && r.cover_state) || 0,
      full_path: r && r.path && r.filename ? path.join(String(r.path), String(r.filename)) : '',
      first_file_path: r && r.first_file_path ? String(r.first_file_path) : '',
    }));
  }

  async listCollections({ knexBook }, params, user) {
    const uid = this._uid(user);
    const page = Math.max(1, Number(params.page || 1));
    const pageSize = Math.max(1, Math.min(100, Number(params.pageSize || 20)));
    const offset = (page - 1) * pageSize;
    const keyword = String(params.keyword || '').trim();

    const sortFieldInput = String(params.sortField || 'create_time');
    const sortOrderInput = String(params.sortOrder || 'desc').toLowerCase();
    const sortOrder = sortOrderInput === 'asc' ? 'asc' : 'desc';
    const sortField = sortFieldInput === 'name' || sortFieldInput === 'create_time' ? sortFieldInput : 'create_time';

    const base = knexBook('book_collection as c')
      .modify(qb => {
        if (keyword) qb.where('c.name', 'like', `%${keyword}%`);
        qb.where('c.uid', uid);
      })
      .select('c.id', 'c.uid', 'c.name', 'c.path_list', 'c.create_time')
      .orderBy(`c.${sortField}`, sortOrder)
      .orderBy('c.id', 'desc');

    const [{ count }] = await base.clone().clearSelect().clearOrder().count('* as count');
    const items = await base.clone().offset(offset).limit(pageSize);

    const enriched = await Promise.all(
      (items || []).map(async row => {
        const pathList = _parsePathList(row.path_list);
        const previews = await this._getCollectionPreviews(knexBook, pathList);
        return {
          id: row.id,
          uid: row.uid,
          name: row.name,
          path_list: pathList,
          create_time: row.create_time,
          previews,
        };
      })
    );

    return {
      items: enriched,
      pagination: {
        total: Number(count || 0),
        page,
        pageSize,
      },
    };
  }

  async getCollection({ knexBook }, collectionId, user) {
    const { collection } = await this._ensureCollectionAccess({ knexBook, collectionId, user });
    return {
      id: collection.id,
      uid: collection.uid,
      name: collection.name,
      path_list: _parsePathList(collection.path_list),
      create_time: collection.create_time,
    };
  }

  async createCollection({ knexBook }, payload, user) {
    const uid = this._uid(user);
    const name = String(payload.name || '').trim();
    if (!name) throw new Error('common.PARAM_ERROR');

    const normalizedPaths = await this._validateAndNormalizePaths(knexBook, payload.path_list);

    const dup = await knexBook('book_collection').where({ uid, name }).first();
    if (dup) {
      const err = new Error('book.BOOK_COLLECTION_NAME_EXISTS');
      err.statusCode = 409;
      throw err;
    }

    const [id] = await knexBook('book_collection').insert({
      uid,
      name,
      path_list: JSON.stringify(normalizedPaths),
      create_time: new Date(),
    });

    return this.getCollection({ knexBook }, id, user);
  }

  async updateCollection({ knexBook }, payload, user) {
    const collectionId = Number(payload.id);
    if (!Number.isFinite(collectionId) || collectionId <= 0) throw new Error('common.PARAM_ERROR');

    const { collection } = await this._ensureCollectionAccess({ knexBook, collectionId, user });

    const name = String(payload.name || '').trim();
    if (!name) throw new Error('common.PARAM_ERROR');

    const normalizedPaths = await this._validateAndNormalizePaths(knexBook, payload.path_list);

    const uid = this._uid(user);
    const dup = await knexBook('book_collection').where({ uid, name }).andWhereNot({ id: collection.id }).first();
    if (dup) {
      const err = new Error('book.BOOK_COLLECTION_NAME_EXISTS');
      err.statusCode = 409;
      throw err;
    }

    await knexBook('book_collection')
      .where({ id: collection.id })
      .update({
        name,
        path_list: JSON.stringify(normalizedPaths),
      });

    return true;
  }

  async deleteCollection({ knexBook }, payload, user) {
    const collectionId = Number(payload.id);
    if (!Number.isFinite(collectionId) || collectionId <= 0) throw new Error('common.PARAM_ERROR');

    const { collection } = await this._ensureCollectionAccess({ knexBook, collectionId, user });
    const affected = await knexBook('book_collection').where({ id: collection.id }).delete();
    return { affected };
  }
}

module.exports = new BookCollectionService();
