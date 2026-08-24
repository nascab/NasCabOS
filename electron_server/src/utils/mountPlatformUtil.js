let packageJson = {};
try {
  packageJson = require('../../package.json');
} catch (_) {}

function isDockerServer() {
  return !!packageJson.isDocker;
}

function assertMountSupportedOnPlatform(msgKey = 'fileMount.PLATFORM_NOT_SUPPORTED') {
  if (!isDockerServer()) return;
  const err = new Error(String(msgKey || 'fileMount.PLATFORM_NOT_SUPPORTED'));
  err.statusCode = 400;
  throw err;
}

module.exports = {
  isDockerServer,
  assertMountSupportedOnPlatform,
};
