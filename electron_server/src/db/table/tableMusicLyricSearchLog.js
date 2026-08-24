const dbUtil = require('../dbUtil');
const knexUtil = require('../knexUtil');
const Logger = require('../../utils/logger');

class tableMusicLyricSearchLog {
  constructor() {
    this.tableName = 'music_lyric_search_log';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MUSIC_DB);
    const exists = await knex.schema.hasTable(this.tableName);
    if (exists) return;

    await knex.schema.createTable(this.tableName, table => {
      table.increments('id').primary();
      table.text('file_name').notNullable();
      table.text('result_json').notNullable().defaultTo('[]');
      table.integer('result_count').notNullable().defaultTo(0);
      table.integer('searched_at').notNullable().defaultTo(0);
      table.timestamp('create_time').defaultTo(knex.fn.now());
    });
    Logger.info(`✅ Table ${this.tableName} created`);
  }

  async createIndexes(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MUSIC_DB);

    const existingIndexes = await knex.raw(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='${this.tableName}'`);
    const indexNames = Array.isArray(existingIndexes) ? existingIndexes.map(row => row.name) : (existingIndexes?.rows || []).map(row => row.name);

    const targetIndexes = [
      {
        columns: ['file_name'],
        name: 'uidx_music_lyric_search_log_file_name',
        unique: true,
      },
      {
        columns: ['searched_at'],
        name: 'idx_music_lyric_search_log_searched_at',
        unique: false,
      },
    ];

    for (const index of targetIndexes) {
      if (indexNames.includes(index.name)) continue;
      await knex.schema.alterTable(this.tableName, table => {
        if (index.unique) {
          table.unique(index.columns, index.name);
        } else {
          table.index(index.columns, index.name);
        }
      });
      Logger.info(`✅ Created index ${index.name} on table ${this.tableName}`);
    }
  }
}

module.exports = new tableMusicLyricSearchLog();
