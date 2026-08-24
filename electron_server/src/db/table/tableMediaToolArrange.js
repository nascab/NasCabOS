const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tableMediaToolArrange {
  static STATUS_STOPPED = 'stopped';
  static STATUS_RUNNING = 'running';
  static STATUS_ERROR = 'error';
  static STATUS_FINISHED = 'finished';

  static ARRANGE_TYPE_YEAR = 'year';
  static ARRANGE_TYPE_MONTH = 'month';
  static ARRANGE_TYPE_DAY = 'day';

  static SAME_NAME_POLICY_SKIP = 'skip';
  static SAME_NAME_POLICY_RENAME = 'rename';
  static SAME_NAME_POLICY_OVERWRITE = 'overwrite';

  constructor() {
    this.tableName = 'media_tool_arrange';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const tableExists = await knex.schema.hasTable(this.tableName);
    if (!tableExists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.text('source_path').notNullable();
        table.text('target_path').notNullable();
        table
          .enu('arrange_type', [tableMediaToolArrange.ARRANGE_TYPE_YEAR, tableMediaToolArrange.ARRANGE_TYPE_MONTH, tableMediaToolArrange.ARRANGE_TYPE_DAY])
          .notNullable()
          .defaultTo(tableMediaToolArrange.ARRANGE_TYPE_YEAR);

        table
          .enu('same_name_policy', [tableMediaToolArrange.SAME_NAME_POLICY_SKIP, tableMediaToolArrange.SAME_NAME_POLICY_RENAME, tableMediaToolArrange.SAME_NAME_POLICY_OVERWRITE])
          .notNullable()
          .defaultTo(tableMediaToolArrange.SAME_NAME_POLICY_RENAME);

        table
          .enu('status', [tableMediaToolArrange.STATUS_STOPPED, tableMediaToolArrange.STATUS_RUNNING, tableMediaToolArrange.STATUS_ERROR, tableMediaToolArrange.STATUS_FINISHED])
          .notNullable()
          .defaultTo(tableMediaToolArrange.STATUS_STOPPED);

        table.text('last_error').nullable();
        table.text('progress').notNullable().defaultTo('');

        table.integer('total_files').notNullable().defaultTo(0);
        table.integer('done_files').notNullable().defaultTo(0);
        table.integer('processed_count').notNullable().defaultTo(0);
        table.integer('skipped_count').notNullable().defaultTo(0);

        table.timestamp('create_time').defaultTo(knex.fn.now());
        table.timestamp('update_time').defaultTo(knex.fn.now());
        table.timestamp('last_start_time').nullable();
        table.timestamp('last_end_time').nullable();
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

    if (!colNames.has('same_name_policy')) {
      await addColumn('same_name_policy', `TEXT NOT NULL DEFAULT '${tableMediaToolArrange.SAME_NAME_POLICY_RENAME}'`);
    }
  }

  async createIndexes(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const existingIndexes = await knex.raw(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='${this.tableName}'`);
    const rows = Array.isArray(existingIndexes) ? existingIndexes : existingIndexes?.rows || [];
    const indexNames = rows.map(row => row.name);

    const targetIndexes = [
      { columns: ['status'], name: 'idx_media_tool_arrange_status', unique: false },
      { columns: ['create_time'], name: 'idx_media_tool_arrange_create_time', unique: false },
      { columns: ['update_time'], name: 'idx_media_tool_arrange_update_time', unique: false },
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

const instance = new tableMediaToolArrange();
instance.STATUS_STOPPED = tableMediaToolArrange.STATUS_STOPPED;
instance.STATUS_RUNNING = tableMediaToolArrange.STATUS_RUNNING;
instance.STATUS_ERROR = tableMediaToolArrange.STATUS_ERROR;
instance.STATUS_FINISHED = tableMediaToolArrange.STATUS_FINISHED;

instance.ARRANGE_TYPE_YEAR = tableMediaToolArrange.ARRANGE_TYPE_YEAR;
instance.ARRANGE_TYPE_MONTH = tableMediaToolArrange.ARRANGE_TYPE_MONTH;
instance.ARRANGE_TYPE_DAY = tableMediaToolArrange.ARRANGE_TYPE_DAY;

instance.SAME_NAME_POLICY_SKIP = tableMediaToolArrange.SAME_NAME_POLICY_SKIP;
instance.SAME_NAME_POLICY_RENAME = tableMediaToolArrange.SAME_NAME_POLICY_RENAME;
instance.SAME_NAME_POLICY_OVERWRITE = tableMediaToolArrange.SAME_NAME_POLICY_OVERWRITE;

module.exports = instance;
