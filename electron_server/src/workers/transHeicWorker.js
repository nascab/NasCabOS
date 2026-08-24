const { parentPort, workerData } = require('worker_threads');
const libheif = require('libheif-js/wasm-bundle');

function returnResult() {
  parentPort.postMessage({ code: 0, output: workerData.output });
  process.exit(0);
}
// 可以直接通过workerData接收主线程初始化时传递的数据
if (workerData && workerData.inputBuffer) {
  const decoder = new libheif.HeifDecoder();
  const data = decoder.decode(workerData.inputBuffer);
  const image = data[0];
  if (!image) {
    return returnResult();
  }
  const width = image.get_width();
  const height = image.get_height();
  image.display({ data: new Uint8ClampedArray(width * height * 4), width, height }, displayData => {
    if (!displayData || !displayData.data) {
      workerData.output = null;
      return returnResult();
    }
    workerData.output = displayData;
    return returnResult();
  });
} else {
  console.log('输入数据没有获取成功');
  returnResult();
}

// 错误处理
parentPort.on('error', err => {
  console.error('Heic worker error:', err);
  returnResult();
});

// 工作线程完成时的清理
parentPort.on('close', () => {
  console.log('Heic worker stopped.');
});
process.on('uncaughtException', (err, origin) => {
  console.log('Error occurred heic worker ', err);
  returnResult();
});
