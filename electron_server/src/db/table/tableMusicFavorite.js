const dbUtil = require('../dbUtil');
const knexUtil = require('../knexUtil');
const Logger = require('../../utils/logger');

class tableMusicFavorite {
  constructor() {
    this.tableName = 'music_favorite';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MUSIC_DB);
    const exists = await knex.schema.hasTable(this.tableName);
    if (!exists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.integer('uid').notNullable();
        table.integer('index_id').notNullable();
        table.timestamp('create_time').defaultTo(knex.fn.now());
      });
      Logger.info(`✅ music_favorite table created`);
    }
  }

  async createIndexes(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MUSIC_DB);

    const idxUnique = 'idx_music_fav_uid_index_unique';
    const existingUnique = await knex.raw("SELECT name FROM sqlite_master WHERE type='index' AND name=?", [idxUnique]);
    const uniqueExists = Array.isArray(existingUnique) ? existingUnique.length > 0 : (existingUnique?.rows || []).length > 0;
    if (!uniqueExists) {
      await knex.schema.alterTable(this.tableName, table => {
        table.unique(['uid', 'index_id'], idxUnique);
      });
      Logger.info(`✅ music_favorite unique index created`);
    }

    const idxUid = 'idx_music_fav_uid';
    const existingUid = await knex.raw("SELECT name FROM sqlite_master WHERE type='index' AND name=?", [idxUid]);
    const uidExists = Array.isArray(existingUid) ? existingUid.length > 0 : (existingUid?.rows || []).length > 0;
    if (!uidExists) {
      await knex.schema.alterTable(this.tableName, table => {
        table.index(['uid'], idxUid);
      });
      Logger.info(`✅ music_favorite index (uid) created`);
    }

    const idxIndexId = 'idx_music_fav_index_id';
    const existingIndexId = await knex.raw("SELECT name FROM sqlite_master WHERE type='index' AND name=?", [idxIndexId]);
    const indexIdExists = Array.isArray(existingIndexId) ? existingIndexId.length > 0 : (existingIndexId?.rows || []).length > 0;
    if (!indexIdExists) {
      await knex.schema.alterTable(this.tableName, table => {
        table.index(['index_id'], idxIndexId);
      });
      Logger.info(`✅ music_favorite index (index_id) created`);
    }

    const idxCreateTime = 'idx_music_fav_uid_create_time';
    const existingCreateTime = await knex.raw("SELECT name FROM sqlite_master WHERE type='index' AND name=?", [idxCreateTime]);
    const createTimeExists = Array.isArray(existingCreateTime) ? existingCreateTime.length > 0 : (existingCreateTime?.rows || []).length > 0;
    if (!createTimeExists) {
      await knex.schema.alterTable(this.tableName, table => {
        table.index(['uid', 'create_time'], idxCreateTime);
      });
      Logger.info(`✅ music_favorite index (uid,create_time) created`);
    }
  }
}

module.exports = new tableMusicFavorite();
