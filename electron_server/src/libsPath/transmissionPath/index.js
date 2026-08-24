var os = require('os');
var path = require('path');
const config = require('../../config/config');
var fs = require('fs');

var platform = os.platform();
if (platform == 'darwin') {
  platform = 'mac';
} else if (platform == 'win32') {
  platform = 'win';
}

if (platform !== 'linux' && platform !== 'mac' && platform !== 'win' && platform !== 'browser') {
  console.error('Unsupported platform.', platform);
  process.exit(1);
}

var arch = os.arch();
if (platform === 'mac' && arch !== 'x64' && arch !== 'arm64') {
  console.error('Unsupported architecture.');
  process.exit(1);
}

var binaryName = platform === 'win' ? 'transmission-daemon.exe' : 'transmission-daemon';
var transmissionPath = path.join(config.getRootPath(), 'libs', 'transmission', platform, arch, binaryName);
try {
  if (os.platform() === 'linux' && fs.existsSync(transmissionPath)) {
    fs.chmodSync(transmissionPath, 0o755);
  }
} catch (err) {}

module.exports = { path: transmissionPath, binaryDir: path.dirname(transmissionPath) };
