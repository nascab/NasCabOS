'use strict';

const fs = require('fs');
const path = require('path');

function _basenameNoExt(v) {
  return path.basename(String(v || ''), path.extname(String(v || '')));
}

function _readAscii(buf, offset, length) {
  return buf.slice(offset, offset + length).toString('ascii').replace(/\0+$/g, '').trim();
}

function _readUInt16BE(buf, offset) {
  if (!Buffer.isBuffer(buf) || offset < 0 || offset + 2 > buf.length) return 0;
  return buf.readUInt16BE(offset);
}

function _readUInt32BE(buf, offset) {
  if (!Buffer.isBuffer(buf) || offset < 0 || offset + 4 > buf.length) return 0;
  return buf.readUInt32BE(offset);
}

function _safeDurationMsFrom90k(inTime, outTime) {
  const start = Number(inTime || 0) || 0;
  const end = Number(outTime || 0) || 0;
  return end > start ? Math.round(((end - start) / 90000) * 1000) : 0;
}

function parseMplsBuffer(buffer, playlistId = '') {
  const buf = Buffer.isBuffer(buffer) ? buffer : Buffer.from(buffer || []);
  if (buf.length < 16) return null;
  const magic = _readAscii(buf, 0, 4);
  if (magic !== 'MPLS') return null;

  const playlistStart = _readUInt32BE(buf, 8);
  if (!playlistStart || playlistStart + 10 > buf.length) return null;

  const numberOfPlayItems = _readUInt16BE(buf, playlistStart + 6);
  let cursor = playlistStart + 10;
  const playItems = [];
  for (let i = 0; i < numberOfPlayItems; i += 1) {
    if (cursor + 2 > buf.length) break;
    const itemLength = _readUInt16BE(buf, cursor);
    const itemStart = cursor + 2;
    if (!itemLength || itemStart + itemLength > buf.length) break;

    const clipFile = _readAscii(buf, itemStart, 5);
    const codecId = _readAscii(buf, itemStart + 5, 4);
    const inTime = _readUInt32BE(buf, itemStart + 12);
    const outTime = _readUInt32BE(buf, itemStart + 16);

    if (clipFile) {
      playItems.push({
        clipFile,
        codecId,
        inTime,
        outTime,
        durationMs: _safeDurationMsFrom90k(inTime, outTime),
      });
    }
    cursor = itemStart + itemLength;
  }

  if (playItems.length === 0) return null;
  const totalDurationMs = playItems.reduce((sum, item) => sum + (item.durationMs || 0), 0);
  return {
    playlistId: String(playlistId || '').trim(),
    playItems,
    totalDurationMs,
  };
}

function parseDvdTitleSetInfo(buffer) {
  const buf = Buffer.isBuffer(buffer) ? buffer : Buffer.from(buffer || []);
  if (buf.length < 0xCC + 4) return [];
  const magic = _readAscii(buf, 0, 12);
  if (magic !== 'DVDVIDEO-VMG') return [];

  const ttSrptSector = _readUInt32BE(buf, 0x00C4);
  const ttSrptOffset = ttSrptSector * 2048;
  if (!ttSrptOffset || ttSrptOffset + 8 > buf.length) return [];

  const numTitle = _readUInt16BE(buf, ttSrptOffset);
  const titles = [];
  let cursor = ttSrptOffset + 8;
  for (let i = 0; i < numTitle; i += 1) {
    if (cursor + 12 > buf.length) break;
    const nrOfAngles = buf[cursor + 1] || 0;
    const nrOfPtts = _readUInt16BE(buf, cursor + 2);
    const titleSetNr = buf[cursor + 6] || 0;
    const vtsTtn = buf[cursor + 7] || 0;
    const titleSetSector = _readUInt32BE(buf, cursor + 8);
    titles.push({
      titleNo: i + 1,
      titleSetNr,
      titleSetSector,
      nrOfAngles,
      nrOfPtts,
      vtsTtn,
    });
    cursor += 12;
  }
  return titles.filter(item => item.titleSetNr > 0);
}

function _sortByNumericBasename(items) {
  return [...(items || [])].sort((a, b) => {
    const aName = String(a && a.name ? a.name : '').toLowerCase();
    const bName = String(b && b.name ? b.name : '').toLowerCase();
    const aNums = aName.match(/\d+/g) || [];
    const bNums = bName.match(/\d+/g) || [];
    const len = Math.max(aNums.length, bNums.length);
    for (let i = 0; i < len; i += 1) {
      const an = Number(aNums[i] || 0);
      const bn = Number(bNums[i] || 0);
      if (an !== bn) return an - bn;
    }
    return aName.localeCompare(bName);
  });
}

async function getLocalBdmvDiscContentsFromPlayFile(playFilePath) {
  const resolvedPlayFile = path.resolve(String(playFilePath || '').trim());
  if (!resolvedPlayFile) return { discType: 'bdmv', items: [] };
  const normalized = resolvedPlayFile.replace(/\\/g, '/');
  const match = normalized.match(/^(.*?)(?:\/BDROM|\/BD_ROM|\/BD-ROM)?\/BDMV\/STREAM\/[^/]+$/i);
  if (!match) return { discType: 'bdmv', items: [] };
  const discRoot = match[1];
  const bdmvDir = normalized.includes('/BDROM/BDMV/')
    ? path.join(discRoot, 'BDROM', 'BDMV')
    : normalized.includes('/BD_ROM/BDMV/')
    ? path.join(discRoot, 'BD_ROM', 'BDMV')
    : normalized.includes('/BD-ROM/BDMV/')
    ? path.join(discRoot, 'BD-ROM', 'BDMV')
    : path.join(discRoot, 'BDMV');
  const streamDir = path.join(bdmvDir, 'STREAM');

  let streamFiles = [];
  try {
    streamFiles = await fs.promises.readdir(streamDir, { withFileTypes: true });
  } catch (_) {
    streamFiles = [];
  }
  const fallbackItems = _sortByNumericBasename(
    streamFiles
      .filter(ent => ent && ent.isFile() && /\.(m2ts|mts|ssif)$/i.test(String(ent.name || '')))
      .map(ent => ({
        name: ent.name,
        path: path.join(streamDir, ent.name),
      }))
  );
  return {
    discType: 'bdmv',
    items: fallbackItems.map((entry, idx) => ({
      order_no: idx + 1,
      title: _basenameNoExt(entry.name),
      display_name: entry.name,
      path: entry.path,
      internal_path: '',
      disc_type: 'bdmv',
      total_duration_ms: 0,
      thumbnail_path: entry.path,
      thumbnail_internal_path: '',
      playlist: [
        {
          order_no: 1,
          name: entry.name,
          path: entry.path,
          internal_path: '',
          duration_ms: 0,
        },
      ],
    })),
  };
}

async function getLocalVideoTsDiscContentsFromPlayFile(playFilePath) {
  const resolvedPlayFile = path.resolve(String(playFilePath || '').trim());
  if (!resolvedPlayFile) return { discType: 'video_ts', items: [] };
  const normalized = resolvedPlayFile.replace(/\\/g, '/');
  const match = normalized.match(/^(.*)\/VIDEO_TS\/[^/]+$/i);
  if (!match) return { discType: 'video_ts', items: [] };
  const discRoot = match[1];
  const videoTsDir = path.join(discRoot, 'VIDEO_TS');

  let entries = [];
  try {
    entries = await fs.promises.readdir(videoTsDir, { withFileTypes: true });
  } catch (_) {
    entries = [];
  }

  const items = _sortByNumericBasename(
    entries
      .filter(ent => ent && ent.isFile && ent.isFile())
      .map(ent => String(ent.name || '').trim())
      .filter(name => {
        const match = /^VTS_(\d{2})_(\d+)\.VOB$/i.exec(name);
        return match && Number(match[2]) > 0;
      })
      .map(name => ({
        name,
        path: path.join(videoTsDir, name),
      }))
  );

  return {
    discType: 'video_ts',
    items: items.map((entry, idx) => {
      const match = /^VTS_(\d{2})_(\d+)\.VOB$/i.exec(entry.name);
      const titleNo = match ? Number(match[1]) || 0 : 0;
      const partNo = match ? Number(match[2]) || 0 : 0;
      return {
        order_no: idx + 1,
        title: titleNo > 0 ? `Title ${String(titleNo).padStart(2, '0')} - Part ${partNo}` : _basenameNoExt(entry.name),
        display_name: entry.name,
        path: entry.path,
        internal_path: '',
        disc_type: 'video_ts',
        total_duration_ms: 0,
        thumbnail_path: entry.path,
        thumbnail_internal_path: '',
        playlist: [
          {
            order_no: 1,
            name: entry.name,
            path: entry.path,
            internal_path: '',
            duration_ms: 0,
          },
        ],
      };
    }),
  };
}

module.exports = {
  parseMplsBuffer,
  parseDvdTitleSetInfo,
  getLocalBdmvDiscContentsFromPlayFile,
  getLocalVideoTsDiscContentsFromPlayFile,
};
