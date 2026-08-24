const express = require('express');
const router = express.Router();
const { authenticateJWT, requireAdmin } = require('../../middleware/authMiddleware');
const FileBackupValidation = require('./fileBackupValidation');
const fileBackupController = require('./fileBackupController');

router.post('/list', authenticateJWT, requireAdmin, FileBackupValidation.validateList(), FileBackupValidation.handleValidationErrors, (req, res) => fileBackupController.list(req, res));
router.post('/get', authenticateJWT, requireAdmin, FileBackupValidation.validateGet(), FileBackupValidation.handleValidationErrors, (req, res) => fileBackupController.get(req, res));
router.post('/upsert', authenticateJWT, requireAdmin, FileBackupValidation.validateUpsert(), FileBackupValidation.handleValidationErrors, (req, res) => fileBackupController.upsert(req, res));
router.post('/delete', authenticateJWT, requireAdmin, FileBackupValidation.validateDelete(), FileBackupValidation.handleValidationErrors, (req, res) => fileBackupController.remove(req, res));
router.post('/start', authenticateJWT, requireAdmin, FileBackupValidation.validateStartStop(), FileBackupValidation.handleValidationErrors, (req, res) => fileBackupController.start(req, res));
router.post('/stop', authenticateJWT, requireAdmin, FileBackupValidation.validateStartStop(), FileBackupValidation.handleValidationErrors, (req, res) => fileBackupController.stop(req, res));
router.post(
  '/records/list',
  authenticateJWT,
  requireAdmin,
  FileBackupValidation.validateListRecords(),
  FileBackupValidation.handleValidationErrors,
  (req, res) => fileBackupController.listRecords(req, res)
);

module.exports = router;
