const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class TablePhotoGpsAdd {
  constructor() {
    this.tableName = 'gps_add';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);

    const exists = await knex.schema.hasTable(this.tableName);
    if (!exists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.string('batch_key').notNullable();
        table.integer('source_index_id').notNullable().defaultTo(0);
        table.string('camera').defaultTo('');
        table.integer('status').notNullable().defaultTo(0); // 0 pending, 1 applied, 2 skipped
        table.float('latitude').defaultTo(0);
        table.float('longitude').defaultTo(0);
        table.text('reference_index_ids').notNullable().defaultTo('[]');
        table.text('pending_index_ids').notNullable().defaultTo('[]');
        table.integer('window_start').defaultTo(0);
        table.integer('window_end').defaultTo(0);
        table.timestamp('create_time').defaultTo(knex.fn.now());
        table.timestamp('update_time').defaultTo(knex.fn.now());
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

    if (!colNames.has('batch_key')) await addColumn('batch_key', "TEXT NOT NULL DEFAULT ''");
    if (!colNames.has('source_index_id')) await addColumn('source_index_id', 'INTEGER NOT NULL DEFAULT 0');
    if (!colNames.has('camera')) await addColumn('camera', "TEXT DEFAULT ''");
    if (!colNames.has('status')) await addColumn('status', 'INTEGER NOT NULL DEFAULT 0');
    if (!colNames.has('latitude')) await addColumn('latitude', 'REAL DEFAULT 0');
    if (!colNames.has('longitude')) await addColumn('longitude', 'REAL DEFAULT 0');
    if (!colNames.has('reference_index_ids')) await addColumn('reference_index_ids', "TEXT NOT NULL DEFAULT '[]'");
    if (!colNames.has('pending_index_ids')) await addColumn('pending_index_ids', "TEXT NOT NULL DEFAULT '[]'");
    if (!colNames.has('window_start')) await addColumn('window_start', 'INTEGER DEFAULT 0');
    if (!colNames.has('window_end')) await addColumn('window_end', 'INTEGER DEFAULT 0');
    if (!colNames.has('create_time')) await addColumn('create_time', "TIMESTAMP DEFAULT (datetime('now'))");
    if (!colNames.has('update_time')) await addColumn('update_time', "TIMESTAMP DEFAULT (datetime('now'))");
  }

  async createIndexes(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);

    const existingIndexes = await knex.raw(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='${this.tableName}'`);
    const indexNames = Array.isArray(existingIndexes) ? existingIndexes.map(row => row.name) : (existingIndexes?.rows || []).map(row => row.name);

    const targetIndexes = [
      { columns: ['batch_key'], name: 'uidx_gps_add_batch_key', unique: true },
      { columns: ['status', 'create_time'], name: 'idx_gps_add_status_create_time', unique: false },
      { columns: ['source_index_id'], name: 'idx_gps_add_source_index_id', unique: false },
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
  }
}

module.exports = new TablePhotoGpsAdd();
