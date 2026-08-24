const express = require('express');
const { authenticateJWT, requireAdmin } = require('../../middleware/authMiddleware');
const dockerController = require('./dockerController');

const router = express.Router();

router.get('/status', authenticateJWT, requireAdmin, dockerController.getStatus);
router.get('/config', authenticateJWT, requireAdmin, dockerController.getConfig);
router.post('/config/save', authenticateJWT, requireAdmin, dockerController.saveConfig);
router.post('/config/proxy', authenticateJWT, requireAdmin, dockerController.setProxyConfig);
router.post('/start', authenticateJWT, requireAdmin, dockerController.startDocker);
router.post('/stop', authenticateJWT, requireAdmin, dockerController.stopDocker);

router.get('/images/list', authenticateJWT, requireAdmin, dockerController.listImages);
router.post('/images/pull', authenticateJWT, requireAdmin, dockerController.pullImage);
router.post('/images/import', authenticateJWT, requireAdmin, dockerController.importImage);
router.post('/images/delete', authenticateJWT, requireAdmin, dockerController.deleteImage);
router.post('/images/tag', authenticateJWT, requireAdmin, dockerController.tagImage);

router.get('/containers/list', authenticateJWT, requireAdmin, dockerController.listContainers);
router.post('/containers/create', authenticateJWT, requireAdmin, dockerController.createContainer);
router.post('/containers/start', authenticateJWT, requireAdmin, dockerController.startContainer);
router.post('/containers/stop', authenticateJWT, requireAdmin, dockerController.stopContainer);
router.post('/containers/delete', authenticateJWT, requireAdmin, dockerController.deleteContainer);
router.get('/containers/logs', authenticateJWT, requireAdmin, dockerController.getContainerLogs);
router.post('/containers/logs', authenticateJWT, requireAdmin, dockerController.getContainerLogs);

router.get('/tasks/list', authenticateJWT, requireAdmin, dockerController.listTasks);
router.get('/tasks/detail', authenticateJWT, requireAdmin, dockerController.getTask);
router.get('/tasks/logs', authenticateJWT, requireAdmin, dockerController.getTaskLogs);
router.post('/tasks/logs', authenticateJWT, requireAdmin, dockerController.getTaskLogs);
router.post('/tasks/cancel', authenticateJWT, requireAdmin, dockerController.cancelTask);
router.post('/tasks/delete', authenticateJWT, requireAdmin, dockerController.deleteTask);

module.exports = router;
