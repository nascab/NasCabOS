var os = require('os');
var fs = require('fs');
const remoteAssets = require('../../utils/remoteAssetsManager');
const { assertSupportedPlatformArch } = require('../platformArch');

assertSupportedPlatformArch();

function resolveSftpgoPath() {
  const rel = remoteAssets.resolveLibBinaryRelativePath('sftpgo');
  const resolved = remoteAssets.resolvePath(rel);
  try {
    if (os.platform() === 'linux' && fs.existsSync(resolved)) {
      fs.chmodSync(resolved, 0o777);
    }
  } catch (err) {
    console.error('sftpgoPath chmod error:', err);
  }
  return resolved;
}

async function ensureReady() {
  await remoteAssets.ensureLib('sftpgo');
}

module.exports = {
  get path() {
    return resolveSftpgoPath();
  },
  ensureReady,
};
