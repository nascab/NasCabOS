const dbUtil = require('../dbUtil');
const knexUtil = require('../knexUtil');
const Logger = require('../../utils/logger');

class tablePhotoFavorite {
  constructor() {
    this.tableName = 'photo_favorite';
  }

  async createTable(connection = null) {
    let knex;
    if (connection && connection.knex) {
      knex = connection.knex;
    } else {
      knex = knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);
    }
    const exists = await knex.schema.hasTable(this.tableName);
    if (!exists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.integer('uid').notNullable();
        table.string('file_hash').notNullable();
        table.timestamp('create_time').defaultTo(knex.fn.now());
      });
      Logger.info(`✅ photo_favorite table created`);
    }
  }

  async createIndexes(connection = null) {
    let knex;
    if (connection && connection.knex) {
      knex = connection.knex;
    } else {
      knex = knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);
    }
    const idxName = 'idx_photo_fav_uid_hash_unique';
    const existing = await knex.raw("SELECT name FROM sqlite_master WHERE type='index' AND name=?", [idxName]);
    if (existing.length === 0 || (existing.rows && existing.rows.length === 0)) {
      await knex.schema.alterTable(this.tableName, table => {
        table.unique(['uid', 'file_hash'], idxName);
      });
      Logger.info(`✅ photo_favorite unique index created`);
    }
    const idxUid = 'idx_photo_fav_uid';
    const existingUid = await knex.raw("SELECT name FROM sqlite_master WHERE type='index' AND name=?", [idxUid]);
    if (existingUid.length === 0 || (existingUid.rows && existingUid.rows.length === 0)) {
      await knex.schema.alterTable(this.tableName, table => {
        table.index(['uid'], idxUid);
      });
      Logger.info(`✅ photo_favorite index (uid) created`);
    }
  }
}

module.exports = new tablePhotoFavorite();
