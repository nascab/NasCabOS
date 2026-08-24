const fs = require('fs');
const path = require('path');
const os = require('os');

function getAutostartPath(app) {
  const dir = path.join(os.homedir(), '.config', 'autostart');
  const name = `${app.getName()}.desktop`;
  return { dir, file: path.join(dir, name) };
}

function setOpenAtLogin(app, openAtLogin, openAsHidden = false) {
  const platform = process.platform;
  if (platform === 'darwin' || platform === 'win32') {
    try {
      app.setLoginItemSettings({ openAtLogin: !!openAtLogin, openAsHidden: !!openAsHidden });
    } catch {}
    return true;
  }
  if (platform === 'linux') {
    const { dir, file } = getAutostartPath(app);
    if (openAtLogin) {
      try {
        if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
        const execPath = app.getPath('exe');
        const content = ['[Desktop Entry]', 'Type=Application', `Name=${app.getName()}`, `Exec="${execPath}"`, 'X-GNOME-Autostart-enabled=true', 'Terminal=false'].join('\n');
        fs.writeFileSync(file, content);
        return true;
      } catch {
        return false;
      }
    } else {
      try {
        if (fs.existsSync(file)) fs.unlinkSync(file);
        return true;
      } catch {
        return false;
      }
    }
  }
  return false;
}

function getOpenAtLogin(app) {
  const platform = process.platform;
  if (platform === 'darwin' || platform === 'win32') {
    try {
      const s = app.getLoginItemSettings();
      return !!s.openAtLogin;
    } catch {
      return false;
    }
  }
  if (platform === 'linux') {
    try {
      const { file } = getAutostartPath(app);
      return fs.existsSync(file);
    } catch {
      return false;
    }
  }
  return false;
}

module.exports = { setOpenAtLogin, getOpenAtLogin };
