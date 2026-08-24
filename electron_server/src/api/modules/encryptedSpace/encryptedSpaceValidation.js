const { body, query, validationResult } = require('express-validator');
const { getLocalizedMessage } = require('../../../utils/i18nUtil');

function isAbsolutePath(value) {
  if (typeof value !== 'string') return false;
  const v = value.trim();
  if (!v) return false;
  if (v.startsWith('/') || v.startsWith('\\\\')) return true;
  return /^[a-zA-Z]:\\/.test(v);
}

const EncryptedSpaceValidation = {
  validateAddSpace() {
    return [
      body('folderPath').notEmpty().isString().custom(isAbsolutePath).withMessage('validation.VALIDATION_ERROR'),
      body('spaceName').notEmpty().isString().isLength({ min: 1, max: 50 }).withMessage('validation.VALIDATION_ERROR'),
      body('spacePwd').notEmpty().isString().isLength({ min: 1, max: 200 }).withMessage('validation.VALIDATION_ERROR'),
    ];
  },

  validateCheckPwd() {
    return [
      body('spaceId').notEmpty().isInt({ min: 1 }).withMessage('validation.ID_INVALID'),
      body('spacePwd').notEmpty().isString().isLength({ min: 1, max: 200 }).withMessage('validation.VALIDATION_ERROR'),
    ];
  },

  validateCheckToken() {
    return [body('token').notEmpty().isString().isLength({ min: 1, max: 200 }).withMessage('validation.VALIDATION_ERROR')];
  },

  validateDeleteToken() {
    return [body('spaceId').notEmpty().isInt({ min: 1 }).withMessage('validation.ID_INVALID')];
  },

  validateGetFileList() {
    return [
      body('spaceId').notEmpty().isInt({ min: 1 }).withMessage('validation.ID_INVALID'),
      body('token').optional().isString().isLength({ min: 1, max: 200 }).withMessage('validation.VALIDATION_ERROR'),
      body('spaceToken').optional().isString().isLength({ min: 1, max: 200 }).withMessage('validation.VALIDATION_ERROR'),
    ];
  },

  validateGetDecodeFile() {
    return [
      query('spaceId').notEmpty().isInt({ min: 1 }).withMessage('validation.ID_INVALID'),
      query('indexId').notEmpty().isInt({ min: 1 }).withMessage('validation.ID_INVALID'),
      query('token').optional().isString().isLength({ min: 1, max: 200 }).withMessage('validation.VALIDATION_ERROR'),
      query('spaceToken').optional().isString().isLength({ min: 1, max: 200 }).withMessage('validation.VALIDATION_ERROR'),
    ];
  },

  validateDeleteSpaceFiles() {
    return [body('spaceId').notEmpty().isInt({ min: 1 }).withMessage('validation.ID_INVALID'), body('ids').notEmpty().withMessage('validation.VALIDATION_ERROR')];
  },

  validateDeleteSpace() {
    return [body('spaceId').notEmpty().isInt({ min: 1 }).withMessage('validation.ID_INVALID')];
  },

  validateUpdateSpaceName() {
    return [
      body('spaceId').notEmpty().isInt({ min: 1 }).withMessage('validation.ID_INVALID'),
      body('spaceName').notEmpty().isString().isLength({ min: 1, max: 50 }).withMessage('validation.VALIDATION_ERROR'),
    ];
  },

  validateImportSpace() {
    return [
      body('folderPath').notEmpty().isString().custom(isAbsolutePath).withMessage('validation.VALIDATION_ERROR'),
      body('spaceName').notEmpty().isString().isLength({ min: 1, max: 50 }).withMessage('validation.VALIDATION_ERROR'),
      body('spacePwd').notEmpty().isString().isLength({ min: 1, max: 200 }).withMessage('validation.VALIDATION_ERROR'),
    ];
  },

  validateExitSpaceId() {
    return [body('spaceId').notEmpty().isInt({ min: 1 }).withMessage('validation.ID_INVALID')];
  },

  validateExportTaskList() {
    return [];
  },

  validateAddExportTask() {
    return [
      body('spaceId').notEmpty().isInt({ min: 1 }).withMessage('validation.ID_INVALID'),
      body('spacePwd').notEmpty().isString().isLength({ min: 1, max: 200 }).withMessage('validation.VALIDATION_ERROR'),
      body('targetPath').notEmpty().isString().custom(isAbsolutePath).withMessage('validation.VALIDATION_ERROR'),
    ];
  },

  validateDeleteExportTask() {
    return [body('id').notEmpty().isInt({ min: 1 }).withMessage('validation.ID_INVALID')];
  },

  validateClearFinishedExportTasks() {
    return [];
  },

  handleValidationErrors(req, res, next) {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      const errorMessages = errors
        .array()
        .map(error => getLocalizedMessage(req, error.msg))
        .join(', ');

      return res.status(400).json({
        success: false,
        message: errorMessages,
      });
    }
    next();
  },
};

module.exports = EncryptedSpaceValidation;
