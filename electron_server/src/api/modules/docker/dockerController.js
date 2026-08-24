const dockerResponseUtil = require('./dockerResponseUtil');
const { DockerService, DockerApiError, mapDockerFailure } = require('./dockerService');
const { runWithRequest, killRequestChildren } = require('./dockerSpawnUtil');

class DockerController {
  constructor() {
    this.service = new DockerService();
  }

  handle = async (req, res, action, successMessage = 'common.SUCCESS', statusCode = 200) => {
    const onClose = () => killRequestChildren(req);
    req.once('close', onClose);
    try {
      const data = await runWithRequest(req, action);
      return dockerResponseUtil.success(req, res, data, successMessage, statusCode);
    } catch (error) {
      const normalized = error instanceof DockerApiError ? error : mapDockerFailure(error);
      return dockerResponseUtil.error(req, res, normalized);
    } finally {
      req.removeListener('close', onClose);
    }
  };

  getStatus = async (req, res) =>
    this.handle(req, res, () => this.service.getStatus(), 'common.SUCCESS');

  getConfig = async (req, res) =>
    this.handle(req, res, () => this.service.getConfig(), 'common.SUCCESS');

  setProxyConfig = async (req, res) =>
    this.handle(req, res, () => this.service.setProxyConfig(req.body || {}), 'docker.CONFIG_SAVED');

  saveConfig = async (req, res) =>
    this.handle(req, res, () => this.service.saveDaemonConfig(req.body || {}), 'docker.CONFIG_SAVED');

  startDocker = async (req, res) =>
    this.handle(req, res, () => this.service.startDocker(req.body || {}), 'docker.TASK_CREATED', 202);

  stopDocker = async (req, res) =>
    this.handle(req, res, () => this.service.stopDocker(req.body || {}), 'docker.TASK_CREATED', 202);

  listImages = async (req, res) =>
    this.handle(req, res, () => this.service.listImages(), 'common.SUCCESS');

  pullImage = async (req, res) =>
    this.handle(req, res, () => this.service.pullImage(req.body || {}), 'docker.TASK_CREATED', 202);

  importImage = async (req, res) =>
    this.handle(req, res, () => this.service.importImage(req.body || {}), 'docker.TASK_CREATED', 202);

  deleteImage = async (req, res) =>
    this.handle(req, res, () => this.service.deleteImage(req.body || {}), 'docker.IMAGE_DELETED');

  tagImage = async (req, res) =>
    this.handle(req, res, () => this.service.tagImage(req.body || {}), 'common.SUCCESS');

  listContainers = async (req, res) =>
    this.handle(req, res, () => this.service.listContainers(req.query || {}), 'common.SUCCESS');

  createContainer = async (req, res) =>
    this.handle(req, res, () => this.service.createContainer(req.body || {}), 'docker.CONTAINER_CREATED', 201);

  startContainer = async (req, res) =>
    this.handle(req, res, () => this.service.startContainer(req.body || {}), 'docker.CONTAINER_STARTED');

  stopContainer = async (req, res) =>
    this.handle(req, res, () => this.service.stopContainer(req.body || {}), 'docker.CONTAINER_STOPPED');

  deleteContainer = async (req, res) =>
    this.handle(req, res, () => this.service.deleteContainer(req.body || {}), 'docker.CONTAINER_DELETED');

  getContainerLogs = async (req, res) =>
    this.handle(req, res, () => this.service.getContainerLogs(req.method === 'GET' ? req.query || {} : req.body || {}), 'common.SUCCESS');

  listTasks = async (req, res) =>
    this.handle(req, res, () => this.service.listTasks(req.query || {}), 'common.SUCCESS');

  getTask = async (req, res) =>
    this.handle(req, res, () => this.service.getTask((req.query && req.query.taskId) || (req.body && req.body.taskId)), 'common.SUCCESS');

  getTaskLogs = async (req, res) =>
    this.handle(
      req,
      res,
      () => this.service.getTaskLogs(req.method === 'GET' ? req.query || {} : req.body || {}),
      'common.SUCCESS'
    );

  cancelTask = async (req, res) =>
    this.handle(req, res, () => this.service.cancelTask(req.body || {}), 'docker.TASK_CANCELLED');

  deleteTask = async (req, res) =>
    this.handle(req, res, () => this.service.deleteTask(req.body || {}), 'common.DELETE_SUCCESS');
}

module.exports = new DockerController();
