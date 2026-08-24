const express = require('express');
const router = express.Router();
const { authenticateJWT, requireAdmin } = require('../../middleware/authMiddleware');
const FileServerValidation = require('./fileServerValidation');
const fileServerController = require('./fileServerController');

router.post('/list', authenticateJWT, requireAdmin, FileServerValidation.validateList(), FileServerValidation.handleValidationErrors, fileServerController.list);
router.post('/get', authenticateJWT, requireAdmin, FileServerValidation.validateGet(), FileServerValidation.handleValidationErrors, fileServerController.get);
router.post('/upsert', authenticateJWT, requireAdmin, FileServerValidation.validateUpsert(), FileServerValidation.handleValidationErrors, (req, res) => fileServerController.upsert(req, res));
router.post('/delete', authenticateJWT, requireAdmin, FileServerValidation.validateGet(), FileServerValidation.handleValidationErrors, (req, res) => fileServerController.remove(req, res));
router.post('/start', authenticateJWT, requireAdmin, FileServerValidation.validateStartStop(), FileServerValidation.handleValidationErrors, (req, res) => fileServerController.start(req, res));
router.post('/restart', authenticateJWT, requireAdmin, FileServerValidation.validateStartStop(), FileServerValidation.handleValidationErrors, (req, res) => fileServerController.restart(req, res));
router.post('/stop', authenticateJWT, requireAdmin, FileServerValidation.validateStartStop(), FileServerValidation.handleValidationErrors, (req, res) => fileServerController.stop(req, res));
router.post('/ports/get', authenticateJWT, requireAdmin, FileServerValidation.validateGetPorts(), FileServerValidation.handleValidationErrors, fileServerController.getPorts);
router.post('/ports/set', authenticateJWT, requireAdmin, FileServerValidation.validateSetPorts(), FileServerValidation.handleValidationErrors, (req, res) => fileServerController.setPorts(req, res));

module.exports = router;
