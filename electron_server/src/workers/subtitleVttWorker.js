const { extractAllToVtt } = require('../utils/subtitleVttExtractUtil');

function sendDone(payload) {
  try {
    if (typeof process.send === 'function') {
      process.send({ type: 'subtitleVtt:done', data: payload });
    }
  } catch (_) {}
}

process.on('message', message => {
  if (!message || message.type !== 'extractAll') return;
  const data = message.data && typeof message.data === 'object' ? message.data : {};
  const fileHash = data.fileHash != null ? String(data.fileHash) : '';
  const filePath = data.filePath != null ? String(data.filePath) : '';
  const subtitleCodecs = Array.isArray(data.subtitleCodecs) ? data.subtitleCodecs : null;
  if (!filePath) {
    sendDone({ ok: false, fileHash: String(fileHash || '').trim(), code: 'INVALID_PARAMS', message: 'invalid params' });
    process.exit(1);
    return;
  }
  Promise.resolve()
    .then(async () => {
      const result = await extractAllToVtt({ fileHash, filePath, subtitleCodecs });
      sendDone(result);
      process.exit(result && result.ok ? 0 : 1);
    })
    .catch(e => {
      sendDone({
        ok: false,
        fileHash: String(fileHash || '').trim(),
        code: 'GEN_FAILED',
        message: e && e.message ? e.message : String(e),
      });
      process.exit(1);
    });
});
