// 预加载脚本：安全桥接渲染与主进程通信（中文注释）
// 暴露 nacsab 与 electronAPI 两套接口，兼容旧代码
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('nascab', {
  // 服务状态（拉取）
  getServiceStatus: () => ipcRenderer.invoke('service:getStatus'),
  // 最近日志（拉取）
  getRecentLogs: () => ipcRenderer.invoke('logs:getRecent'),
  // 打开外部网址
  openWebsite: url => ipcRenderer.invoke('open:external', url),
  // 应用信息（版本号）
  getAppInfo: () => ipcRenderer.invoke('app:getInfo'),
  // 启动选项获取/设置
  getStartupOptions: () => ipcRenderer.invoke('settings:getStartupOptions'),
  setStartupOptions: payload => ipcRenderer.invoke('settings:setStartupOptions', payload),
  // 管理员信息与改密
  getAdminInfo: () => ipcRenderer.invoke('user:getAdmin'),
  changeAdminPassword: newPassword => ipcRenderer.invoke('user:changeAdminPassword', newPassword),
  getInitialAdminInfo: () => ipcRenderer.invoke('user:getInitialAdmin'),
  getAdminSecurity: () => ipcRenderer.invoke('user:getAdminSecurity'),
  updateAdmin: payload => ipcRenderer.invoke('user:updateAdmin', payload),
  resetAdmin2fa: () => ipcRenderer.invoke('user:resetAdmin2fa'),
  // 主动推送事件订阅（服务状态、日志）
  onServiceStatus: cb => ipcRenderer.on('service:status', (_, data) => cb(data)),
  onRecentLogs: cb => ipcRenderer.on('logs:recent', (_, data) => cb(data)),
  getMacFullDiskAccessStatus: () => ipcRenderer.invoke('mac:getFullDiskAccessStatus'),
  onMacFullDiskAccessStatus: cb => ipcRenderer.on('mac:fullDiskAccess', (_, data) => cb(data)),
  // 自动更新：仅检测，有更新时由 UI 在关于卡片显示「去下载」
  onUpdateStatus: cb => ipcRenderer.on('update:status', (_, data) => cb(data)),
  onUpdateAvailable: cb => ipcRenderer.on('update:available', (_, data) => cb(data)),
  // UI 语言获取与设置
  getLanguage: () => ipcRenderer.invoke('ui:getLanguage'),
  setLanguage: lang => ipcRenderer.invoke('ui:setLanguage', lang),
  getFeatureAccessScope: () => ipcRenderer.invoke('settings:getFeatureAccessScope'),
  setFeatureAccessScope: payload => ipcRenderer.invoke('settings:setFeatureAccessScope', payload),
  selectDirectories: () => ipcRenderer.invoke('settings:selectDirectories'),
  vacuumAllDatabases: () => ipcRenderer.invoke('database:vacuumAll'),
  // Cache statistics & cleanup
  scanCacheFolders: (cacheDir, folders, jobId) => ipcRenderer.invoke('cache:scanFolders', { cacheDir, folders, jobId }),
  cancelCacheScan: jobId => ipcRenderer.invoke('cache:cancelScan', jobId),
  cleanCacheFolders: (cacheDir, folders, jobId) => ipcRenderer.invoke('cache:cleanFolders', { cacheDir, folders, jobId }),
  onCacheScanProgress: cb => {
    const handler = (_event, data) => cb(data);
    ipcRenderer.on('cache:scanProgress', handler);
    return () => ipcRenderer.removeListener('cache:scanProgress', handler);
  },
  onCacheScanComplete: cb => {
    const handler = (_event, data) => cb(data);
    ipcRenderer.on('cache:scanComplete', handler);
    return () => ipcRenderer.removeListener('cache:scanComplete', handler);
  },
  onCacheCleanProgress: cb => {
    const handler = (_event, data) => cb(data);
    ipcRenderer.on('cache:cleanProgress', handler);
    return () => ipcRenderer.removeListener('cache:cleanProgress', handler);
  },
  onCacheCleanComplete: cb => {
    const handler = (_event, data) => cb(data);
    ipcRenderer.on('cache:cleanComplete', handler);
    return () => ipcRenderer.removeListener('cache:cleanComplete', handler);
  },
});

contextBridge.exposeInMainWorld('electronAPI', {
  // 兼容旧渲染代码的服务状态接口
  getServiceStatus: async () => {
    const s = await ipcRenderer.invoke('service:getStatus');
    const ip = (s.ipAddresses && s.ipAddresses[0]) || '127.0.0.1';
    const port = s.httpPort || null;
    const httpsPort = s.httpsPort || null;
    const express = !!s.expressStarted;
    return {
      ip,
      ipAddresses: Array.isArray(s.ipAddresses) ? s.ipAddresses : [],
      port,
      httpsPort,
      httpAddresses: Array.isArray(s.httpAddresses) ? s.httpAddresses : [],
      httpsAddresses: Array.isArray(s.httpsAddresses) ? s.httpsAddresses : [],
      express,
      databaseDir: s.databaseDir || '',
      cacheDir: s.cacheDir || '',
      databaseTotalBytes: typeof s.databaseTotalBytes === 'number' ? s.databaseTotalBytes : null,
    };
  },
  getProcessList: async () => {
    const list = await ipcRenderer.invoke('process:getList');
    return Array.isArray(list) ? list : [];
  },
  // 管理员信息与改密（兼容）
  getAdminInfo: async () => {
    const r = await ipcRenderer.invoke('user:getAdmin');
    return r;
  },
  updateAdminPassword: async password => {
    const r = await ipcRenderer.invoke('user:changeAdminPassword', password);
    return r && typeof r === 'object' ? r : { success: !!r, error: 'FAILED' };
  },
  getInitialAdminInfo: async () => {
    return await ipcRenderer.invoke('user:getInitialAdmin');
  },
  getAdminSecurity: async () => {
    return await ipcRenderer.invoke('user:getAdminSecurity');
  },
  updateAdmin: async payload => {
    return await ipcRenderer.invoke('user:updateAdmin', payload);
  },
  resetAdmin2fa: async () => {
    return await ipcRenderer.invoke('user:resetAdmin2fa');
  },
  // 启动选项与版本（兼容）
  getSettings: async () => {
    const r = await ipcRenderer.invoke('settings:getStartupOptions');
    return {
      startOnBoot: !!r.openAtLogin,
      minimizeOnStart: !!r.minimizeOnStart,
      autoDiscoverServer: r.autoDiscoverServer !== false,
    };
  },
  getVersion: async () => {
    const info = await ipcRenderer.invoke('app:getInfo');
    return info.version || '';
  },
  saveSettings: async settings => {
    return await ipcRenderer.invoke('settings:setStartupOptions', {
      openAtLogin: !!settings.startOnBoot,
      minimizeOnStart: !!settings.minimizeOnStart,
      autoDiscoverServer: !!settings.autoDiscoverServer,
    });
  },
  getFeatureAccessScope: async () => {
    return await ipcRenderer.invoke('settings:getFeatureAccessScope');
  },
  saveFeatureAccessScope: async payload => {
    return await ipcRenderer.invoke('settings:setFeatureAccessScope', payload);
  },
  selectDirectories: async () => {
    return await ipcRenderer.invoke('settings:selectDirectories');
  },
  openLink: async url => {
    return await ipcRenderer.invoke('open:external', url);
  },
  openPath: async path => {
    return await ipcRenderer.invoke('open:path', path);
  },
  vacuumAllDatabases: () => ipcRenderer.invoke('database:vacuumAll'),
  // 日志推送（兼容：取最近一条）
  onLog: cb => {
    ipcRenderer.on('logs:recent', (_, payload) => {
      if (Array.isArray(payload) && payload.length) {
        const last = payload[payload.length - 1];
        if (last && last.level !== 'debug') cb(last);
      } else if (payload && payload.level && payload.level !== 'debug') {
        cb(payload);
      }
    });
  },
  onLogs: cb => {
    ipcRenderer.on('logs:recent', (_, payload) => {
      if (Array.isArray(payload)) {
        cb(payload.filter(l => l && l.level !== 'debug'));
      }
    });
  },
});
