'use strict';

const knexUtil = require('../db/knexUtil');
const dbUtil = require('../db/dbUtil');
const Logger = require('../utils/logger');
const { DockerService, DockerApiError, mapDockerFailure } = require('../api/modules/docker/dockerService');
const dockerTaskManager = require('../api/modules/docker/dockerTaskManager');

function normalizeError(error) {
  const normalized = error instanceof DockerApiError ? error : mapDockerFailure(error);
  return {
    code: normalized && normalized.code ? String(normalized.code) : 'common.ERROR',
    statusCode: Number(normalized && normalized.statusCode) || 500,
    message: normalized && normalized.message ? String(normalized.message) : '',
    data: normalized && normalized.data !== undefined ? normalized.data : null,
    args: Array.isArray(normalized && normalized.args) ? normalized.args : [],
  };
}

class DockerTaskWorker {
  constructor() {
    this.service = new DockerService({ taskTransport: 'local' });
    this.exitTimer = null;
    this.idleExitDelayMs = Math.max(60 * 1000, Number(process.env.DOCKER_TASK_WORKER_IDLE_EXIT_MS) || 10 * 60 * 1000);
    this.ready = this.init();
    this.bindMessages();
    this.refreshExitPolicy();
  }

  async init() {
    await knexUtil.init(dbUtil.DB_PATHS.MAIN_DB);
  }

  reply(payload) {
    if (typeof process.send !== 'function') return;
    try {
      process.send({
        type: 'dockerTaskResponse',
        data: payload,
      });
    } catch (_) {}
  }

  async cleanupBeforeExit() {
    this.clearExitTimer();
    try {
      await knexUtil.destroy(dbUtil.DB_PATHS.MAIN_DB);
    } catch (error) {
      Logger.warn('dockerTaskWorker destroy db failed', { error });
    }
  }

  clearExitTimer() {
    if (!this.exitTimer) return;
    clearTimeout(this.exitTimer);
    this.exitTimer = null;
  }

  hasTasks() {
    return dockerTaskManager.listTasks({}).length > 0;
  }

  refreshExitPolicy() {
    if (this.hasTasks()) {
      this.clearExitTimer();
      return;
    }
    if (this.exitTimer) return;
    this.exitTimer = setTimeout(async () => {
      this.exitTimer = null;
      if (this.hasTasks()) return;
      await this.cleanupBeforeExit();
      process.exit(0);
    }, this.idleExitDelayMs);
    if (this.exitTimer && typeof this.exitTimer.unref === 'function') {
      this.exitTimer.unref();
    }
  }

  async handleRequest(message) {
    const data = message && message.data && typeof message.data === 'object' ? message.data : {};
    const requestId = data.requestId ? String(data.requestId) : '';
    const action = data.action ? String(data.action) : '';
    const payload = data.payload && typeof data.payload === 'object' ? data.payload : {};
    if (!requestId || !action) return;

    try {
      await this.ready;
      const result = await this.dispatchAction(action, payload);
      this.reply({
        requestId,
        ok: true,
        data: result,
      });
    } catch (error) {
      Logger.error('dockerTaskWorker request failed', { action, error });
      this.reply({
        requestId,
        ok: false,
        error: normalizeError(error),
      });
    } finally {
      this.refreshExitPolicy();
    }
  }

  async dispatchAction(action, payload) {
    switch (action) {
      case 'startDocker':
        return await this.service.startDocker(payload);
      case 'stopDocker':
        return await this.service.stopDocker(payload);
      case 'pullImage':
        return await this.service.pullImage(payload);
      case 'importImage':
        return await this.service.importImage(payload);
      case 'getContainerLogs':
        return await this.service.getContainerLogs(payload);
      case 'listTasks':
        return await this.service.listTasks(payload);
      case 'getTask':
        return await this.service.getTask(payload.taskId || payload.id);
      case 'getTaskLogs':
        return await this.service.getTaskLogs(payload);
      case 'cancelTask':
        return await this.service.cancelTask(payload);
      case 'deleteTask':
        return await this.service.deleteTask(payload);
      default:
        throw new DockerApiError('common.ERROR', 400, `Unsupported docker task action: ${action}`);
    }
  }

  bindMessages() {
    process.on('message', async message => {
      const type = message && message.type ? String(message.type) : '';
      if (!type) return;
      if (type === 'stop') {
        await this.cleanupBeforeExit();
        process.exit(0);
      }
      if (type === 'dockerTaskRequest') {
        await this.handleRequest(message);
      }
    });
  }
}

new DockerTaskWorker();
