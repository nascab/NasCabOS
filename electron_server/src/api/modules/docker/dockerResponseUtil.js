const { getLocalizedMessage } = require('../../../utils/i18nUtil');

function success(req, res, data = {}, messageKey = 'common.SUCCESS', statusCode = 200) {
  return res.status(statusCode).json({
    success: true,
    code: 0,
    message: getLocalizedMessage(req, messageKey),
    data: data == null ? {} : data,
  });
}

function error(req, res, err) {
  const messageKey = err && err.code ? String(err.code) : 'common.ERROR';
  const statusCode = Number(err && err.statusCode) || 500;
  const args = Array.isArray(err && err.args) ? err.args : [];
  const data = err && err.data !== undefined ? err.data : null;

  return res.status(statusCode).json({
    success: false,
    code: messageKey,
    message: getLocalizedMessage(req, messageKey, args),
    data,
  });
}

module.exports = {
  success,
  error,
};
