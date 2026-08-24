const path = require('path');
const multer = require('multer');
const fs = require('fs-extra');
const config = require('../../../../config/config');
const FileUtil = require('../../../../utils/fileUtil');
const ResponseUtil = require('../../../apiUtils/responseUtil');

const storage = multer.diskStorage({
  destination: async function (req, file, cb) {
    try {
      const { hash, targetDir } = req.body;
      if (!hash || !targetDir) {
        const tempDir = path.join(config.getUploadTempDir(), 'temp_uploads_stage');
        await fs.ensureDir(tempDir);
        return cb(null, tempDir);
      }

      const chunkDir = path.join(targetDir, `${config.uploadTempFilePrefix}${hash}`);
      await fs.ensureDir(chunkDir);
      cb(null, chunkDir);
    } catch (err) {
      cb(err);
    }
  },
  filename: function (req, file, cb) {
    if (req.body.index !== undefined) {
      cb(null, req.body.index.toString());
    } else {
      const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1e9);
      cb(null, file.fieldname + '-' + uniqueSuffix);
    }
  },
});

const upload = multer({ storage: storage }).single('file');

function uploadChunkStage(req, res, next) {
  upload(req, res, function (err) {
    if (err) {
      const message = FileUtil.getErrorMessageKey(err);
      return ResponseUtil.error(req, res, message);
    }
    next();
  });
}

module.exports = {
  uploadChunkStage,
};
