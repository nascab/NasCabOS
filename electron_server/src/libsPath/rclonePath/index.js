var os = require('os');
var fs = require('fs');
const remoteAssets = require('../../utils/remoteAssetsManager');
const { assertSupportedPlatformArch } = require('../platformArch');

assertSupportedPlatformArch();

function resolveRclonePath() {
  const rel = remoteAssets.resolveLibBinaryRelativePath('rclone');
  const resolved = remoteAssets.resolvePath(rel);
  try {
    if (os.platform() === 'linux' && fs.existsSync(resolved)) {
      fs.chmodSync(resolved, 0o777);
    }
  } catch (err) {}
  return resolved;
}

async function ensureReady() {
  await remoteAssets.ensureLib('rclone');
}

module.exports = {
  get path() {
    return resolveRclonePath();
  },
  ensureReady,
};
