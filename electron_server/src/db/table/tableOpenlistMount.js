const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tableOpenlistMount {
  constructor() {
    this.tableName = 'openlist_mount';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const tableExists = await knex.schema.hasTable(this.tableName);
    if (!tableExists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.string('uid').notNullable();
        table.string('name').notNullable();
        table.string('mount_path').notNullable();
        table.string('local_mount_dir').nullable();
        table.string('openlist_mount_path').notNullable();
        table.integer('openlist_storage_id').nullable();
        table.string('driver').notNullable();
        table.string('remote').notNullable();
        table.string('status').notNullable().defaultTo('stopped');
        table.integer('auto_running').notNullable().defaultTo(0);
        table.text('config').nullable();
        table.text('last_error').nullable();
        table.timestamp('create_time').defaultTo(knex.fn.now());
        table.timestamp('update_time').defaultTo(knex.fn.now());
      });
      Logger.info(`✅ Table ${this.tableName} created`);
    } else {
      const hasLocalMountDir = await knex.schema.hasColumn(this.tableName, 'local_mount_dir');
      if (!hasLocalMountDir) {
        await knex.schema.alterTable(this.tableName, table => {
          table.string('local_mount_dir').nullable();
        });
        Logger.info(`✅ Added column local_mount_dir on table ${this.tableName}`);
      }
    }
  }

  async createIndexes(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const existingIndexes = await knex.raw(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='${this.tableName}'`);
    const rows = Array.isArray(existingIndexes) ? existingIndexes : existingIndexes?.rows || [];
    const indexNames = rows.map(row => row.name);

    const targetIndexes = [
      { columns: ['uid'], name: 'idx_openlist_mount_uid', unique: false },
      { columns: ['status'], name: 'idx_openlist_mount_status', unique: false },
      { columns: ['auto_running'], name: 'idx_openlist_mount_auto_running', unique: false },
      { columns: ['openlist_mount_path'], name: 'uidx_openlist_mount_ol_path', unique: true },
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
      Logger.info(`✅ Created ${index.unique ? 'unique ' : ''}index ${index.name} on table ${this.tableName}`);
    }
  }
}

module.exports = new tableOpenlistMount();
