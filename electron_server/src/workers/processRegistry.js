'use strict';

const WORKER_META = {
  'ai/faces/faceWorker.js': { nameKey: 'process.worker.ai.faces.name', purposeKey: 'process.worker.ai.faces.purpose' },
  'ai/ocr/ocrWorker.js': { nameKey: 'process.worker.ai.ocr.name', purposeKey: 'process.worker.ai.ocr.purpose' },
  'ai/places/placesWorker.js': { nameKey: 'process.worker.ai.places.name', purposeKey: 'process.worker.ai.places.purpose' },
  'ai/similar/similarWorker.js': { nameKey: 'process.worker.ai.similar.name', purposeKey: 'process.worker.ai.similar.purpose' },
  'encryptedSpaceExport/encryptedSpaceExportWorker.js': { nameKey: 'process.worker.encryptedExport.name', purposeKey: 'process.worker.encryptedExport.purpose' },
  'fileAllIndex/fileAllIndexWorker.js': { nameKey: 'process.worker.fileAllIndex.name', purposeKey: 'process.worker.fileAllIndex.purpose' },
  'fileBackup/fileBackupTaskWorker.js': { nameKey: 'process.worker.fileBackup.name', purposeKey: 'process.worker.fileBackup.purpose' },
  'fileList/listDirectoryWorker.js': { nameKey: 'process.worker.fileList.name', purposeKey: 'process.worker.fileList.purpose' },
  'fileMount/fileMountWorker.js': { nameKey: 'process.worker.fileMount.name', purposeKey: 'process.worker.fileMount.purpose' },
  'openlist/openlistWorker.js': { nameKey: 'process.worker.openlist.name', purposeKey: 'process.worker.openlist.purpose' },
  'fileServer/fileServerWorker.js': { nameKey: 'process.worker.fileServer.name', purposeKey: 'process.worker.fileServer.purpose' },
  'mediaTool/imgBatchCompress/imgBatchCompressWorker.js': { nameKey: 'process.worker.imgBatchCompress.name', purposeKey: 'process.worker.imgBatchCompress.purpose' },
  'mediaTool/videoTrans/videoTransWorker.js': { nameKey: 'process.worker.videoTrans.name', purposeKey: 'process.worker.videoTrans.purpose' },
  'mediaTool/audioTrans/audioTransWorker.js': { nameKey: 'process.worker.audioTrans.name', purposeKey: 'process.worker.audioTrans.purpose' },
  'mediaTool/mediaArrange/mediaArrangeWorker.js': { nameKey: 'process.worker.mediaArrange.name', purposeKey: 'process.worker.mediaArrange.purpose' },
  'musicIndex/musicIndexWorker.js': { nameKey: 'process.worker.musicIndex.name', purposeKey: 'process.worker.musicIndex.purpose' },
  'musicIndex/musicWatchWorker.js': { nameKey: 'process.worker.musicWatch.name', purposeKey: 'process.worker.musicWatch.purpose' },
  'bookIndex/bookIndexWorker.js': { nameKey: 'process.worker.bookIndex.name', purposeKey: 'process.worker.bookIndex.purpose' },
  'bookIndex/bookWatchWorker.js': { nameKey: 'process.worker.bookWatch.name', purposeKey: 'process.worker.bookWatch.purpose' },
  'p2pConnectWorker/p2pConnectWorker.js': { nameKey: 'process.worker.p2pConnect.name', purposeKey: 'process.worker.p2pConnect.purpose' },
  'ddnsWorker/ddnsWorker.js': { nameKey: 'process.worker.ddns.name', purposeKey: 'process.worker.ddns.purpose' },
  'photoIndex/photoIndexWorker.js': { nameKey: 'process.worker.photoIndex.name', purposeKey: 'process.worker.photoIndex.purpose' },
  'photoIndex/photoWatchWorker.js': { nameKey: 'process.worker.photoWatch.name', purposeKey: 'process.worker.photoWatch.purpose' },
  'photoIndex/gpsSupplementWorker.js': { nameKey: 'process.worker.gpsSupplement.name', purposeKey: 'process.worker.gpsSupplement.purpose' },
  'videoIndex/videoIndexWorker.js': { nameKey: 'process.worker.videoIndex.name', purposeKey: 'process.worker.videoIndex.purpose' },
  'videoIndex/videoWatchWorker.js': { nameKey: 'process.worker.videoWatch.name', purposeKey: 'process.worker.videoWatch.purpose' },
  'videoIndex/nfoFetchWorker/nfoFetchWorker.js': { nameKey: 'process.worker.nfoFetch.name', purposeKey: 'process.worker.nfoFetch.purpose' },
  'videoIndex/subtitlePreExtractWorker/subtitlePreExtractWorker.js': {
    nameKey: 'process.worker.subtitlePreExtract.name',
    purposeKey: 'process.worker.subtitlePreExtract.purpose',
  },
  'subtitleVttWorker.js': { nameKey: 'process.worker.subtitleVtt.name', purposeKey: 'process.worker.subtitleVtt.purpose' },
  'videoIndex/videoScrapeWorker/videoScrapeWorker.js': { nameKey: 'process.worker.videoScrape.name', purposeKey: 'process.worker.videoScrape.purpose' },
  'backgroundTaskWorker.js': { nameKey: 'process.worker.backgroundTask.name', purposeKey: 'process.worker.backgroundTask.purpose' },
  'expressBroadcastWorker.js': { nameKey: 'process.worker.expressBroadcast.name', purposeKey: 'process.worker.expressBroadcast.purpose' },
  'ffmpegHwTestWorker.js': { nameKey: 'process.worker.ffmpegHwTest.name', purposeKey: 'process.worker.ffmpegHwTest.purpose' },
  'fileOperationWorker.js': { nameKey: 'process.worker.fileOperation.name', purposeKey: 'process.worker.fileOperation.purpose' },
  'dockerTaskWorker.js': { nameKey: 'process.worker.dockerTask.name', purposeKey: 'process.worker.dockerTask.purpose' },
  'hwMonitor.js': { nameKey: 'process.worker.hwMonitor.name', purposeKey: 'process.worker.hwMonitor.purpose' },
  'transcodeWorker.js': { nameKey: 'process.worker.transcode.name', purposeKey: 'process.worker.transcode.purpose' },
  'transmission/transmissionWorker.js': { nameKey: 'process.worker.transmission.name', purposeKey: 'process.worker.transmission.purpose' },
  'tinyImageWorker.js': { nameKey: 'process.worker.tinyImage.name', purposeKey: 'process.worker.tinyImage.purpose' },
  'expressWorker.js': { nameKey: 'process.worker.express.name', purposeKey: 'process.worker.express.purpose' },
};

function rowFromRegistryItem(item) {
  return {
    pid: item.pid,
    workerPath: item.workerPath,
    role: item.role,
    nameKey: item.nameKey,
    purposeKey: item.purposeKey,
    startedAt: item.startedAt,
  };
}

class ProcessRegistry {
  constructor() {
    this.pidMap = new Map();
  }

  registerProcess({ pid, workerPath = '', role = '' }) {
    const pidNum = Number(pid);
    if (!Number.isFinite(pidNum) || pidNum <= 0) return;
    const normalizedPath = String(workerPath || '').replace(/\\/g, '/');
    const meta = WORKER_META[normalizedPath] || {};
    this.pidMap.set(pidNum, {
      pid: pidNum,
      workerPath: normalizedPath,
      role: role || normalizedPath || 'worker',
      nameKey: meta.nameKey || 'process.worker.unknown.name',
      purposeKey: meta.purposeKey || 'process.worker.unknown.purpose',
      startedAt: Date.now(),
    });
  }

  removeProcessByPid(pid) {
    const pidNum = Number(pid);
    if (!Number.isFinite(pidNum) || pidNum <= 0) return;
    this.pidMap.delete(pidNum);
  }

  getProcessList() {
    try {
      const items = Array.from(this.pidMap.values());
      return items
        .map(item => rowFromRegistryItem(item))
        .sort((a, b) => a.pid - b.pid);
    } catch (_) {
      try {
        return Array.from(this.pidMap.values())
          .map(item => rowFromRegistryItem(item))
          .sort((a, b) => a.pid - b.pid);
      } catch (__) {
        return [];
      }
    }
  }
}

let instance = null;
function getProcessRegistry() {
  if (!instance) instance = new ProcessRegistry();
  return instance;
}

module.exports = {
  getProcessRegistry,
};
