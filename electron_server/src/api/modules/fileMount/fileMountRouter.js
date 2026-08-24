const express = require('express');
const router = express.Router();
const { authenticateJWT, requireAdmin } = require('../../middleware/authMiddleware');
const FileMountValidation = require('./fileMountValidation');
const fileMountController = require('./fileMountController');

router.post('/list', authenticateJWT, requireAdmin, FileMountValidation.validateList(), FileMountValidation.handleValidationErrors, (req, res) => fileMountController.list(req, res));
router.post('/upsert', authenticateJWT, requireAdmin, FileMountValidation.validateUpsert(), FileMountValidation.handleValidationErrors, (req, res) => fileMountController.upsert(req, res));
router.post('/delete', authenticateJWT, requireAdmin, FileMountValidation.validateDelete(), FileMountValidation.handleValidationErrors, (req, res) => fileMountController.remove(req, res));
router.post('/start', authenticateJWT, requireAdmin, FileMountValidation.validateStartStop(), FileMountValidation.handleValidationErrors, (req, res) => fileMountController.start(req, res));
router.post('/stop', authenticateJWT, requireAdmin, FileMountValidation.validateStartStop(), FileMountValidation.handleValidationErrors, (req, res) => fileMountController.stop(req, res));
router.post('/checkWinfsp', authenticateJWT, requireAdmin, FileMountValidation.validateCheckWinfsp(), FileMountValidation.handleValidationErrors, (req, res) => fileMountController.checkWinfsp(req, res));

module.exports = router;
