const dbUtil = require('../dbUtil');
const knexUtil = require('../knexUtil');
const Logger = require('../../utils/logger');

class tableVideoTranscodeSession {
  constructor() {
    this.tableName = 'video_transcode_session';
  }

  _getKnex(connection = null) {
    if (connection && connection.knex) return connection.knex;
    if (connection && connection.schema) return connection;
    return knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);
  }

  async createTable(connection = null) {
    const knex = this._getKnex(connection);
    const exists = await knex.schema.hasTable(this.tableName);
    if (!exists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.text('device_id').defaultTo('');
        table.text('play_id').notNullable();
        table.text('file_path').defaultTo('');
        table.text('options_json').defaultTo('');
        table.integer('base_seek_seconds').notNullable().defaultTo(0);
        table.bigInteger('last_get_hls_time').notNullable().defaultTo(0);
        table.text('last_get_hls_filename').notNullable().defaultTo('');
        table.integer('is_running').notNullable().defaultTo(0);
        table.bigInteger('update_time').notNullable().defaultTo(0);
        table.bigInteger('create_time').notNullable().defaultTo(0);
      });
      Logger.info(`✅ Table ${this.tableName} created`);
    }
  }

  async createIndexes(connection = null) {
    const knex = this._getKnex(connection);

    const idxPlayIdUnique = 'idx_video_transcode_session_play_id_unique';
    const existingPlayIdUnique = await knex.raw("SELECT name FROM sqlite_master WHERE type='index' AND name=?", [idxPlayIdUnique]);
    if (existingPlayIdUnique.length === 0) {
      await knex.schema.alterTable(this.tableName, table => {
        table.unique(['play_id'], idxPlayIdUnique);
      });
      Logger.info(`✅ ${this.tableName} unique index (play_id) created`);
    }

    const idxDeviceRunning = 'idx_video_transcode_session_device_running';
    const existingDeviceRunning = await knex.raw("SELECT name FROM sqlite_master WHERE type='index' AND name=?", [idxDeviceRunning]);
    if (existingDeviceRunning.length === 0) {
      await knex.schema.alterTable(this.tableName, table => {
        table.index(['device_id', 'is_running'], idxDeviceRunning);
      });
      Logger.info(`✅ ${this.tableName} index (device_id,is_running) created`);
    }

    const idxLastGetHlsTime = 'idx_video_transcode_session_last_get_hls_time';
    const existingLastGetHlsTime = await knex.raw("SELECT name FROM sqlite_master WHERE type='index' AND name=?", [idxLastGetHlsTime]);
    if (existingLastGetHlsTime.length === 0) {
      await knex.schema.alterTable(this.tableName, table => {
        table.index(['last_get_hls_time'], idxLastGetHlsTime);
      });
      Logger.info(`✅ ${this.tableName} index (last_get_hls_time) created`);
    }
  }

  _normalizeText(v) {
    if (v === undefined || v === null) return '';
    return String(v).trim();
  }

  _nowMs() {
    return Date.now();
  }

  async getByPlayId(playId, connection = null) {
    const knex = this._getKnex(connection);
    const id = this._normalizeText(playId);
    if (!id) return null;
    return knex(this.tableName)
      .where({ play_id: id })
      .first()
      .catch(() => null);
  }

  async listRunningByDeviceId(deviceId, excludePlayId = '', connection = null) {
    const knex = this._getKnex(connection);
    const did = this._normalizeText(deviceId);
    if (!did) return [];
    const ex = this._normalizeText(excludePlayId);
    const q = knex(this.tableName).where({ device_id: did, is_running: 1 });
    if (ex) q.andWhereNot({ play_id: ex });
    return q.select(['play_id', 'device_id', 'file_path', 'options_json', 'base_seek_seconds', 'last_get_hls_time', 'last_get_hls_filename']).catch(() => []);
  }

  async upsertSession({ deviceId, playId, filePath, optionsJson, baseSeekSeconds, isRunning, lastGetHlsTime, lastGetHlsFilename }, connection = null) {
    const knex = this._getKnex(connection);
    const now = this._nowMs();
    const pid = this._normalizeText(playId);
    if (!pid) return false;

    const row = {
      device_id: this._normalizeText(deviceId),
      play_id: pid,
      file_path: this._normalizeText(filePath),
      options_json: this._normalizeText(optionsJson),
      base_seek_seconds: Number.isFinite(Number(baseSeekSeconds)) ? Math.max(0, Math.floor(Number(baseSeekSeconds))) : 0,
      last_get_hls_time: Number.isFinite(Number(lastGetHlsTime)) ? Math.max(0, Math.floor(Number(lastGetHlsTime))) : 0,
      last_get_hls_filename: this._normalizeText(lastGetHlsFilename),
      is_running: Number(isRunning) === 1 ? 1 : 0,
      update_time: now,
      create_time: now,
    };

    await knex(this.tableName)
      .insert(row)
      .onConflict(['play_id'])
      .merge({
        device_id: row.device_id,
        file_path: row.file_path,
        options_json: row.options_json,
        base_seek_seconds: row.base_seek_seconds,
        last_get_hls_time: row.last_get_hls_time,
        last_get_hls_filename: row.last_get_hls_filename,
        is_running: row.is_running,
        update_time: row.update_time,
      })
      .catch(() => null);
    return true;
  }

  async updateHeartbeat(playId, { lastGetHlsTime, lastGetHlsFilename }, connection = null) {
    const knex = this._getKnex(connection);
    const pid = this._normalizeText(playId);
    if (!pid) return false;
    const patch = { update_time: this._nowMs() };
    if (lastGetHlsTime !== undefined) {
      const t = Number(lastGetHlsTime);
      patch.last_get_hls_time = Number.isFinite(t) ? Math.max(0, Math.floor(t)) : 0;
    }
    if (lastGetHlsFilename !== undefined) {
      patch.last_get_hls_filename = this._normalizeText(lastGetHlsFilename);
    }
    const affected = await knex(this.tableName)
      .where({ play_id: pid })
      .update(patch)
      .catch(() => 0);
    return Number(affected || 0) > 0;
  }

  async setRunning(playId, isRunning, connection = null) {
    const knex = this._getKnex(connection);
    const pid = this._normalizeText(playId);
    if (!pid) return false;
    const affected = await knex(this.tableName)
      .where({ play_id: pid })
      .update({ is_running: Number(isRunning) === 1 ? 1 : 0, update_time: this._nowMs() })
      .catch(() => 0);
    return Number(affected || 0) > 0;
  }

  async deleteByPlayId(playId, connection = null) {
    const knex = this._getKnex(connection);
    const pid = this._normalizeText(playId);
    if (!pid) return 0;
    const affected = await knex(this.tableName)
      .where({ play_id: pid })
      .del()
      .catch(() => 0);
    return Number(affected || 0) || 0;
  }

  async deleteOlderThanMs(ageMs, connection = null) {
    const knex = this._getKnex(connection);
    const ms = Number(ageMs);
    if (!Number.isFinite(ms) || ms <= 0) return 0;
    const cutoff = this._nowMs() - Math.floor(ms);
    const affected = await knex(this.tableName)
      .where(qb => {
        qb.where(qb2 => qb2.where('last_get_hls_time', '>', 0).andWhere('last_get_hls_time', '<', cutoff)).orWhere(qb2 =>
          qb2
            .where('last_get_hls_time', '<=', 0)
            .andWhere(qb3 =>
              qb3
                .where(qb4 => qb4.where('update_time', '>', 0).andWhere('update_time', '<', cutoff))
                .orWhere(qb4 => qb4.where('update_time', '<=', 0).andWhere('create_time', '>', 0).andWhere('create_time', '<', cutoff))
            )
        );
      })
      .del()
      .catch(() => 0);
    return Number(affected || 0) || 0;
  }
}

module.exports = new tableVideoTranscodeSession();
