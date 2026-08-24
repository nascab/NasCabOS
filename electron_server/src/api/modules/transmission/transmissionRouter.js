const express = require('express');
const { authenticateJWT, requireAdmin } = require('../../middleware/authMiddleware');
const transmissionController = require('./transmissionController');

const router = express.Router();

router.get('/status', authenticateJWT, requireAdmin, (req, res) => transmissionController.getStatus(req, res));
router.post('/start', authenticateJWT, requireAdmin, (req, res) => transmissionController.start(req, res));
router.post('/stop', authenticateJWT, requireAdmin, (req, res) => transmissionController.stop(req, res));
router.post('/restart', authenticateJWT, requireAdmin, (req, res) => transmissionController.restart(req, res));

router.get('/config', authenticateJWT, requireAdmin, (req, res) => transmissionController.getConfig(req, res));
router.post('/config/save', authenticateJWT, requireAdmin, (req, res) => transmissionController.saveConfig(req, res));
router.post('/config/ports', authenticateJWT, requireAdmin, (req, res) => transmissionController.setPorts(req, res));

router.get('/session', authenticateJWT, requireAdmin, (req, res) => transmissionController.getSession(req, res));
router.post('/session/set', authenticateJWT, requireAdmin, (req, res) => transmissionController.setSession(req, res));

router.get('/torrents/list', authenticateJWT, requireAdmin, (req, res) => transmissionController.listTorrents(req, res));
router.post('/torrents/list', authenticateJWT, requireAdmin, (req, res) => transmissionController.listTorrents(req, res));
router.post('/torrents/add', authenticateJWT, requireAdmin, (req, res) => transmissionController.addTorrent(req, res));
router.post(
  '/torrents/upload',
  authenticateJWT,
  requireAdmin,
  (req, res, next) => transmissionController.uploadTorrentMiddleware(req, res, next),
  (req, res) => transmissionController.uploadTorrent(req, res)
);
router.post('/torrents/start', authenticateJWT, requireAdmin, (req, res) => transmissionController.startTorrents(req, res));
router.post('/torrents/stop', authenticateJWT, requireAdmin, (req, res) => transmissionController.stopTorrents(req, res));
router.post('/torrents/remove', authenticateJWT, requireAdmin, (req, res) => transmissionController.removeTorrents(req, res));
router.post('/torrents/set', authenticateJWT, requireAdmin, (req, res) => transmissionController.setTorrents(req, res));
router.post('/torrents/set-location', authenticateJWT, requireAdmin, (req, res) => transmissionController.setTorrentLocation(req, res));
router.post('/torrents/verify', authenticateJWT, requireAdmin, (req, res) => transmissionController.verifyTorrents(req, res));
router.post('/torrents/reannounce', authenticateJWT, requireAdmin, (req, res) => transmissionController.reannounceTorrents(req, res));

router.get('/torrents/files', authenticateJWT, requireAdmin, (req, res) => transmissionController.getTorrentFiles(req, res));
router.post('/torrents/files', authenticateJWT, requireAdmin, (req, res) => transmissionController.getTorrentFiles(req, res));
router.post('/torrents/files/set', authenticateJWT, requireAdmin, (req, res) => transmissionController.setTorrentFiles(req, res));

router.get('/free-space', authenticateJWT, requireAdmin, (req, res) => transmissionController.freeSpace(req, res));
router.post('/free-space', authenticateJWT, requireAdmin, (req, res) => transmissionController.freeSpace(req, res));

module.exports = router;
