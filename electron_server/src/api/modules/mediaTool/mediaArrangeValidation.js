const { body, validationResult } = require('express-validator');
const { getLocalizedMessage } = require('../../../utils/i18nUtil');
const tableMediaToolArrange = require('../../../db/table/tableMediaToolArrange');

function isAbsolutePath(value) {
  if (typeof value !== 'string') return false;
  const v = value.trim();
  if (!v) return false;
  if (v.startsWith('/') || v.startsWith('\\\\')) return true;
  return /^[a-zA-Z]:\\/.test(v);
}

const MediaArrangeValidation = {
  validateList() {
    return [body('page').optional().isInt({ min: 1 }).withMessage('validation.VALIDATION_ERROR'), body('pageSize').optional().isInt({ min: 1, max: 200 }).withMessage('validation.VALIDATION_ERROR')];
  },

  validateUpsert() {
    return [
      body('id').optional().isInt({ min: 1 }).withMessage('validation.ID_INVALID'),
      body('source_path').notEmpty().custom(isAbsolutePath).withMessage('validation.VALIDATION_ERROR'),
      body('target_path').notEmpty().custom(isAbsolutePath).withMessage('validation.VALIDATION_ERROR'),
      body('arrange_type')
        .notEmpty()
        .isIn([tableMediaToolArrange.ARRANGE_TYPE_YEAR, tableMediaToolArrange.ARRANGE_TYPE_MONTH, tableMediaToolArrange.ARRANGE_TYPE_DAY])
        .withMessage('validation.VALIDATION_ERROR'),
      body('same_name_policy')
        .optional()
        .isIn([tableMediaToolArrange.SAME_NAME_POLICY_SKIP, tableMediaToolArrange.SAME_NAME_POLICY_RENAME, tableMediaToolArrange.SAME_NAME_POLICY_OVERWRITE])
        .withMessage('validation.VALIDATION_ERROR'),
    ];
  },

  validateDelete() {
    return [body('id').notEmpty().isInt({ min: 1 }).withMessage('validation.ID_INVALID')];
  },

  validateStartStop() {
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

module.exports = MediaArrangeValidation;
