var os = require('os');
var fs = require('fs');
const remoteAssets = require('../../utils/remoteAssetsManager');
const { assertSupportedPlatformArch } = require('../platformArch');

assertSupportedPlatformArch();

function resolveOpenlistPath() {
  const rel = remoteAssets.resolveLibBinaryRelativePath('openlist');
  const resolved = remoteAssets.resolvePath(rel);
  try {
    if (os.platform() === 'linux' && fs.existsSync(resolved)) {
      fs.chmodSync(resolved, 0o777);
    }
  } catch (err) {}
  return resolved;
}

/** OpenList HTTP 端口（与默认 5244 错开） */
const OPENLIST_HTTP_PORT = 15244;

async function ensureReady() {
  await remoteAssets.ensureLib('openlist');
}

module.exports = {
  get path() {
    return resolveOpenlistPath();
  },
  httpPort: OPENLIST_HTTP_PORT,
  ensureReady,
};
