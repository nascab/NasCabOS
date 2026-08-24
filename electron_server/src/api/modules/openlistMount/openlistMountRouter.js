const express = require('express');
const router = express.Router();
const { authenticateJWT, requireAdmin } = require('../../middleware/authMiddleware');
const OpenlistMountValidation = require('./openlistMountValidation');
const openlistMountController = require('./openlistMountController');

router.post('/list', authenticateJWT, requireAdmin, OpenlistMountValidation.validateList(), OpenlistMountValidation.handleValidationErrors, (req, res) =>
  openlistMountController.list(req, res)
);
router.post('/upsert', authenticateJWT, requireAdmin, OpenlistMountValidation.validateUpsert(), OpenlistMountValidation.handleValidationErrors, (req, res) =>
  openlistMountController.upsert(req, res)
);
router.post('/delete', authenticateJWT, requireAdmin, OpenlistMountValidation.validateIdOnly(), OpenlistMountValidation.handleValidationErrors, (req, res) =>
  openlistMountController.remove(req, res)
);
router.post('/start', authenticateJWT, requireAdmin, OpenlistMountValidation.validateIdOnly(), OpenlistMountValidation.handleValidationErrors, (req, res) =>
  openlistMountController.start(req, res)
);
router.post('/stop', authenticateJWT, requireAdmin, OpenlistMountValidation.validateIdOnly(), OpenlistMountValidation.handleValidationErrors, (req, res) =>
  openlistMountController.stop(req, res)
);
router.get('/drivers', authenticateJWT, requireAdmin, (req, res) => openlistMountController.drivers(req, res));
router.get('/oauthHelpUrl', authenticateJWT, requireAdmin, (req, res) => openlistMountController.oauthHelpUrl(req, res));

module.exports = router;
