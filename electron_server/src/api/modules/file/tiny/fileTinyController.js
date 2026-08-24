const ResponseUtil = require('../../../apiUtils/responseUtil');
const fileService = require('../core/fileService');
const fs = require('fs');

async function getTiny(req, res) {
  // console.log('tiny tiny', req.query.path, req.query.size);
  try {
    const { path: filePath, size } = req.query;
    if (!filePath) return ResponseUtil.error(req, res, 'file.INVALID_PATH', 400);
    const targetPath = await fileService.getTinyImgByPath(filePath, size);
    if (fs.existsSync(targetPath)) {
      return await res.sendFile(targetPath);
    } else {
      return res.sendStatus(404);
    }
  } catch (err) {
    if (err.message !== 'file.TINY_PENDING') {
      console.log(err, req.query.path);
    }
    if (err.message === 'file.NOT_FOUND') return res.sendStatus(404);
    if (err.message === 'file.TINY_PENDING') return res.status(202).set('Retry-After', '2').end();
    if (err.message === 'file.UNSUPPORTED_TYPE') return res.sendStatus(415);
    return ResponseUtil.error(req, res, 'file.TINY_FAILED', 500, { error: err.message });
  }
}

module.exports = {
  getTiny,
};
