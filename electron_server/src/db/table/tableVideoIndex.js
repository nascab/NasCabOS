const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tableVideoIndex {
  constructor() {
    this.tableName = 'video_index';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);
    const tableExists = await knex.schema.hasTable(this.tableName);
    if (!tableExists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.string('path').notNullable();
        table.string('filename').notNullable();
        table.string('filename_fl').defaultTo('');
        table.string('ext').defaultTo('');
        table.integer('is_file').notNullable().defaultTo(1);
        table.string('file_hash').defaultTo('');
        table.string('play_rel_path').defaultTo('');
        table.string('nfo_name').defaultTo('');
        table.string('nfo_name_fl').defaultTo('');
        table.string('media_type').defaultTo('');
        table.integer('season_count').notNullable().defaultTo(0);
        table.integer('episod_count').notNullable().defaultTo(0);
        table.integer('size').notNullable().defaultTo(0);
        table.integer('width').notNullable().defaultTo(0);
        table.integer('height').notNullable().defaultTo(0);
        table.integer('duration').notNullable().defaultTo(0);
        table.text('nfo_alias').defaultTo('');
        table.text('nfo_tags').defaultTo('');
        table.text('nfo_regions').defaultTo('');
        table.text('nfo_language').defaultTo('');
        table.string('nfo_imdb_id').defaultTo('');
        table.text('nfo_genres').defaultTo('');
        table.date('nfo_release_date');
        table.text('nfo_storyline').defaultTo('');
        table.float('nfo_score').notNullable().defaultTo(0);
        table.integer('nfo_year').notNullable().defaultTo(0);
        table.text('nfo_actor').defaultTo('');
        table.text('nfo_director').defaultTo('');
        table.text('poster_path').defaultTo(''); //海报路径
        table.text('fanart_path').defaultTo(''); //横版海报图路径
        table.text('logo_path').defaultTo(''); //logo图路径
        table.text('nfo_actor_json').defaultTo('[]');
        table.text('nfo_director_json').defaultTo('[]');
        table.integer('open_skip_start_sec').notNullable().defaultTo(0);
        table.integer('open_skip_end_sec').notNullable().defaultTo(0);
        table.integer('nfo_get_state').notNullable().defaultTo(0);
        table.integer('gen_subtitle_vtt').notNullable().defaultTo(0);
        table.integer('gen_tiny').notNullable().defaultTo(0);
        table.integer('episod_num').notNullable().defaultTo(0);
        table.timestamp('create_time').defaultTo(knex.fn.now());
        table.timestamp('view_time');
      });
      Logger.info(`✅ Table ${this.tableName} created`);
    } else {
      const result = await knex.raw(`PRAGMA table_info(${this.tableName})`).catch(() => []);
      const rows = Array.isArray(result) ? result : result?.rows || [];
      const colNames = new Set((rows || []).map(r => (r && r.name ? String(r.name) : '')).filter(Boolean));
      const addColumn = async (name, sqlType) => {
        if (colNames.has(name)) return;
        await knex.raw(`ALTER TABLE ${this.tableName} ADD COLUMN ${name} ${sqlType}`);
        Logger.info(`✅ Added ${name} column to table ${this.tableName}`);
      };
      await addColumn('play_rel_path', "TEXT DEFAULT ''");
      await addColumn('gen_subtitle_vtt', 'INTEGER NOT NULL DEFAULT 0');
    }
  }

  async createIndexes(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);
    const existingIndexes = await knex.raw(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='${this.tableName}'`);
    const indexNames = Array.isArray(existingIndexes) ? existingIndexes.map(row => row.name) : (existingIndexes?.rows || []).map(row => row.name);

    const targetIndexes = [
      { columns: ['path', 'filename'], name: 'uidx_video_index_path_filename', unique: true },

      { columns: ['path', 'filename', 'media_type', 'create_time'], name: 'idx_video_index_path_filename_media_type_create_time', unique: false },
      { columns: ['path', 'filename', 'media_type', 'view_time'], name: 'idx_video_index_path_filename_media_type_view_time', unique: false },
      { columns: ['path', 'filename', 'media_type', 'nfo_regions'], name: 'idx_video_index_path_filename_media_type_nfo_regions', unique: false },
      { columns: ['path', 'filename', 'media_type', 'nfo_language'], name: 'idx_video_index_path_filename_media_type_nfo_language', unique: false },
      { columns: ['path', 'filename', 'media_type', 'nfo_genres'], name: 'idx_video_index_path_filename_media_type_nfo_genres', unique: false },
      { columns: ['path', 'filename', 'media_type', 'nfo_release_date'], name: 'idx_video_index_path_filename_media_type_nfo_release_date', unique: false },
      { columns: ['path', 'filename', 'media_type', 'nfo_score'], name: 'idx_video_index_path_filename_media_type_nfo_score', unique: false },
      { columns: ['path', 'filename', 'media_type', 'nfo_director'], name: 'idx_video_index_path_filename_media_type_nfo_director', unique: false },
      { columns: ['path', 'filename', 'media_type', 'nfo_actor'], name: 'idx_video_index_path_filename_media_type_nfo_actor', unique: false },
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
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);
    const triggers = [
      {
        name: 'trg_video_index_delete_video_index2key',
        sql: `
          CREATE TRIGGER trg_video_index_delete_video_index2key
          AFTER DELETE ON video_index
          FOR EACH ROW
          BEGIN
            DELETE FROM video_index2key WHERE index_id = OLD.id;
          END;
        `,
      },
      {
        name: 'trg_video_index_delete_video_favorite',
        sql: `
          CREATE TRIGGER trg_video_index_delete_video_favorite
          AFTER DELETE ON video_index
          FOR EACH ROW
          BEGIN
            DELETE FROM video_favorite WHERE index_id = OLD.id;
          END;
        `,
      },
    ];

    for (const t of triggers) {
      const existing = await knex.raw("SELECT name FROM sqlite_master WHERE type='trigger' AND name=?", [t.name]);
      const triggerExists = Array.isArray(existing) ? existing.length > 0 : (existing?.rows || []).length > 0;
      if (triggerExists) continue;
      await knex.raw(t.sql);
      Logger.info(`✅ Created trigger ${t.name} on table ${this.tableName}`);
    }
  }
}

module.exports = new tableVideoIndex();
