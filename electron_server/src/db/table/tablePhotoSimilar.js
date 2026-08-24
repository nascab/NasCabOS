const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');
const tablePhotoIndex = require('./tablePhotoIndex');

class tablePhotoSimilar {
  constructor() {
    this.tableName = 'photo_similar';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);

    const exists = await knex.schema.hasTable(this.tableName);
    if (!exists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.integer('index_id').notNullable();
        table.text('similar_file_hash').notNullable();
        table.timestamp('create_time').defaultTo(knex.fn.now());
      });
      Logger.info(`✅ Table ${this.tableName} created`);
      return;
    }

    const info = await knex.raw(`PRAGMA table_info('${this.tableName}')`).catch(() => null);
    const rows = Array.isArray(info) ? info : ((info?.rows || info) ?? []);
    const colNames = new Set((rows || []).map(r => (r && r.name ? String(r.name) : '')).filter(Boolean));

    const addColumn = async (name, sqlType) => {
      try {
        await knex.raw(`ALTER TABLE ${this.tableName} ADD COLUMN ${name} ${sqlType}`);
      } catch (_) {}
    };

    if (!colNames.has('index_id')) {
      await addColumn('index_id', 'INTEGER NOT NULL DEFAULT 0');
    }
    if (!colNames.has('similar_file_hash')) {
      await addColumn('similar_file_hash', "TEXT NOT NULL DEFAULT '[]'");
    }
    if (!colNames.has('create_time')) {
      await addColumn('create_time', "TIMESTAMP DEFAULT (datetime('now'))");
    }
  }

  async createIndexes(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);

    const existingIndexes = await knex.raw(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='${this.tableName}'`);
    const indexNames = Array.isArray(existingIndexes) ? existingIndexes.map(row => row.name) : (existingIndexes?.rows || []).map(row => row.name);

    const targetIndexes = [
      { columns: ['index_id'], name: 'uidx_photo_similar_index_id', unique: true },
      { columns: ['create_time'], name: 'idx_photo_similar_create_time', unique: false },
    ];

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

    if (tablePhotoIndex && typeof tablePhotoIndex.createTriggers === 'function') {
      await tablePhotoIndex.createTriggers(connection).catch(() => {});
    }
  }
}

module.exports = new tablePhotoSimilar();
