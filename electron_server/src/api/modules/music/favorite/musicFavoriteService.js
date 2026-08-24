class MusicFavoriteService {
  constructor(knexMusic) {
    this.knexMusic = knexMusic;
    this.tableName = 'music_favorite';
  }

  _getUid(user) {
    const uid = user && user.id ? Number(user.id) : 0;
    return uid > 0 ? uid : 0;
  }

  async addFavorite(user, indexId) {
    const uid = this._getUid(user);
    const safeIndexId = Number(indexId) || 0;
    if (!uid || !safeIndexId) return { is_favorite: false };

    const insertRow = {
      uid,
      index_id: safeIndexId,
      create_time: this.knexMusic.fn.now(),
    };

    const q = this.knexMusic(this.tableName).insert(insertRow);
    if (typeof q.onConflict === 'function') {
      await q.onConflict(['uid', 'index_id']).ignore();
    } else {
      try {
        await q;
      } catch (_) {}
    }
    return { is_favorite: true };
  }

  async removeFavorite(user, indexId) {
    const uid = this._getUid(user);
    const safeIndexId = Number(indexId) || 0;
    if (!uid || !safeIndexId) return { is_favorite: false };

    await this.knexMusic(this.tableName)
      .where({ uid, index_id: safeIndexId })
      .del()
      .catch(() => {});
    return { is_favorite: false };
  }

  async batchFavorite(user, indexIds, isFavorite) {
    const uid = this._getUid(user);
    const list = Array.isArray(indexIds) ? indexIds.map(v => Number(v) || 0).filter(v => v > 0) : [];
    const uniqueList = Array.from(new Set(list));
    if (!uid || uniqueList.length === 0) return;

    if (isFavorite) {
      const existingSet = await this.getFavoriteIndexIdSet(user, uniqueList);
      const toInsert = uniqueList
        .filter(id => !existingSet.has(id))
        .map(id => ({
          uid,
          index_id: id,
          create_time: this.knexMusic.fn.now(),
        }));
      if (toInsert.length === 0) return;

      const q = this.knexMusic(this.tableName).insert(toInsert);
      if (typeof q.onConflict === 'function') {
        await q.onConflict(['uid', 'index_id']).ignore();
      } else {
        await q.catch(() => {});
      }
      return;
    }

    await this.knexMusic(this.tableName)
      .where({ uid })
      .whereIn('index_id', uniqueList)
      .del()
      .catch(() => {});
  }

  async getFavoriteIndexIdSet(user, indexIds) {
    const uid = this._getUid(user);
    const list = Array.isArray(indexIds) ? indexIds.map(v => Number(v) || 0).filter(v => v > 0) : [];
    if (!uid || list.length === 0) return new Set();

    const rows = await this.knexMusic(this.tableName)
      .where({ uid })
      .whereIn('index_id', list)
      .select('index_id')
      .catch(() => []);

    return new Set((rows || []).map(r => Number(r && r.index_id) || 0).filter(v => v > 0));
  }
}

module.exports = MusicFavoriteService;
