const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');
const tableMusicIndex = require('./tableMusicIndex');

class tableBookHistory {
  constructor() {
    this.tableName = 'music_history';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MUSIC_DB);
    const exists = await knex.schema.hasTable(this.tableName);
    if (!exists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.integer('uid').notNullable();
        table.integer('index_id').notNullable();
        table.timestamp('last_listen_at').defaultTo(knex.fn.now());
        table.timestamp('create_time').defaultTo(knex.fn.now());
        table.integer('play_count').defaultTo(0);
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
    if (!colNames.has('last_listen_at')) {
      await addColumn('last_listen_at', "TIMESTAMP DEFAULT (datetime('now'))");
    }
    if (!colNames.has('create_time')) {
      await addColumn('create_time', "TIMESTAMP DEFAULT (datetime('now'))");
    }
    if (!colNames.has('play_count')) {
      await addColumn('play_count', 'INTEGER DEFAULT 0');
    }

    if (colNames.has('file_hash')) {
      await knex
        .raw(
          `
          UPDATE ${this.tableName}
          SET index_id = (
            SELECT id FROM music_index
            WHERE music_index.file_hash = ${this.tableName}.file_hash
            LIMIT 1
          )
          WHERE (index_id IS NULL OR index_id = 0)
            AND file_hash IS NOT NULL
            AND trim(file_hash) != ''
          `
        )
        .catch(() => {});
    }
  }

  async createIndexes(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MUSIC_DB);
    const existingIndexes = await knex.raw(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='${this.tableName}'`);
    const indexNames = new Set((Array.isArray(existingIndexes) ? existingIndexes : existingIndexes?.rows || []).map(row => (row && row.name ? String(row.name) : '')));

    const dropIfExists = async name => {
      if (!name) return;
      await knex.raw(`DROP INDEX IF EXISTS ${name}`).catch(() => {});
      indexNames.delete(name);
    };

    await dropIfExists('uidx_music_history_uid_file_hash');
    await dropIfExists('uidx_music_history_last_listen_at');
    await dropIfExists('uidx_music_history_uid_index_id');

    await knex
      .raw(
        `
        DELETE FROM ${this.tableName}
        WHERE index_id IS NULL OR index_id <= 0
        `
      )
      .catch(() => {});

    await knex
      .raw(
        `
        DELETE FROM ${this.tableName} AS h1
        WHERE (h1.index_id IS NOT NULL AND h1.index_id > 0)
          AND EXISTS (
            SELECT 1 FROM ${this.tableName} AS h2
            WHERE h2.uid = h1.uid
              AND h2.index_id = h1.index_id
              AND (
                h2.last_listen_at > h1.last_listen_at
                OR (h2.last_listen_at = h1.last_listen_at AND h2.rowid > h1.rowid)
              )
          )
        `
      )
      .catch(() => {});

    const targets = [
      {
        name: 'uidx_music_history_uid_index_id',
        sql: `CREATE UNIQUE INDEX uidx_music_history_uid_index_id ON ${this.tableName}(uid, index_id)`,
      },
      { name: 'idx_music_history_uid', sql: `CREATE INDEX idx_music_history_uid ON ${this.tableName}(uid)` },
      {
        name: 'idx_music_history_uid_last_listen_at',
        sql: `CREATE INDEX idx_music_history_uid_last_listen_at ON ${this.tableName}(uid, last_listen_at DESC)`,
      },
      { name: 'idx_music_history_index_id', sql: `CREATE INDEX idx_music_history_index_id ON ${this.tableName}(index_id)` },
    ];

    for (const t of targets) {
      if (indexNames.has(t.name)) continue;
      await knex.raw(t.sql).catch(() => {});
      Logger.info(`✅ Created index ${t.name} on table ${this.tableName}`);
    }

    if (tableMusicIndex && typeof tableMusicIndex.createTriggers === 'function') {
      await tableMusicIndex.createTriggers(connection).catch(() => {});
    }
  }
}

module.exports = new tableBookHistory();
