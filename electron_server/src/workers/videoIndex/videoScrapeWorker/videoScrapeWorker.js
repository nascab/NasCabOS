'use strict';

const Logger = require('../../../utils/logger');
const { NfoFetchRunner } = require('../nfoFetchWorker/nfoFetchRunner');
const ScrapeCleanupUtil = require('../../../api/modules/video/scrape/scrapeCleanupUtil');

let started = false;

async function cleanupOldArtworkAndNfo(runner, indexId) {
  const mode = process.env.SCRAPE_MODE ? String(process.env.SCRAPE_MODE).trim() : '';
  if (mode !== 'manual') return;

  const id = Number(indexId || 0) || 0;
  if (!id || !runner || !runner.knexVideo) return;
  await ScrapeCleanupUtil.cleanupByIndexId(runner.knexVideo, id);
}

async function runJob({ indexId, tmdbId }) {
  const runner = new NfoFetchRunner();
  await runner.init();
  await cleanupOldArtworkAndNfo(runner, indexId);
  const res = await runner.scrapeByIndexId({ indexId, tmdbId });
  return !!(res && res.ok);
}

process.on('message', message => {
  if (!message || !message.type) return;
  if (message.type === 'stop') {
    process.exit(0);
    return;
  }
  if (message.type !== 'start') return;
  if (started) return;
  started = true;

  const data = message.data && typeof message.data === 'object' ? message.data : {};
  const indexId = Number(data.indexId || data.index_id || 0) || 0;
  const tmdbId = data.tmdbId ? Number(data.tmdbId || 0) || 0 : data.tmdb_id ? Number(data.tmdb_id || 0) || 0 : 0;

  Promise.resolve()
    .then(async () => {
      const ok = await runJob({ indexId, tmdbId });
      await new Promise(resolve => setTimeout(resolve, 50));
      process.exit(ok ? 0 : 1);
    })
    .catch(async err => {
      Logger.error('❌ videoScrapeWorker failed', err && err.message ? err.message : err);
      await new Promise(resolve => setTimeout(resolve, 50));
      process.exit(1);
    });
});

process.on('uncaughtException', err => {
  Logger.error('❌ videoScrapeWorker uncaughtException', err);
  process.exit(1);
});

process.on('unhandledRejection', reason => {
  Logger.error('❌ videoScrapeWorker unhandledRejection', reason);
  process.exit(1);
});
