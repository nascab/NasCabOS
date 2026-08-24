// 主窗口创建模块（中文注释）：统一管理窗口初始化与加载UI
// 使用延迟 require，避免在 Docker/无 Electron 环境下加载本文件时抛错
const fs = require('fs');
const path = require('path');
const { pathToFileURL } = require('url');

function resolveExistingPath(candidates) {
  for (const candidate of candidates) {
    try {
      if (candidate && fs.existsSync(candidate)) return candidate;
    } catch (_) {}
  }
  return candidates[0];
}

function buildRendererUrl() {
  const candidates = [
    path.resolve(__dirname, 'index.html'),
    path.resolve(__dirname, '../../src/ui/index.html'),
    path.resolve(process.resourcesPath || '', 'app', 'ui', 'index.html'),
    path.resolve(process.resourcesPath || '', 'app', 'app', 'ui', 'index.html'),
    path.resolve(process.resourcesPath || '', 'ui', 'index.html'),
  ].filter(Boolean);
  const indexPath = resolveExistingPath(candidates);
  return {
    indexPath,
    indexUrl: pathToFileURL(indexPath).href,
    candidates,
  };
}

async function createMainWindow() {
  let BrowserWindow, Menu;
  try {
    ({ BrowserWindow, Menu } = require('electron'));
  } catch (e) {
    return null;
  }
  // 去掉 Electron 默认应用菜单（File / Edit / Window / Help 等），界面由自定义 UI 承担
  try {
    Menu.setApplicationMenu(null);
  } catch (_) {}

  const win = new BrowserWindow({
    width: 1080,
    height: 720,
    backgroundColor: '#0f1220',
    show: false,
    webPreferences: {
      preload: path.resolve(__dirname, '../preload.js'),
      nodeIntegration: false,
      contextIsolation: true,
      webgl: false,
    },
  });
  const { indexPath, indexUrl, candidates } = buildRendererUrl();

  win.once('ready-to-show', () => {
    if (!win.isDestroyed()) win.show();
  });

  win.webContents.on('did-fail-load', (_event, errorCode, errorDescription, validatedURL) => {
    console.error('[mainWindow] Renderer load failed', {
      errorCode,
      errorDescription,
      validatedURL,
      indexPath,
      indexUrl,
      candidates,
    });
  });

  win.webContents.on('render-process-gone', (_event, details) => {
    console.error('[mainWindow] render-process-gone', {
      reason: details && details.reason,
      exitCode: details && details.exitCode,
      indexPath,
      indexUrl,
    });
  });

  try {
    await win.loadURL(indexUrl);
  } catch (loadUrlError) {
    console.error('[mainWindow] loadURL failed, fallback to loadFile', {
      indexPath,
      indexUrl,
      candidates,
      message: loadUrlError && loadUrlError.message ? loadUrlError.message : String(loadUrlError),
    });
    await win.loadFile(indexPath);
  }

  // 开发模式：打开开发者工具
  if (process.env.NODE_ENV === 'development') {
    win.webContents.openDevTools();
  }

  return win;
}

module.exports = { createMainWindow };
