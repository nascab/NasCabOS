const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tableBookIndex {
  constructor() {
    this.tableName = 'book_index';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.BOOK_DB);
    const tableExists = await knex.schema.hasTable(this.tableName);
    if (!tableExists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();

        table.text('path').notNullable();
        table.boolean('is_file').notNullable().defaultTo(1);
        table.string('file_hash'); // 文件哈希
        table.datetime('ctime');
        table.datetime('mtime');
        table.datetime('birthtime');

        table.text('filename').defaultTo('');
        table.text('filename_fl').defaultTo('');
        table.text('language').defaultTo('');

        table.text('cover_path').defaultTo('');
        table.integer('cover_state').defaultTo(0);
        table.integer('metadata_state').defaultTo(0);

        table.text('title').defaultTo('');
        table.text('title_fl').defaultTo('');
        table.text('artist').defaultTo('');
        table.text('artist_fl').defaultTo('');
        table.text('year').defaultTo('');
        table.text('genre').defaultTo('');
        table.text('isbn').defaultTo('');
        table.text('tag').defaultTo('');
        table.text('publish_date').defaultTo('');
        table.text('publisher').defaultTo('');
        table.text('introduction').defaultTo('');
        table.text('remark').defaultTo('');

        table.text('ext').defaultTo('');
        table.integer('size').defaultTo(0);
        table.text('type'); // book（图书） comic（漫画）
        table.text('show_type'); // series(系列) book(单本) subbook(系列下的某一本)
        table.integer('total_page').defaultTo(0);
        table.integer('book_count').defaultTo(0); //series(系列)目录下的图书数量

        table.timestamp('create_time').defaultTo(knex.fn.now());
        table.integer('view_time').defaultTo(0);
      });
      Logger.info(`✅ Table ${this.tableName} created`);
    }
  }

  async createIndexes(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.BOOK_DB);
    const existingIndexes = await knex.raw(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='${this.tableName}'`);
    const indexNames = Array.isArray(existingIndexes) ? existingIndexes.map(row => row.name) : (existingIndexes?.rows || []).map(row => row.name);

    const targetIndexes = [
      { columns: ['path', 'filename'], name: 'uidx_book_index_path_filename', unique: true },
      { columns: ['title_fl'], name: 'idx_book_index_title_fl', unique: false },
      { columns: ['artist_fl'], name: 'idx_book_index_artist_fl', unique: false },
      { columns: ['isbn'], name: 'idx_book_index_isbn', unique: false },
      { columns: ['create_time'], name: 'idx_book_index_create_time', unique: false },
      { columns: ['view_time'], name: 'idx_book_index_view_time', unique: false },
      { columns: ['cover_state'], name: 'idx_book_index_cover_state', unique: false },
      { columns: ['metadata_state'], name: 'idx_book_index_metadata_state', unique: false },
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
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.BOOK_DB);

    const hasMapTable = await knex.schema.hasTable('book_list2index').catch(() => false);
    const hasFavoriteTable = await knex.schema.hasTable('book_favorite').catch(() => false);
    if (!hasMapTable && !hasFavoriteTable) return;

    const triggers = [
      ...(hasMapTable
        ? [
            {
              name: 'trg_book_index_delete_book_list2index',
              sql: `
                CREATE TRIGGER trg_book_index_delete_book_list2index
                AFTER DELETE ON book_index
                FOR EACH ROW
                BEGIN
                  DELETE FROM book_list2index WHERE index_id = OLD.id;
                END;
              `,
            },
          ]
        : []),
      ...(hasFavoriteTable
        ? [
            {
              name: 'trg_book_index_delete_book_favorite',
              sql: `
                CREATE TRIGGER trg_book_index_delete_book_favorite
                AFTER DELETE ON book_index
                FOR EACH ROW
                BEGIN
                  DELETE FROM book_favorite WHERE index_id = OLD.id;
                END;
              `,
            },
          ]
        : []),
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

module.exports = new tableBookIndex();
