/**
 * 硬超时：超时后 reject，不等待原 promise 结束（调用方应自行决定是否接受后台继续执行）
 */
function withHardTimeout(promise, timeoutMs, errMessage = 'timeout') {
  const ms = Math.max(1, Number(timeoutMs) || 1);
  let timer;
  const timeoutPromise = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(errMessage)), ms);
  });
  return Promise.race([Promise.resolve(promise), timeoutPromise]).finally(() => {
    if (timer) clearTimeout(timer);
  });
}

async function pathAccessible(filePath, timeoutMs = 8000) {
  const fs = require('fs');
  try {
    await withHardTimeout(fs.promises.access(filePath, fs.constants.F_OK), timeoutMs, 'path.access_timeout');
    return true;
  } catch {
    return false;
  }
}

module.exports = {
  withHardTimeout,
  pathAccessible,
};
