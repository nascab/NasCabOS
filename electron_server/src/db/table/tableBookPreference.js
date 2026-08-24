const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tableBookPreference {
  constructor() {
    this.tableName = 'book_preference';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.BOOK_DB);
    const exists = await knex.schema.hasTable(this.tableName);
    if (!exists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.integer('uid').notNullable();
        table.text('file_hash').notNullable();
        table.integer('font_size').defaultTo(16);
        table.float('spacing').defaultTo(1.4);
        table.text('flow').defaultTo('paginated');
        table.text('theme').defaultTo('light');
        table.timestamp('updated_at').defaultTo(knex.fn.now());
        table.timestamp('create_time').defaultTo(knex.fn.now());
      });
      Logger.info(`✅ Table ${this.tableName} created`);
    }
  }

  async createIndexes(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.BOOK_DB);
    const idxName = 'idx_book_preference_uid_hash_unique';
    const existing = await knex.raw("SELECT name FROM sqlite_master WHERE type='index' AND name=?", [idxName]).catch(() => []);
    const rows = Array.isArray(existing) ? existing : existing?.rows || [];
    const exists = Array.isArray(rows) ? rows.length > 0 : false;
    if (!exists) {
      await knex.schema.alterTable(this.tableName, table => {
        table.unique(['uid', 'file_hash'], idxName);
      });
      Logger.info(`✅ ${this.tableName} unique index created`);
    }
  }
}

module.exports = new tableBookPreference();
