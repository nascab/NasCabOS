const express = require('express');
const { authenticateJWT, requireAdmin } = require('../../middleware/authMiddleware');
const imageCompressController = require('./imageCompressController');
const imgBatchCompressController = require('./imgBatchCompressController');
const ImgBatchCompressValidation = require('./imgBatchCompressValidation');
const videoTransController = require('./videoTransController');
const VideoTransValidation = require('./videoTransValidation');
const audioTransController = require('./audioTransController');
const AudioTransValidation = require('./audioTransValidation');
const mediaArrangeController = require('./mediaArrangeController');
const MediaArrangeValidation = require('./mediaArrangeValidation');

const router = express.Router();

router.post('/imageCompress/upload', authenticateJWT, imageCompressController.uploadStage, imageCompressController.uploadAndCompress);
router.get('/imageCompress/file', authenticateJWT, imageCompressController.downloadFile);
router.get('/imageCompress/zip', authenticateJWT, imageCompressController.downloadZip);

router.post('/imgBatchCompress/list', authenticateJWT, requireAdmin, ImgBatchCompressValidation.validateList(), ImgBatchCompressValidation.handleValidationErrors, (req, res) =>
  imgBatchCompressController.list(req, res)
);
router.post('/imgBatchCompress/upsert', authenticateJWT, requireAdmin, ImgBatchCompressValidation.validateUpsert(), ImgBatchCompressValidation.handleValidationErrors, (req, res) =>
  imgBatchCompressController.upsert(req, res)
);
router.post('/imgBatchCompress/delete', authenticateJWT, requireAdmin, ImgBatchCompressValidation.validateDelete(), ImgBatchCompressValidation.handleValidationErrors, (req, res) =>
  imgBatchCompressController.remove(req, res)
);
router.post('/imgBatchCompress/start', authenticateJWT, requireAdmin, ImgBatchCompressValidation.validateStartStop(), ImgBatchCompressValidation.handleValidationErrors, (req, res) =>
  imgBatchCompressController.start(req, res)
);
router.post('/imgBatchCompress/stop', authenticateJWT, requireAdmin, ImgBatchCompressValidation.validateStartStop(), ImgBatchCompressValidation.handleValidationErrors, (req, res) =>
  imgBatchCompressController.stop(req, res)
);

router.post('/videoTrans/list', authenticateJWT, requireAdmin, VideoTransValidation.validateList(), VideoTransValidation.handleValidationErrors, (req, res) => videoTransController.list(req, res));
router.post('/videoTrans/upsert', authenticateJWT, requireAdmin, VideoTransValidation.validateUpsert(), VideoTransValidation.handleValidationErrors, (req, res) => videoTransController.upsert(req, res));
router.post('/videoTrans/delete', authenticateJWT, requireAdmin, VideoTransValidation.validateDelete(), VideoTransValidation.handleValidationErrors, (req, res) => videoTransController.remove(req, res));
router.post('/videoTrans/start', authenticateJWT, requireAdmin, VideoTransValidation.validateStartStop(), VideoTransValidation.handleValidationErrors, (req, res) => videoTransController.start(req, res));
router.post('/videoTrans/stop', authenticateJWT, requireAdmin, VideoTransValidation.validateStartStop(), VideoTransValidation.handleValidationErrors, (req, res) => videoTransController.stop(req, res));

router.post('/audioTrans/list', authenticateJWT, requireAdmin, AudioTransValidation.validateList(), AudioTransValidation.handleValidationErrors, (req, res) => audioTransController.list(req, res));
router.post('/audioTrans/upsert', authenticateJWT, requireAdmin, AudioTransValidation.validateUpsert(), AudioTransValidation.handleValidationErrors, (req, res) => audioTransController.upsert(req, res));
router.post('/audioTrans/delete', authenticateJWT, requireAdmin, AudioTransValidation.validateDelete(), AudioTransValidation.handleValidationErrors, (req, res) => audioTransController.remove(req, res));
router.post('/audioTrans/start', authenticateJWT, requireAdmin, AudioTransValidation.validateStartStop(), AudioTransValidation.handleValidationErrors, (req, res) => audioTransController.start(req, res));
router.post('/audioTrans/stop', authenticateJWT, requireAdmin, AudioTransValidation.validateStartStop(), AudioTransValidation.handleValidationErrors, (req, res) => audioTransController.stop(req, res));

router.post('/mediaArrange/list', authenticateJWT, requireAdmin, MediaArrangeValidation.validateList(), MediaArrangeValidation.handleValidationErrors, (req, res) => mediaArrangeController.list(req, res));
router.post('/mediaArrange/upsert', authenticateJWT, requireAdmin, MediaArrangeValidation.validateUpsert(), MediaArrangeValidation.handleValidationErrors, (req, res) => mediaArrangeController.upsert(req, res));
router.post('/mediaArrange/delete', authenticateJWT, requireAdmin, MediaArrangeValidation.validateDelete(), MediaArrangeValidation.handleValidationErrors, (req, res) => mediaArrangeController.remove(req, res));
router.post('/mediaArrange/start', authenticateJWT, requireAdmin, MediaArrangeValidation.validateStartStop(), MediaArrangeValidation.handleValidationErrors, (req, res) => mediaArrangeController.start(req, res));
router.post('/mediaArrange/stop', authenticateJWT, requireAdmin, MediaArrangeValidation.validateStartStop(), MediaArrangeValidation.handleValidationErrors, (req, res) => mediaArrangeController.stop(req, res));

module.exports = router;
