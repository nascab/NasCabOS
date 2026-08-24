const Logger = require('../../../utils/logger');
const {
  loadConfig,
  isRpcReachable,
  getDaemonFallbackDownloadDir,
  ensureTrackersResolved,
  getDefaultTrackersForDaemon,
} = require('../../../workers/transmission/transmissionConfig');
const { callTransmissionRpc } = require('./transmissionRpcClient');
const {
  isFallbackDownloadDir,
  normalizeDir,
  setTorrentDownloadDir,
  rememberDownloadDir,
  pathHasTorrentData,
  resolveStoredDownloadDir,
} = require('../../../workers/transmission/transmissionTorrentPathStore');

function pickTorrentField(torrent, ...keys) {
  if (!torrent || typeof torrent !== 'object') return undefined;
  for (const key of keys) {
    if (torrent[key] !== undefined && torrent[key] !== null) return torrent[key];
  }1
  return undefined;
}

function toNumber(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function enrichTorrentForClient(torrent) {
  if (!torrent || typeof torrent !== 'object') return torrent;

  const sizeWhenDone = toNumber(pickTorrentField(torrent, 'sizeWhenDone', 'size_when_done'));
  const totalSize = toNumber(pickTorrentField(torrent, 'totalSize', 'total_size'));
  const leftUntilDoneRaw = pickTorrentField(torrent, 'leftUntilDone', 'left_until_done');
  const leftUntilDone = leftUntilDoneRaw === undefined || leftUntilDoneRaw === null ? null : toNumber(leftUntilDoneRaw);
  const percentDone = toNumber(pickTorrentField(torrent, 'percentDone', 'percent_done'));
  const haveValid = toNumber(pickTorrentField(torrent, 'haveValid', 'have_valid'));
  const haveUnchecked = toNumber(pickTorrentField(torrent, 'haveUnchecked', 'have_unchecked'));
  const downloadedEver = toNumber(pickTorrentField(torrent, 'downloadedEver', 'downloaded_ever'));

  const displayTotalSize = sizeWhenDone > 0 ? sizeWhenDone : totalSize;

  let displayDownloadedBytes = 0;
  if (sizeWhenDone > 0 && leftUntilDone !== null) {
    displayDownloadedBytes = Math.max(0, sizeWhenDone - leftUntilDone);
  } else if (sizeWhenDone > 0 && percentDone > 0) {
    displayDownloadedBytes = sizeWhenDone * percentDone;
  } else if (haveValid + haveUnchecked > 0) {
    displayDownloadedBytes = haveValid + haveUnchecked;
  } else {
    displayDownloadedBytes = downloadedEver;
  }

  if (displayTotalSize > 0) {
    displayDownloadedBytes = Math.min(displayDownloadedBytes, displayTotalSize);
  }

  const addedDate = toNumber(
    pickTorrentField(torrent, 'addedDate', 'added_date', 'dateAdded', 'date_added')
  );

  return {
    ...torrent,
    addedDate: addedDate || torrent.addedDate,
    dateAdded: addedDate || torrent.dateAdded,
    sizeWhenDone: sizeWhenDone || torrent.sizeWhenDone,
    totalSize: totalSize || torrent.totalSize,
    percentDone: percentDone || torrent.percentDone,
    downloadedEver: downloadedEver || torrent.downloadedEver,
    leftUntilDone: leftUntilDone === null ? torrent.leftUntilDone : leftUntilDone,
    haveValid: haveValid || torrent.haveValid,
    haveUnchecked: haveUnchecked || torrent.haveUnchecked,
    displayTotalSize,
    displayDownloadedBytes,
  };
}


async function gracefulCloseTransmissionDaemon(cfg, { timeoutMs = 20000 } = {}) {
  const configObj = cfg || (await loadConfig().catch(() => null));
  if (!configObj || !(await isRpcReachable(configObj))) return false;
  try {
    await callTransmissionRpc(configObj, 'session-close', {});
    Logger.info('[transmission] session-close sent, waiting for daemon to flush state');
    const deadline = Date.now() + Math.max(5000, Number(timeoutMs) || 20000);
    while (Date.now() < deadline) {
      if (!(await isRpcReachable(configObj))) return true;
      await new Promise(r => setTimeout(r, 400));
    }
    Logger.warn('[transmission] daemon still reachable after session-close');
    return false;
  } catch (err) {
    Logger.warn('[transmission] session-close failed', err);
    return false;
  }
}

function isTorrentStillChecking(torrent) {
  const status = toNumber(pickTorrentField(torrent, 'status'));
  if (status === 2) return true;
  const recheckRaw = pickTorrentField(torrent, 'recheckProgress', 'recheck_progress');
  if (recheckRaw === undefined || recheckRaw === null) return false;
  return toNumber(recheckRaw) < 1;
}

async function repairTorrentDownloadLocations(cfg) {
  const configObj = cfg || (await loadConfig());
  if (!(await isRpcReachable(configObj))) return false;

  const result = await callTransmissionRpc(configObj, 'torrent-get', {
    fields: ['id', 'hashString', 'name', 'downloadDir'],
  });
  const torrents = Array.isArray(result.torrents) ? result.torrents : [];
  if (!torrents.length) return false;

  let repaired = 0;
  for (const torrent of torrents) {
    const id = torrent.id;
    const hashString = pickTorrentField(torrent, 'hashString', 'hash_string');
    const name = pickTorrentField(torrent, 'name') || '';
    const currentDir = normalizeDir(pickTorrentField(torrent, 'downloadDir', 'download_dir'));
    if (!hashString || id === undefined || id === null) continue;

    if (currentDir && !isFallbackDownloadDir(currentDir)) {
      await setTorrentDownloadDir(hashString, currentDir);
      continue;
    }

    const storedDir = await resolveStoredDownloadDir(hashString, name);
    if (!storedDir || storedDir === currentDir) continue;

    const dataDir = await pathHasTorrentData(storedDir, name);
    if (!dataDir) {
      Logger.warn('[transmission] stored download dir has no local data, skip repair', {
        hashString,
        name,
        storedDir,
      });
      continue;
    }

    Logger.info('[transmission] repairing torrent download location', {
      id,
      name,
      from: currentDir || getDaemonFallbackDownloadDir(),
      to: dataDir,
    });

    await callTransmissionRpc(configObj, 'torrent-set-location', {
      ids: [id],
      location: dataDir,
      move: false,
    });
    await setTorrentDownloadDir(hashString, dataDir);
    repaired += 1;
  }

  if (repaired > 0) {
    Logger.info('[transmission] repaired torrent download locations', { repaired });
  }
  return repaired > 0;
}

async function prepareTransmissionDaemonAfterReady(cfg, { verifyTimeoutMs = 180000 } = {}) {
  let configObj = cfg || (await loadConfig());
  try {
    configObj = await ensureTrackersResolved(configObj);
    await callTransmissionRpc(configObj, 'session-set', {
      'default-trackers': getDefaultTrackersForDaemon(configObj),
    });
  } catch (err) {
    Logger.warn('[transmission] apply default trackers failed', err);
  }
  try {
    await repairTorrentDownloadLocations(configObj);
  } catch (err) {
    Logger.warn('[transmission] repair torrent download locations failed', err);
  }
  try {
    await verifyIncompleteTorrents(configObj, {
      waitForCompletion: true,
      timeoutMs: verifyTimeoutMs,
    });
  } catch (err) {
    Logger.warn('[transmission] verify incomplete torrents failed', err);
  }
}

async function rememberTorrentDownloadDirsFromList(torrents) {
  if (!Array.isArray(torrents) || !torrents.length) return;
  for (const torrent of torrents) {
    const hashString = pickTorrentField(torrent, 'hashString', 'hash_string');
    const downloadDir = normalizeDir(pickTorrentField(torrent, 'downloadDir', 'download_dir'));
    if (!hashString || !downloadDir || isFallbackDownloadDir(downloadDir)) continue;
    await setTorrentDownloadDir(hashString, downloadDir);
  }
}

async function persistAddedTorrentPath(result, downloadDir) {
  const dir = normalizeDir(downloadDir);
  if (!dir || isFallbackDownloadDir(dir)) return;
  await rememberDownloadDir(dir);
  const added = (result && (result['torrent-added'] || result['torrent-duplicate'])) || null;
  const hashString = added && (added.hashString || added.hash_string);
  if (hashString) {
    await setTorrentDownloadDir(hashString, dir);
    return;
  }
  if (added && added.id !== undefined && added.id !== null) {
    try {
      const cfg = await loadConfig();
      const lookup = await callTransmissionRpc(cfg, 'torrent-get', {
        ids: [added.id],
        fields: ['hashString'],
      });
      const torrent = Array.isArray(lookup.torrents) ? lookup.torrents[0] : null;
      const hash = torrent && (torrent.hashString || torrent.hash_string);
      if (hash) await setTorrentDownloadDir(hash, dir);
    } catch (_) {}
  }
}

async function verifyIncompleteTorrents(cfg, { waitForCompletion = true, timeoutMs = 300000 } = {}) {
  const configObj = cfg || (await loadConfig());
  if (!(await isRpcReachable(configObj))) return false;

  const result = await callTransmissionRpc(configObj, 'torrent-get', {
    fields: ['id', 'percentDone', 'status', 'haveValid', 'haveUnchecked', 'leftUntilDone'],
  });
  const torrents = Array.isArray(result.torrents) ? result.torrents : [];
  const ids = torrents
    .filter(t => toNumber(pickTorrentField(t, 'percentDone', 'percent_done')) < 1)
    .map(t => t.id)
    .filter(id => id !== undefined && id !== null);

  if (!ids.length) return false;

  Logger.info('[transmission] verifying incomplete torrents after daemon ready', { count: ids.length });
  await callTransmissionRpc(configObj, 'torrent-verify', { ids });

  if (!waitForCompletion) return true;

  const deadline = Date.now() + Math.max(10000, Number(timeoutMs) || 300000);
  while (Date.now() < deadline) {
    await new Promise(r => setTimeout(r, 800));
    const statusResult = await callTransmissionRpc(configObj, 'torrent-get', {
      ids,
      fields: ['id', 'percentDone', 'status', 'recheckProgress', 'haveValid', 'haveUnchecked', 'leftUntilDone'],
    });
    const active = Array.isArray(statusResult.torrents) ? statusResult.torrents : [];
    if (!active.some(isTorrentStillChecking)) {
      Logger.info('[transmission] torrent verify finished', {
        torrents: active.map(t => ({
          id: t.id,
          percentDone: pickTorrentField(t, 'percentDone', 'percent_done'),
          haveValid: pickTorrentField(t, 'haveValid', 'have_valid'),
          haveUnchecked: pickTorrentField(t, 'haveUnchecked', 'have_unchecked'),
        })),
      });
      return true;
    }
  }

  Logger.warn('[transmission] torrent verify wait timed out');
  return false;
}

module.exports = {
  pickTorrentField,
  enrichTorrentForClient,
  gracefulCloseTransmissionDaemon,
  repairTorrentDownloadLocations,
  prepareTransmissionDaemonAfterReady,
  rememberTorrentDownloadDirsFromList,
  persistAddedTorrentPath,
  verifyIncompleteTorrents,
};
