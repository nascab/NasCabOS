function handlePhotoWatchWorkerMessage({ initUtil, Logger, message }) {
  if (!message || !message.type) return;
  switch (message.type) {
    case 'newPhotoCome': {
      Logger.info('📸 newPhotoCome, starting related workers');
      try {
        initUtil.startTinyImageWorker();
        initUtil.startOcrWorker();
        initUtil.startFaceWorker();
        initUtil.startPlacesWorker();
        initUtil.startSimilarWorker();
      } catch (err) {
        Logger.error('❌ newPhotoCome handler error:', err);
      }
      break;
    }
  }
}

function handlePhotoIndexWorkerMessage({ initUtil, Logger, message }) {
  if (!message || !message.type) return;
  switch (message.type) {
    case 'photoIndexingFinished': {
      Logger.info('📸 photoIndexingFinished, starting related workers');
      try {
        initUtil.startTinyImageWorker();
        initUtil.startOcrWorker();
        initUtil.startFaceWorker();
        initUtil.startPlacesWorker();
        initUtil.startSimilarWorker();
      } catch (err) {
        Logger.error('❌ photoIndexingFinished handler error:', err);
      }
      break;
    }
  }
}

function handleVideoWatchWorkerMessage({ initUtil, Logger, message }) {
  if (!message || !message.type) return;
  switch (message.type) {
    case 'newVideoCome': {
      Logger.info('🎥 newVideoCome, starting related workers');
      try {
        initUtil.startTinyImageWorker();
        initUtil.startNfoFetchWorker();
        void initUtil.maybeStartSubtitlePreExtractWorker();
      } catch (err) {
        Logger.error('❌ newVideoCome handler error:', err);
      }
      break;
    }
  }
}

function handleVideoIndexWorkerMessage({ initUtil, Logger, message }) {
  if (!message || !message.type) return;
  switch (message.type) {
    case 'videoIndexingFinished': {
      Logger.info('🎥 videoIndexingFinished, starting related workers');
      try {
        initUtil.startTinyImageWorker();
        initUtil.startNfoFetchWorker();
        void initUtil.maybeStartSubtitlePreExtractWorker();
      } catch (err) {
        Logger.error('❌ videoIndexingFinished handler error:', err);
      }
      break;
    }
  }
}

function handleBookWatchWorkerMessage({ initUtil, Logger, message }) {
  if (!message || !message.type) return;
  switch (message.type) {
    case 'startBookIndexWorker': {
      try {
        initUtil.startBookIndexWorker();
      } catch (err) {
        Logger.error('❌ startBookIndexWorker handler error:', err);
      }
      break;
    }
  }
}

function handleBookIndexWorkerMessage({ initUtil, Logger, message }) {
  if (!message || !message.type) return;
  switch (message.type) {
    case 'bookIndexingFinished': {
      Logger.info('📚 bookIndexingFinished, starting related workers');
      try {
        initUtil.startTinyImageWorker();
      } catch (err) {
        Logger.error('❌ bookIndexingFinished handler error:', err);
      }
      break;
    }
  }
}

function handleMusicWatchWorkerMessage({ initUtil, Logger, message }) {
  if (!message || !message.type) return;
  switch (message.type) {
    case 'startMusicIndexWorker': {
      try {
        initUtil.startMusicIndexWorker();
      } catch (err) {
        Logger.error('❌ startMusicIndexWorker handler error:', err);
      }
      break;
    }
  }
}

function handleMusicIndexWorkerMessage({ Logger, message }) {
  if (!message || !message.type) return;
  switch (message.type) {
    case 'musicIndexingFinished': {
      Logger.info('🎵 musicIndexingFinished');
      break;
    }
  }
}

module.exports = {
  handlePhotoWatchWorkerMessage,
  handlePhotoIndexWorkerMessage,
  handleVideoWatchWorkerMessage,
  handleVideoIndexWorkerMessage,
  handleBookWatchWorkerMessage,
  handleBookIndexWorkerMessage,
  handleMusicWatchWorkerMessage,
  handleMusicIndexWorkerMessage,
};
