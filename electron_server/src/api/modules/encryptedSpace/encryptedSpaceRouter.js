const express = require('express');
const router = express.Router();
const { authenticateJWT } = require('../../middleware/authMiddleware');
const { requirePermission } = require('../../middleware/permissionMiddleware');
const EncryptedSpaceValidation = require('./encryptedSpaceValidation');
const encryptedSpaceController = require('./encryptedSpaceController');

router.post('/list', authenticateJWT, (req, res) => encryptedSpaceController.list(req, res));

// 普通用户只能增加到自己有上传权限的目录下
router.post(
  '/addSpace',
  authenticateJWT,
  EncryptedSpaceValidation.validateAddSpace(),
  EncryptedSpaceValidation.handleValidationErrors,
  requirePermission('upload', { from: 'body.folderPath' }),
  (req, res) => encryptedSpaceController.addSpace(req, res)
);

router.post('/checkPwd', authenticateJWT, EncryptedSpaceValidation.validateCheckPwd(), EncryptedSpaceValidation.handleValidationErrors, (req, res) => encryptedSpaceController.checkPwd(req, res));

router.post('/checkToken', authenticateJWT, EncryptedSpaceValidation.validateCheckToken(), EncryptedSpaceValidation.handleValidationErrors, (req, res) =>
  encryptedSpaceController.checkToken(req, res)
);

router.post('/deleteToken', authenticateJWT, EncryptedSpaceValidation.validateDeleteToken(), EncryptedSpaceValidation.handleValidationErrors, (req, res) =>
  encryptedSpaceController.deleteToken(req, res)
);

router.post('/getFileList', authenticateJWT, EncryptedSpaceValidation.validateGetFileList(), EncryptedSpaceValidation.handleValidationErrors, (req, res) =>
  encryptedSpaceController.getFileList(req, res)
);

router.post('/upload/check', authenticateJWT, (req, res) => encryptedSpaceController.checkChunk(req, res));
router.post('/upload/chunk', authenticateJWT, (req, res) => encryptedSpaceController.uploadChunk(req, res));

router.get('/getDecodeFile*', authenticateJWT, EncryptedSpaceValidation.validateGetDecodeFile(), EncryptedSpaceValidation.handleValidationErrors, (req, res) =>
  encryptedSpaceController.getDecodeFile(req, res)
);

router.post('/deleteSpaceFiles', authenticateJWT, EncryptedSpaceValidation.validateDeleteSpaceFiles(), EncryptedSpaceValidation.handleValidationErrors, (req, res) =>
  encryptedSpaceController.deleteSpaceFiles(req, res)
);

router.post('/deleteSpace', authenticateJWT, EncryptedSpaceValidation.validateDeleteSpace(), EncryptedSpaceValidation.handleValidationErrors, (req, res) =>
  encryptedSpaceController.deleteSpace(req, res)
);

router.post('/updateSpaceName', authenticateJWT, EncryptedSpaceValidation.validateUpdateSpaceName(), EncryptedSpaceValidation.handleValidationErrors, (req, res) =>
  encryptedSpaceController.updateSpaceName(req, res)
);

// 导入空间：需验证用户对要导入的目录有读取权限
router.post(
  '/importSpace',
  authenticateJWT,
  EncryptedSpaceValidation.validateImportSpace(),
  EncryptedSpaceValidation.handleValidationErrors,
  requirePermission(['view'], { from: 'body.folderPath' }),
  (req, res) => encryptedSpaceController.importSpace(req, res)
);

router.post('/exitSpaceId', authenticateJWT, EncryptedSpaceValidation.validateExitSpaceId(), EncryptedSpaceValidation.handleValidationErrors, (req, res) =>
  encryptedSpaceController.exitSpaceId(req, res)
);

router.post('/export/list', authenticateJWT, EncryptedSpaceValidation.validateExportTaskList(), EncryptedSpaceValidation.handleValidationErrors, (req, res) =>
  encryptedSpaceController.exportTaskList(req, res)
);

// 导出目标目录必须有写入权限（upload）才能导出
router.post(
  '/export/add',
  authenticateJWT,
  EncryptedSpaceValidation.validateAddExportTask(),
  EncryptedSpaceValidation.handleValidationErrors,
  requirePermission('upload', { from: 'body.targetPath' }),
  (req, res) => encryptedSpaceController.addExportTask(req, res)
);

router.post('/export/delete', authenticateJWT, EncryptedSpaceValidation.validateDeleteExportTask(), EncryptedSpaceValidation.handleValidationErrors, (req, res) =>
  encryptedSpaceController.deleteExportTask(req, res)
);

router.post('/export/clearFinished', authenticateJWT, EncryptedSpaceValidation.validateClearFinishedExportTasks(), EncryptedSpaceValidation.handleValidationErrors, (req, res) =>
  encryptedSpaceController.clearFinishedExportTasks(req, res)
);

module.exports = router;
