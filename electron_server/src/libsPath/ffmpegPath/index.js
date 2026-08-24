var os = require('os');
var path = require('path');
const config = require('../../config/config');
var package = require('../../../package.json');
const fs = require('fs');

var platform = os.platform();
//patch for compatibilit with electron-builder, for smart built process.
if (platform == 'darwin') {
  platform = 'mac';
} else if (platform == 'win32') {
  platform = 'win';
}
//adding browser, for use case when module is bundled using browserify. and added to html using src.
if (platform !== 'linux' && platform !== 'mac' && platform !== 'win' && platform !== 'browser') {
  console.error('Unsupported platform.', platform);
  process.exit(1);
}

var arch = os.arch();
if (platform === 'mac' && arch !== 'x64' && arch !== 'arm64') {
  console.error('Unsupported architecture.');
  process.exit(1);
}

var ffmpegPath = path.join(config.getRootPath(), 'libs', 'ffmpeg', 'bin', platform, arch, platform === 'win' ? 'ffmpeg.exe' : 'ffmpeg');
if (package.isDocker) {
  //docker下使用系统的ffmpeg
  ffmpegPath = 'ffmpeg';
} else {
  try {
    //授予可执行权限
    if (os.platform() == 'linux') {
      fs.chmodSync(ffmpegPath, '777');
    }
  } catch (err) {}
}

// exports.path = ffmpegPath;
module.exports = { path: ffmpegPath };
