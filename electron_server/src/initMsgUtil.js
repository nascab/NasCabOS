const dispatchExpressMessage = require('./msgHandler/expressDispatcher');
const watchHandlers = require('./msgHandler/watchHandlers');

class InitMsgUtil {
  constructor({ initUtil, singletonWorkerManager, Logger, shell }) {
    this.initUtil = initUtil;
    this.singletonWorkerManager = singletonWorkerManager;
    this.Logger = Logger;
    this.shell = shell;
  }

  bindExpressWorker(expressWorker, { httpPort, httpsPort, serverId, jwtSecret }) {
    this.serverId = serverId;
    expressWorker.on('message', message => {
      this.handleExpressWorkerMessage(expressWorker, message, { httpPort, httpsPort, serverId, jwtSecret });
    });
  }

  bindPhotoWatchWorker(photoWatchWorker) {
    if (!photoWatchWorker || typeof photoWatchWorker.on !== 'function') return;
    photoWatchWorker.on('message', message => {
      this.handlePhotoWatchWorkerMessage(photoWatchWorker, message);
    });
  }
  bindVideoWatchWorker(videoWatchWorker) {
    if (!videoWatchWorker || typeof videoWatchWorker.on !== 'function') return;
    videoWatchWorker.on('message', message => {
      this.handleVideoWatchWorkerMessage(videoWatchWorker, message);
    });
  }
  bindBookWatchWorker(bookWatchWorker) {
    if (!bookWatchWorker || typeof bookWatchWorker.on !== 'function') return;
    bookWatchWorker.on('message', message => {
      this.handleBookWatchWorkerMessage(bookWatchWorker, message);
    });
  }
  bindMusicWatchWorker(musicWatchWorker) {
    if (!musicWatchWorker || typeof musicWatchWorker.on !== 'function') return;
    musicWatchWorker.on('message', message => {
      this.handleMusicWatchWorkerMessage(musicWatchWorker, message);
    });
  }
  bindPhotoIndexWorker(photoIndexWorker) {
    if (!photoIndexWorker || typeof photoIndexWorker.on !== 'function') return;
    photoIndexWorker.on('message', message => {
      this.handlePhotoIndexWorkerMessage(photoIndexWorker, message);
    });
  }
  bindVideoIndexWorker(videoIndexWorker) {
    if (!videoIndexWorker || typeof videoIndexWorker.on !== 'function') return;
    videoIndexWorker.on('message', message => {
      this.handleVideoIndexWorkerMessage(videoIndexWorker, message);
    });
  }
  bindBookIndexWorker(bookIndexWorker) {
    if (!bookIndexWorker || typeof bookIndexWorker.on !== 'function') return;
    bookIndexWorker.on('message', message => {
      this.handleBookIndexWorkerMessage(bookIndexWorker, message);
    });
  }
  bindMusicIndexWorker(musicIndexWorker) {
    if (!musicIndexWorker || typeof musicIndexWorker.on !== 'function') return;
    musicIndexWorker.on('message', message => {
      this.handleMusicIndexWorkerMessage(musicIndexWorker, message);
    });
  }

  handlePhotoWatchWorkerMessage(photoWatchWorker, message) {
    watchHandlers.handlePhotoWatchWorkerMessage({ initUtil: this.initUtil, Logger: this.Logger, message });
  }
  handlePhotoIndexWorkerMessage(photoIndexWorker, message) {
    watchHandlers.handlePhotoIndexWorkerMessage({ initUtil: this.initUtil, Logger: this.Logger, message });
  }
  handleVideoWatchWorkerMessage(videoWatchWorker, message) {
    watchHandlers.handleVideoWatchWorkerMessage({ initUtil: this.initUtil, Logger: this.Logger, message });
  }
  handleBookWatchWorkerMessage(bookWatchWorker, message) {
    watchHandlers.handleBookWatchWorkerMessage({ initUtil: this.initUtil, Logger: this.Logger, message });
  }
  handleMusicWatchWorkerMessage(musicWatchWorker, message) {
    watchHandlers.handleMusicWatchWorkerMessage({ initUtil: this.initUtil, Logger: this.Logger, message });
  }
  handleVideoIndexWorkerMessage(videoIndexWorker, message) {
    watchHandlers.handleVideoIndexWorkerMessage({ initUtil: this.initUtil, Logger: this.Logger, message });
  }
  handleBookIndexWorkerMessage(bookIndexWorker, message) {
    watchHandlers.handleBookIndexWorkerMessage({ initUtil: this.initUtil, Logger: this.Logger, message });
  }
  handleMusicIndexWorkerMessage(musicIndexWorker, message) {
    watchHandlers.handleMusicIndexWorkerMessage({ Logger: this.Logger, message });
  }

  handleExpressWorkerMessage(expressWorker, message, { httpPort, httpsPort, serverId, jwtSecret }) {
    dispatchExpressMessage({
      expressWorker,
      message,
      initUtil: this.initUtil,
      singletonWorkerManager: this.singletonWorkerManager,
      Logger: this.Logger,
      shell: this.shell,
      httpPort,
      httpsPort,
      serverId,
      jwtSecret,
    });
  }
}

module.exports = InitMsgUtil;
