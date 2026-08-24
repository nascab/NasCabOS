const dbUtil = require('../dbUtil');
const knexUtil = require('../knexUtil');
const Logger = require('../../utils/logger');

class tableFileRecent {
  constructor() {
    this.tableName = 'file_recent';
  }

  _getKnex(connection = null) {
    if (connection && connection.knex) return connection.knex;
    return knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
  }

  async createTable(connection = null) {
    const knex = this._getKnex(connection);
    const exists = await knex.schema.hasTable(this.tableName);
    if (!exists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.integer('uid').notNullable();
        table.text('path').notNullable();
        table.timestamp('check_time').defaultTo(knex.fn.now());
      });
      Logger.info(`✅ table file_recent created`);
    }
  }

  async createIndexes(connection = null) {
    const knex = this._getKnex(connection);

    const idxUnique = 'idx_recent_uid_path_unique';
    const existingUnique = await knex.raw("SELECT name FROM sqlite_master WHERE type='index' AND name=?", [idxUnique]);
    if (existingUnique.length === 0) {
      await knex.schema.alterTable(this.tableName, table => {
        table.unique(['uid', 'path'], idxUnique);
      });
      Logger.info(`✅ file_recent unique index created`);
    }

    const idxUidTime = 'idx_recent_uid_check_time';
    const existingUidTime = await knex.raw("SELECT name FROM sqlite_master WHERE type='index' AND name=?", [idxUidTime]);
    if (existingUidTime.length === 0) {
      await knex.schema.alterTable(this.tableName, table => {
        table.index(['uid', 'check_time'], idxUidTime);
      });
      Logger.info(`✅ file_recent index (uid,check_time) created`);
    }
  }

  async upsertRecent(uid, filePath, connection = null) {
    const knex = this._getKnex(connection);
    await knex(this.tableName)
      .insert({
        uid,
        path: filePath,
        check_time: knex.fn.now(),
      })
      .onConflict(['uid', 'path'])
      .merge({ check_time: knex.fn.now() });
  }

  async listRecentByUid(uid, limit = 100, connection = null) {
    const knex = this._getKnex(connection);
    return knex(this.tableName).where({ uid }).select(['id', 'path', 'check_time']).orderBy('check_time', 'desc').limit(limit);
  }

  async deleteByUidAndPath(uid, filePath, connection = null) {
    const knex = this._getKnex(connection);
    await knex(this.tableName).where({ uid, path: filePath }).del();
  }

  async deleteByUidAndPaths(uid, filePaths = [], connection = null) {
    const knex = this._getKnex(connection);
    const list = Array.isArray(filePaths) ? filePaths.map(p => (p === null || p === undefined ? '' : String(p).trim())).filter(Boolean) : [];
    if (list.length === 0) return 0;

    const chunkSize = 200;
    let affectedTotal = 0;
    for (let i = 0; i < list.length; i += chunkSize) {
      const chunk = list.slice(i, i + chunkSize);
      const affected = await knex(this.tableName)
        .where({ uid })
        .whereIn('path', chunk)
        .del()
        .catch(() => 0);
      affectedTotal += Number(affected || 0) || 0;
    }
    return affectedTotal;
  }

  async deleteAllByUid(uid, connection = null) {
    const knex = this._getKnex(connection);
    await knex(this.tableName).where({ uid }).del();
  }

  async cleanupByUid(uid, keep = 100, connection = null) {
    const knex = this._getKnex(connection);
    const subQuery = knex(this.tableName).where({ uid }).select('id').orderBy('check_time', 'desc').limit(keep);

    await knex(this.tableName).where({ uid }).whereNotIn('id', subQuery).del();
  }
}

module.exports = new tableFileRecent();
