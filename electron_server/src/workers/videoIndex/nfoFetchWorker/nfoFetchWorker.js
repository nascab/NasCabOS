'use strict';

const Logger = require('../../../utils/logger');
const { NfoFetchRunner } = require('./nfoFetchRunner');

class NfoFetchWorker {
  constructor() {
    this.runner = new NfoFetchRunner();
    this.init();
  }

  async init() {
    try {
      await this.runner.init();

      await this.runUntilEmpty();
      process.exit(0);
    } catch (err) {
      Logger.error('❌ nfoFetchWorker init failed:', err);
      process.exit(1);
    }
  }

  async runUntilEmpty() {
    while (true) {
      const { processed } = await this.runner.runOnce({ limit: 5 });
      if (!processed) {
        Logger.info('✅ No pending NFO fetch tasks, worker exiting');
        return;
      }
    }
  }
}

new NfoFetchWorker();

process.on('message', message => {
  if (message && message.type === 'stop') {
    process.exit(0);
  }
});

process.on('uncaughtException', err => {
  Logger.error('❌ nfoFetch worker uncaughtException', err);
  process.exit(0);
});

process.on('unhandledRejection', reason => {
  Logger.error('❌ nfoFetch worker unhandledRejection', reason);
  process.exit(0);
});
