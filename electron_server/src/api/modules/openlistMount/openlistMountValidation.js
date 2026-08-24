const { body, validationResult } = require('express-validator');
const { getLocalizedMessage } = require('../../../utils/i18nUtil');

function isAbsolutePath(value) {
  if (typeof value !== 'string') return false;
  const v = value.trim();
  if (!v) return false;
  if (v.startsWith('/') || v.startsWith('\\\\')) return true;
  return /^[a-zA-Z]:\\/.test(v);
}

const OpenlistMountValidation = {
  validateList() {
    return [
      body('uid').optional().isString().matches(/^\d+$/).withMessage('validation.ID_INVALID'),
      body('status').optional().isIn(['running', 'stopped', 'error']).withMessage('validation.VALIDATION_ERROR'),
    ];
  },

  validateUpsert() {
    return [
      body('id').optional().isInt({ min: 1 }).withMessage('validation.ID_INVALID'),
      body('name').notEmpty().isString().withMessage('validation.VALIDATION_ERROR'),
      body('mount_path').notEmpty().custom(isAbsolutePath).withMessage('validation.VALIDATION_ERROR'),
      body('driver').notEmpty().isString().withMessage('validation.VALIDATION_ERROR'),
      body('config').optional().isObject().withMessage('validation.VALIDATION_ERROR'),
    ];
  },

  validateIdOnly() {
    return [body('id').notEmpty().isInt({ min: 1 }).withMessage('validation.ID_INVALID')];
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

module.exports = OpenlistMountValidation;
