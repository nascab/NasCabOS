function handleResetPhotoWatchWorker({ initUtil }) {
  initUtil.resetPhotoWatchWorker();
}

function handleResetVideoWatchWorker({ initUtil }) {
  initUtil.resetVideoWatchWorker();
}

function handleResetBookWatchWorker({ initUtil }) {
  initUtil.resetBookWatchWorker();
}

function handleResetMusicWatchWorker({ initUtil }) {
  initUtil.resetMusicWatchWorker();
}

module.exports = {
  resetPhotoWatchWorker: handleResetPhotoWatchWorker,
  resetVideoWatchWorker: handleResetVideoWatchWorker,
  resetBookWatchWorker: handleResetBookWatchWorker,
  resetMusicWatchWorker: handleResetMusicWatchWorker,
};
