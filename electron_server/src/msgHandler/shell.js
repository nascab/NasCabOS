function handleShell({ shell, Logger, message }) {
  if (!shell || !message.path) return;

  switch (message.shellType) {
    case 'trash':
      shell
        .trashItem(message.path)
        .then(() => {
          Logger.debug('已经放入回收站:', message.path);
        })
        .catch(err => {
          Logger.error('Move to trash failed:', err, { path: message.path });
        });
      break;

    case 'openPath':
      // 用系统默认程序打开文件/文件夹
      shell
        .openPath(message.path)
        .then(result => {
          if (result) {
            Logger.error('openPath 失败:', result, { path: message.path });
          } else {
            Logger.debug('已在系统中打开:', message.path);
          }
        })
        .catch(err => {
          Logger.error('openPath 异常:', err, { path: message.path });
        });
      break;

    case 'showItemInFolder':
      // 在系统文件管理器中选中并显示文件/文件夹（同步方法，无返回值）
      try {
        shell.showItemInFolder(message.path);
        Logger.debug('已在系统中选中:', message.path);
      } catch (err) {
        Logger.error('showItemInFolder 失败:', err, { path: message.path });
      }
      break;

    default:
      break;
  }
}

module.exports = {
  shell: handleShell,
};
