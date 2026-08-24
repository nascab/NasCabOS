'use strict';

const os = require('os');

function getPlatformArch() {
  let platform = os.platform();
  if (platform === 'darwin') {
    platform = 'mac';
  } else if (platform === 'win32') {
    platform = 'win';
  }

  const arch = os.arch();
  return { platform, arch };
}

function assertSupportedPlatformArch() {
  const { platform, arch } = getPlatformArch();
  if (platform !== 'linux' && platform !== 'mac' && platform !== 'win' && platform !== 'browser') {
    console.error('Unsupported platform.', platform);
    process.exit(1);
  }
  if (platform === 'mac' && arch !== 'x64' && arch !== 'arm64') {
    console.error('Unsupported architecture.');
    process.exit(1);
  }
  return { platform, arch };
}

module.exports = {
  getPlatformArch,
  assertSupportedPlatformArch,
};
