const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tableMusicIndex {
  constructor() {
    this.tableName = 'music_index';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MUSIC_DB);
    const tableExists = await knex.schema.hasTable(this.tableName);
    if (!tableExists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.string('path').notNullable();
        table.string('filename').notNullable();
        table.string('ext').defaultTo('');
        table.integer('size').defaultTo(0);
        table.integer('duration').defaultTo(0);
        table.string('file_hash').defaultTo('');
        table.datetime('ctime');
        table.datetime('mtime');
        table.datetime('birthtime');
        table.string('title').defaultTo('');
        table.string('title_fl');
        table.string('artist').defaultTo('');
        table.string('artist_fl');
        table.string('album').defaultTo('');
        table.string('album_fl');
        table.string('year');
        table.string('genre');
        table.string('lyrics');
        table.string('stream_info');
        table.integer('bitrate'); // 码率
        table.integer('sample_rate'); // 采样率
        table.integer('bit_depth'); // 位深
        table.integer('lyrics_get_state').defaultTo(0);
        table.integer('has_inner_cover').defaultTo(0); // 是否有内置封面
        table.string('show_type'); // music（单体音乐，文件） series（系列音乐、文件夹） submusic（系列音乐下的子音乐，文件）
        table.integer('music_count').defaultTo(0); //series(系列)目录下的音乐数量
        table.integer('play_count').defaultTo(0); // 播放次数
      });
      Logger.info(`✅ Table ${this.tableName} created`);
    }
  }

  async createIndexes(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MUSIC_DB);
    const existingIndexes = await knex.raw(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='${this.tableName}'`);
    const indexNames = Array.isArray(existingIndexes) ? existingIndexes.map(row => row.name) : (existingIndexes?.rows || []).map(row => row.name);

    const targetIndexes = [
      { columns: ['path', 'filename'], name: 'uidx_music_index_path_filename', unique: true },
      { columns: ['path'], name: 'idx_music_index_path', unique: false },
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

    await this.createTriggers({ knex });
  }

  async createTriggers(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MUSIC_DB);
    const hasPlayListMapTable = await knex.schema.hasTable('play_list2index').catch(() => false);
    const hasFavoriteTable = await knex.schema.hasTable('music_favorite').catch(() => false);
    const hasHistoryTable = await knex.schema.hasTable('music_history').catch(() => false);
    const triggers = [
      {
        name: 'trg_music_index_delete_music_index2key',
        sql: `
          CREATE TRIGGER trg_music_index_delete_music_index2key
          AFTER DELETE ON music_index
          FOR EACH ROW
          BEGIN
            DELETE FROM music_index2key WHERE index_id = OLD.id;
          END;
        `,
      },
    ];

    if (hasPlayListMapTable) {
      triggers.push({
        name: 'trg_music_index_delete_play_list2index',
        sql: `
          CREATE TRIGGER trg_music_index_delete_play_list2index
          AFTER DELETE ON music_index
          FOR EACH ROW
          BEGIN
            DELETE FROM play_list2index WHERE index_id = OLD.id;
          END;
        `,
      });
    }

    if (hasFavoriteTable) {
      triggers.push({
        name: 'trg_music_index_delete_music_favorite',
        sql: `
          CREATE TRIGGER trg_music_index_delete_music_favorite
          AFTER DELETE ON music_index
          FOR EACH ROW
          BEGIN
            DELETE FROM music_favorite WHERE index_id = OLD.id;
          END;
        `,
      });
    }

    if (hasHistoryTable) {
      triggers.push({
        name: 'trg_music_index_delete_music_history',
        sql: `
          CREATE TRIGGER trg_music_index_delete_music_history
          AFTER DELETE ON music_index
          FOR EACH ROW
          BEGIN
            DELETE FROM music_history WHERE index_id = OLD.id;
          END;
        `,
      });
    }

    for (const t of triggers) {
      const existing = await knex.raw("SELECT name FROM sqlite_master WHERE type='trigger' AND name=?", [t.name]);
      const triggerExists = Array.isArray(existing) ? existing.length > 0 : (existing?.rows || []).length > 0;
      if (triggerExists) continue;
      await knex.raw(t.sql);
      Logger.info(`✅ Created trigger ${t.name} on table ${this.tableName}`);
    }
  }
}

module.exports = new tableMusicIndex();
