function handleStartFileWorker({ initUtil }) {
  initUtil.startFileOperationWorker();
}

function handleStartPhotoIndexWorker({ initUtil }) {
  initUtil.startPhotoIndexWorker();
}

function handleStartVideoIndexWorker({ initUtil }) {
  initUtil.startVideoIndexWorker();
}

function handleStartBookIndexWorker({ initUtil }) {
  initUtil.startBookIndexWorker();
}

function handleStartMusicIndexWorker({ initUtil }) {
  initUtil.startMusicIndexWorker();
}

function handleStopPhotoIndexWorker({ expressWorker, initUtil, message }) {
  const requestId = message?.data?.requestId;
  Promise.resolve()
    .then(async () => {
      const stopped = await initUtil.stopPhotoIndexWorker();
      if (!requestId) return;
      try {
        expressWorker.send({
          type: 'stopPhotoIndexWorkerResponse',
          data: { requestId, stopped: !!stopped },
        });
      } catch (_) {}
    })
    .catch(err => {
      if (!requestId) return;
      try {
        expressWorker.send({
          type: 'stopPhotoIndexWorkerResponse',
          data: { requestId, stopped: false, error: err && err.message ? String(err.message) : String(err) },
        });
      } catch (_) {}
    });
}

function handleStopVideoIndexWorker({ expressWorker, initUtil, message }) {
  const requestId = message?.data?.requestId;
  Promise.resolve()
    .then(async () => {
      const stopped = await initUtil.stopVideoIndexWorker();
      if (!requestId) return;
      try {
        expressWorker.send({
          type: 'stopVideoIndexWorkerResponse',
          data: { requestId, stopped: !!stopped },
        });
      } catch (_) {}
    })
    .catch(err => {
      if (!requestId) return;
      try {
        expressWorker.send({
          type: 'stopVideoIndexWorkerResponse',
          data: { requestId, stopped: false, error: err && err.message ? String(err.message) : String(err) },
        });
      } catch (_) {}
    });
}

function handleStopBookIndexWorker({ expressWorker, initUtil, message }) {
  const requestId = message?.data?.requestId;
  Promise.resolve()
    .then(async () => {
      const stopped = await initUtil.stopBookIndexWorker();
      if (!requestId) return;
      try {
        expressWorker.send({
          type: 'stopBookIndexWorkerResponse',
          data: { requestId, stopped: !!stopped },
        });
      } catch (_) {}
    })
    .catch(err => {
      if (!requestId) return;
      try {
        expressWorker.send({
          type: 'stopBookIndexWorkerResponse',
          data: { requestId, stopped: false, error: err && err.message ? String(err.message) : String(err) },
        });
      } catch (_) {}
    });
}

function handleStopMusicIndexWorker({ expressWorker, initUtil, message }) {
  const requestId = message?.data?.requestId;
  Promise.resolve()
    .then(async () => {
      const stopped = await initUtil.stopMusicIndexWorker();
      if (!requestId) return;
      try {
        expressWorker.send({
          type: 'stopMusicIndexWorkerResponse',
          data: { requestId, stopped: !!stopped },
        });
      } catch (_) {}
    })
    .catch(err => {
      if (!requestId) return;
      try {
        expressWorker.send({
          type: 'stopMusicIndexWorkerResponse',
          data: { requestId, stopped: false, error: err && err.message ? String(err.message) : String(err) },
        });
      } catch (_) {}
    });
}

function handleStartTinyImageWorker({ initUtil }) {
  initUtil.startTinyImageWorker();
}


module.exports = {
  startFileWorker: handleStartFileWorker,
  startPhotoIndexWorker: handleStartPhotoIndexWorker,
  startVideoIndexWorker: handleStartVideoIndexWorker,
  startBookIndexWorker: handleStartBookIndexWorker,
  startMusicIndexWorker: handleStartMusicIndexWorker,
  stopPhotoIndexWorker: handleStopPhotoIndexWorker,
  stopVideoIndexWorker: handleStopVideoIndexWorker,
  stopBookIndexWorker: handleStopBookIndexWorker,
  stopMusicIndexWorker: handleStopMusicIndexWorker,
  startTinyImageWorker: handleStartTinyImageWorker,
};
