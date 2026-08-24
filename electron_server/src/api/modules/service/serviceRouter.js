const express = require('express');
const { authenticateJWT, requireAdmin } = require('../../middleware/authMiddleware');
const serviceController = require('./serviceController');
const ddnsController = require('./ddns/ddnsController');

const router = express.Router();

router.post('/nascab/login', authenticateJWT, requireAdmin, (req, res) => serviceController.loginNasCabAccount(req, res));
router.get('/nascab/login', authenticateJWT, requireAdmin, (req, res) => serviceController.loginNasCabAccount(req, res));

router.get('/nascab/query', authenticateJWT, requireAdmin, (req, res) => serviceController.getNasCabAccount(req, res));

router.post('/nascab/logout', authenticateJWT, requireAdmin, (req, res) => serviceController.logoutNasCabAccount(req, res));

router.post('/nascab/refresh', authenticateJWT, requireAdmin, (req, res) => serviceController.refreshNasCabAccountInfo(req, res));

router.get('/nascab/p2p/pairCode', authenticateJWT, requireAdmin, (req, res) => serviceController.getP2pPairCode(req, res));
router.post('/nascab/p2p/pairCode/reset', authenticateJWT, requireAdmin, (req, res) => serviceController.resetP2pPairCode(req, res));
router.post('/nascab/p2p/pairCode/custom', authenticateJWT, requireAdmin, (req, res) => serviceController.customP2pPairCode(req, res));
router.post('/nascab/p2p/bindDevice', authenticateJWT, requireAdmin, (req, res) => serviceController.bindP2pDevice(req, res));
router.get('/nascab/p2p/remoteAccess', authenticateJWT, requireAdmin, (req, res) => serviceController.getP2pRemoteAccess(req, res));
router.post('/nascab/p2p/remoteAccess', authenticateJWT, requireAdmin, (req, res) => serviceController.setP2pRemoteAccess(req, res));
router.post('/nascab/p2p/nodePreference', authenticateJWT, requireAdmin, (req, res) => serviceController.setP2pNodePreference(req, res));

router.get('/nascab/tempCode', authenticateJWT, requireAdmin, (req, res) => serviceController.getNasCabTempCode(req, res));
router.get('/process', authenticateJWT, requireAdmin, (req, res) => serviceController.getProcessList(req, res));

router.get('/ddns/status', authenticateJWT, requireAdmin, (req, res) => ddnsController.getStatus(req, res));
router.post('/ddns/domain', authenticateJWT, requireAdmin, (req, res) => ddnsController.setDomain(req, res));
router.post('/ddns/type', authenticateJWT, requireAdmin, (req, res) => ddnsController.setType(req, res));
router.post('/ddns/enabled', authenticateJWT, requireAdmin, (req, res) => ddnsController.setEnabled(req, res));

module.exports = router;
