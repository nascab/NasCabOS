const dbUtil = require('../dbUtil');
const knexUtil = require('../knexUtil');
const Logger = require('../../utils/logger');

class tableFileFavorite {
  constructor() {
    this.tableName = 'file_favorite';
  }

  async createTable(connection = null) {
    let knex;
    if (connection && connection.knex) {
      knex = connection.knex;
    } else {
      knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    }
    const exists = await knex.schema.hasTable(this.tableName);
    if (!exists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.integer('uid').notNullable();
        table.text('path').notNullable();
        table.timestamp('create_time').defaultTo(knex.fn.now());
      });
      Logger.info(`✅ file_favorite table created`);
    }
  }

  async createIndexes(connection = null) {
    let knex;
    if (connection && connection.knex) {
      knex = connection.knex;
    } else {
      knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    }
    const idxName = 'idx_fav_uid_path_unique';
    const existing = await knex.raw("SELECT name FROM sqlite_master WHERE type='index' AND name=?", [idxName]);
    if (existing.length === 0) {
      await knex.schema.alterTable(this.tableName, table => {
        table.unique(['uid', 'path'], idxName);
      });
      Logger.info(`✅ file_favorite unique index created`);
    }
    const idxUid = 'idx_fav_uid';
    const existingUid = await knex.raw("SELECT name FROM sqlite_master WHERE type='index' AND name=?", [idxUid]);
    if (existingUid.length === 0) {
      await knex.schema.alterTable(this.tableName, table => {
        table.index(['uid'], idxUid);
      });
      Logger.info(`✅ file_favorite index (uid) created`);
    }
  }
}

module.exports = new tableFileFavorite();
