const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tableBookSource {
  constructor() {
    this.tableName = 'book_source';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.BOOK_DB);

    const tableExists = await knex.schema.hasTable(this.tableName);
    if (!tableExists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.string('path').notNullable();
        table.integer('scan_when_start').defaultTo(0);
        table.integer('scan_when_change').defaultTo(1);
        table.integer('is_show').defaultTo(1);
        table.datetime('ctime');
        table.integer('scan_interval').defaultTo(0);
        table.integer('scan_interval_ms').defaultTo(0);
        table.string('scan_interval_config');
        table.integer('last_scan_time').defaultTo(0);
        table.string('show_type'); //以文件为单元展示 或以文件夹为单元展示 book series
      });
      Logger.info(`✅ Table ${this.tableName} created`);
    }
  }

  async getScanWhenStartPaths(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.BOOK_DB);

    const rows = await knex(this.tableName)
      .select('path')
      .where({ scan_when_start: 1 })
      .catch(err => {
        Logger.error('❌ book source query failed:', err);
        return [];
      });

    const unique = new Set();
    for (const row of rows || []) {
      const p = row && row.path ? String(row.path) : '';
      if (p) unique.add(p);
    }
    return Array.from(unique);
  }

  async createIndexes(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.BOOK_DB);

    const existingIndexes = await knex.raw(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='${this.tableName}'`);
    const indexNames = Array.isArray(existingIndexes) ? existingIndexes.map(row => row.name) : (existingIndexes?.rows || []).map(row => row.name);

    const targetIndexes = [{ columns: ['path'], name: 'uidx_book_source_path', unique: true }];

    for (const index of targetIndexes) {
      if (!indexNames.includes(index.name)) {
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
}

module.exports = new tableBookSource();
