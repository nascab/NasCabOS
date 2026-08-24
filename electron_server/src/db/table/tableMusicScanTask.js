const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tableMusicScanTask {
  constructor() {
    this.tableName = 'music_scan_task';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MUSIC_DB);
    const tableExists = await knex.schema.hasTable(this.tableName);
    if (!tableExists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.text('scan_path');
        table.text('remark');
        table.timestamp('create_time').defaultTo(knex.fn.now());
      });
      Logger.info(`✅ Table ${this.tableName} created`);
    }
  }

  async createIndexes(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MUSIC_DB);
    const existingIndexes = await knex.raw(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='${this.tableName}'`);
    const indexNames = Array.isArray(existingIndexes) ? existingIndexes.map(row => row.name) : (existingIndexes?.rows || []).map(row => row.name);

    const targetIndexes = [
      { columns: ['scan_path'], name: 'idx_music_scan_task_scan_path', unique: false },
      { columns: ['create_time'], name: 'idx_music_scan_task_create_time', unique: false },
    ];

    for (const index of targetIndexes) {
      if (!indexNames.includes(index.name)) {
        await knex.schema.alterTable(this.tableName, table => {
          table.index(index.columns, index.name);
        });
        Logger.info(`✅ Created index ${index.name} on table ${this.tableName}`);
      }
    }
  }

  async hasAnyTask(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MUSIC_DB);
    const row = await knex(this.tableName)
      .first('id')
      .catch(() => null);
    return !!(row && row.id);
  }

  async enqueueScanPaths(scanPaths = [], remark = '', connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MUSIC_DB);

    const unique = new Set();
    for (const p of scanPaths || []) {
      const s = p ? String(p) : '';
      if (s) unique.add(s);
    }
    const list = Array.from(unique);
    if (list.length === 0) return 0;

    const inserted = await knex.transaction(async trx => {
      const existingRows = await trx(this.tableName)
        .select('scan_path')
        .whereIn('scan_path', list)
        .catch(() => []);
      const existing = new Set();
      for (const r of existingRows || []) {
        const s = r && r.scan_path ? String(r.scan_path) : '';
        if (s) existing.add(s);
      }

      const toInsert = [];
      for (const p of list) {
        if (!existing.has(p)) {
          toInsert.push({
            scan_path: p,
            remark: remark ? String(remark) : '',
            create_time: new Date(),
          });
        }
      }

      if (toInsert.length === 0) return 0;
      await trx(this.tableName).insert(toInsert);
      return toInsert.length;
    });

    if (inserted > 0) Logger.info(`✅ Added ${inserted} music scan task(s)`);
    return inserted;
  }
}

module.exports = new tableMusicScanTask();
