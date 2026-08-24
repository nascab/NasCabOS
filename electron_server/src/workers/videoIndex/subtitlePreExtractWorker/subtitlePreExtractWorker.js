'use strict';

const Logger = require('../../../utils/logger');
const { SubtitlePreExtractRunner } = require('./subtitlePreExtractRunner');

class SubtitlePreExtractWorker {
  constructor() {
    this.runner = new SubtitlePreExtractRunner();
    this.init();
  }

  async init() {
    try {
      await this.runner.init();
      if (!(await this.runner.isEnabled())) {
        Logger.info('📝 subtitle pre-extract disabled, worker exiting');
        process.exit(0);
        return;
      }
      await this.runUntilEmpty();
      process.exit(0);
    } catch (err) {
      Logger.error('❌ subtitlePreExtractWorker init failed:', err);
      process.exit(1);
    }
  }

  async runUntilEmpty() {
    while (true) {
      const { processed, disabled, noAvailableSources } = await this.runner.runOnce();
      if (disabled) {
        Logger.info('📝 subtitle pre-extract disabled during run, worker exiting');
        return;
      }
      if (noAvailableSources) {
        Logger.info('📝 subtitle pre-extract: no mounted video sources, worker exiting');
        return;
      }
      if (!processed) {
        Logger.info('✅ No pending subtitle pre-extract tasks, worker exiting');
        return;
      }
    }
  }
}

new SubtitlePreExtractWorker();

process.on('message', message => {
  if (message && message.type === 'stop') {
    process.exit(0);
  }
});

process.on('uncaughtException', err => {
  Logger.error('❌ subtitlePreExtract worker uncaughtException', err);
  process.exit(0);
});

process.on('unhandledRejection', reason => {
  Logger.error('❌ subtitlePreExtract worker unhandledRejection', reason);
  process.exit(0);
});
