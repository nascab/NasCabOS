function createFavoriteOps({ getKnex }) {
  async function batchFavorite(user, file_hashes, is_favorite) {
    const knex = getKnex();
    const uid = user.id;

    if (!file_hashes || file_hashes.length === 0) return;

    if (is_favorite) {
      const existing = await knex('photo_favorite').where({ uid }).whereIn('file_hash', file_hashes).select('file_hash');

      const existingHashes = new Set(existing.map(e => e.file_hash));
      const toInsert = file_hashes.filter(h => !existingHashes.has(h)).map(h => ({ uid, file_hash: h }));

      if (toInsert.length > 0) {
        await knex('photo_favorite').insert(toInsert);
      }
      return;
    }

    await knex('photo_favorite').where({ uid }).whereIn('file_hash', file_hashes).del();
  }

  async function toggleFavorite(user, file_hash) {
    const knex = getKnex();
    const uid = user.id;
    const existing = await knex('photo_favorite').where({ uid: uid, file_hash }).first();

    if (existing) {
      await knex('photo_favorite').where({ id: existing.id }).del();
      return { is_favorite: false };
    }

    await knex('photo_favorite').insert({
      uid: uid,
      file_hash,
    });
    return { is_favorite: true };
  }

  return {
    batchFavorite,
    toggleFavorite,
  };
}

module.exports = { createFavoriteOps };
