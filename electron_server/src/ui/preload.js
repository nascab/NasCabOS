const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  onLog: callback => ipcRenderer.on('log-entry', (_event, value) => callback(value)),
  getServiceStatus: async () => {
    const res = await ipcRenderer.invoke('service:getStatus');
    return {
      ip: (res && res.ipAddresses && res.ipAddresses[0]) || '127.0.0.1',
      port: res && res.httpPort,
      httpsPort: res && res.httpsPort,
      express: res && res.expressStarted,
      databaseDir: res && res.databaseDir,
      cacheDir: res && res.cacheDir,
    };
  },
  getProcessList: () => ipcRenderer.invoke('process:getList'),
  getAdminInfo: async () => {
    const res = await ipcRenderer.invoke('user:getAdmin');
    return { username: res && res.username };
  },
  updateAdminPassword: password => ipcRenderer.invoke('user:changeAdminPassword', password),
  openLink: url => ipcRenderer.invoke('open:external', url),
  getVersion: async () => {
    const res = await ipcRenderer.invoke('app:getInfo');
    return res && res.version;
  },
  getSettings: () => ipcRenderer.invoke('settings:getStartupOptions'),
  saveSettings: settings => ipcRenderer.invoke('settings:setStartupOptions', settings),
  minimizeWindow: () => ipcRenderer.invoke('minimize-window'),
  openPath: p => ipcRenderer.invoke('open:path', p),
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
