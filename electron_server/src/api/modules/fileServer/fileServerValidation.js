const { body, validationResult } = require('express-validator');
const { getLocalizedMessage } = require('../../../utils/i18nUtil');

function isAbsolutePath(value) {
  if (typeof value !== 'string') return false;
  const v = value.trim();
  if (!v) return false;
  if (v.startsWith('/') || v.startsWith('\\\\')) return true;
  return /^[a-zA-Z]:\\/.test(v);
}

function isOptionalPem(value) {
  if (value === undefined || value === null || value === '') return true;
  if (typeof value !== 'string') return false;
  return value.includes('-----BEGIN');
}

function isRootPathMappings(value) {
  if (typeof value === 'string') return isAbsolutePath(value);
  if (!Array.isArray(value) || value.length === 0) return false;
  const seen = new Set();
  for (const item of value) {
    if (typeof item === 'string') {
      const p = item.trim();
      if (!isAbsolutePath(p)) return false;
      if (seen.has(p)) return false;
      seen.add(p);
      continue;
    }

    if (item && typeof item === 'object') {
      const p = typeof item.path === 'string' ? item.path.trim() : '';
      if (!isAbsolutePath(p)) return false;
      if (seen.has(p)) return false;
      seen.add(p);

      const isOptionalBool01 = v => {
        if (v === undefined || v === null) return true;
        if (typeof v === 'boolean') return true;
        if (typeof v === 'number') return v === 0 || v === 1;
        if (typeof v === 'string') return v === '0' || v === '1';
        return false;
      };

      if (!isOptionalBool01(item.write)) return false;
      if (!isOptionalBool01(item.update)) return false;
      if (!isOptionalBool01(item.delete)) return false;
      continue;
    }

    return false;
  }
  return true;
}

const FileServerValidation = {
  validateUpsert() {
    return [
      body('uid').notEmpty().isString().matches(/^\d+$/).withMessage('validation.ID_INVALID'),
      body('server_type').notEmpty().isIn(['WebDav', 'FTP', 'SFTP']).withMessage('validation.VALIDATION_ERROR'),
      body('root_path').notEmpty().custom(isRootPathMappings).withMessage('validation.VALIDATION_ERROR'),
      body('http_port').optional().isInt({ min: 1, max: 65535 }).withMessage('validation.VALIDATION_ERROR'),
      body('https_port').optional().isInt({ min: 1, max: 65535 }).withMessage('validation.VALIDATION_ERROR'),
      body('config').optional().isObject().withMessage('validation.VALIDATION_ERROR'),
      body('config.users').optional().isArray().withMessage('validation.VALIDATION_ERROR'),
      body('config.users.*.username').optional().isString().notEmpty().withMessage('validation.VALIDATION_ERROR'),
      body('config.users.*.password').optional().isString().notEmpty().withMessage('validation.VALIDATION_ERROR'),
      body('config.users.*.home_dir').optional().isString().withMessage('validation.VALIDATION_ERROR'),
      body('config.tls_cert_pem').optional().custom(isOptionalPem).withMessage('validation.VALIDATION_ERROR'),
      body('config.tls_key_pem').optional().custom(isOptionalPem).withMessage('validation.VALIDATION_ERROR'),
    ];
  },

  validateGet() {
    return [
      body('uid').notEmpty().isString().matches(/^\d+$/).withMessage('validation.ID_INVALID'),
      body('server_type').notEmpty().isIn(['WebDav', 'FTP', 'SFTP']).withMessage('validation.VALIDATION_ERROR'),
    ];
  },

  validateStartStop() {
    return [
      body('server_type').notEmpty().isIn(['WebDav', 'FTP', 'SFTP']).withMessage('validation.VALIDATION_ERROR'),
      body('restart').optional().isBoolean().withMessage('validation.VALIDATION_ERROR'),
    ];
  },

  validateGetPorts() {
    return [body('server_type').notEmpty().isIn(['WebDav', 'FTP', 'SFTP']).withMessage('validation.VALIDATION_ERROR')];
  },

  validateSetPorts() {
    return [
      body('server_type').notEmpty().isIn(['WebDav', 'FTP', 'SFTP']).withMessage('validation.VALIDATION_ERROR'),
      body('http_port').optional().isInt({ min: 1, max: 65535 }).withMessage('validation.VALIDATION_ERROR'),
      body('https_port').optional().isInt({ min: 1, max: 65535 }).withMessage('validation.VALIDATION_ERROR'),
    ];
  },

  validateList() {
    return [
      body('uid').optional().isString().matches(/^\d+$/).withMessage('validation.ID_INVALID'),
      body('server_type').optional().isIn(['WebDav', 'FTP', 'SFTP']).withMessage('validation.VALIDATION_ERROR'),
      body('status').optional().isIn(['running', 'stopped', 'error']).withMessage('validation.VALIDATION_ERROR'),
    ];
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

module.exports = FileServerValidation;
