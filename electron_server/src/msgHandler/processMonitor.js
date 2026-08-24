function handleGetProcessList({ expressWorker, initUtil, message }) {
  const requestId = message && message.data && message.data.requestId ? String(message.data.requestId) : '';
  if (!requestId) return;
  let list = [];
  try {
    list = typeof initUtil.getProcessList === 'function' ? initUtil.getProcessList() : [];
    if (!Array.isArray(list)) list = [];
  } catch (_) {
    list = [];
  }
  try {
    expressWorker.send({
      type: 'getProcessListResponse',
      data: { requestId, list },
    });
  } catch (_) {}
}

module.exports = {
  getProcessList: handleGetProcessList,
};
