'use strict';

const fs = require('fs');
const path = require('path');
const config = require('../../config/config');
const FileUtil = require('../../utils/fileUtil');
const Logger = require('../../utils/logger');
const { getFirstLetter } = require('../../utils/firstLetterUtil');

function isVideoFileExt(ext) {
  const e = String(ext || '').toLowerCase();
  if (!e) return false;
  return Array.isArray(config.videoTypeList) && config.videoTypeList.includes(e);
}

const _CN_NUM_CHAR_RE = /[零〇一二两三四五六七八九十百千]+/;
const _CN_NUM_ALL_RE = /^[零〇一二两三四五六七八九十百千]+$/;

function _parseCnNumberText(text) {
  const s = String(text || '').trim();
  if (!s) return 0;
  if (/^\d+$/.test(s)) return Number(s) || 0;
  if (!_CN_NUM_ALL_RE.test(s)) return 0;

  const digitMap = {
    零: 0,
    〇: 0,
    一: 1,
    二: 2,
    两: 2,
    三: 3,
    四: 4,
    五: 5,
    六: 6,
    七: 7,
    八: 8,
    九: 9,
  };
  const unitMap = {
    十: 10,
    百: 100,
    千: 1000,
  };

  let total = 0;
  let num = 0;
  for (const ch of Array.from(s)) {
    if (Object.prototype.hasOwnProperty.call(digitMap, ch)) {
      num = digitMap[ch];
      continue;
    }
    if (Object.prototype.hasOwnProperty.call(unitMap, ch)) {
      const unit = unitMap[ch];
      const base = num === 0 ? 1 : num;
      total += base * unit;
      num = 0;
      continue;
    }
    return 0;
  }
  total += num;
  if (!Number.isFinite(total) || total <= 0) return 0;
  return total;
}

function _seasonNumFromMatchText(text) {
  const raw = String(text || '').trim();
  if (!raw) return 0;
  if (/^\d+$/.test(raw)) return Number(raw) || 0;
  return _parseCnNumberText(raw);
}

function _isSpecialSeasonFolderName(name) {
  const s = String(name || '').trim();
  if (!s) return false;
  if (/^(specials?|extras?|bonuses?|bonus|ova|oad|sp|featurettes?|interviews?)$/i.test(s)) return true;
  if (/^behind[\s._-]*the[\s._-]*scenes$/i.test(s)) return true;
  if (/^deleted[\s._-]*scenes$/i.test(s)) return true;
  if (/^(花絮|特典|番外|幕后|删减|未播|先导|彩蛋)$/.test(s)) return true;
  return false;
}

function _stripSeasonPattern(name) {
  const s = String(name || '').trim();
  if (!s) return '';

  let result = s;

  // 去除 "Season XX", "Season_XX", "Season-XX", "Season.XX" 等
  result = result.replace(/\bseason[.\-_]?\s*\d{1,4}\b/gi, '');
  // 去除 "SXX", "S_XX", "S-XX", "S XX" 等
  result = result.replace(/\bs[.\-_]?\s*\d{1,4}\b/gi, '');
  // 去除其他语言季号："Saison 1", "Staffel 1", "Temporada 1", "Series 1"
  result = result.replace(/\b(?:saison|staffel|temporada|series)\s*[.\-_]?\s*\d{1,4}\b/gi, '');
  // 去除 "第X季"（阿拉伯数字）
  result = result.replace(/第\s*\d{1,4}\s*季/g, '');
  // 去除 "第X季"（中文数字）
  result = result.replace(new RegExp(`第\\s*${_CN_NUM_CHAR_RE.source}\\s*季`, 'g'), '');
  // 去除 "季 X"（阿拉伯数字）
  result = result.replace(/季\s*\d{1,4}(?:$|\s|[._\-[\]()])/g, '');
  // 去除 "季 X"（中文数字）
  result = result.replace(new RegExp(`季\\s*${_CN_NUM_CHAR_RE.source}(?:$|\\s|[._\\-[\\]()])`, 'g'), '');
  // 去除尾部 "X 季"（阿拉伯数字结尾）
  result = result.replace(/(?:^|[^\d])(\d{1,4})\s*季(?:$|\s|[._\-[\]()])/g, '');

  // 清理末尾的分隔符和多余空格
  result = result.replace(/[.\-_]+$/, '').trim();
  result = result.replace(/\s+/g, ' ').trim();

  return result;
}

function _normalizeSimpleName(s) {
  return String(s || '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '')
    .replace(/[_-]+/g, '');
}

function _isGenericShowName(name) {
  const s = String(name || '').trim();
  if (!s) return true;
  const norm = _normalizeSimpleName(s);
  // 泛化词汇：过短或无具体含义，做包含匹配容易误命中
  const genericWords = [
    'tv', 'television', 'shows', 'series', 'movies', 'films', 'videos',
    '电视剧', '剧集', '电视', '动漫', '动画', '综艺', '电影', '合集',
    'hd', 'bd', '4k', 'download', 'downloads', 'video',
  ];
  return genericWords.includes(norm);
}

function isSeasonFolderOfShow(seasonName, showName) {
  const sn = String(seasonName || '').trim();
  const swn = String(showName || '').trim();
  if (!sn || !swn) return false;
  if (!isSeasonFolderName(sn)) return false;

  // 特殊季文件夹（Specials、花絮等）始终视为该剧的季文件夹
  if (_isSpecialSeasonFolderName(sn)) return true;

  // 去除季号信息，获取季文件夹名的前缀部分
  const prefix = _stripSeasonPattern(sn);

  // 如果去除季号后为空，说明是纯季号格式（如 S01、Season 1），直接视为季文件夹
  if (!prefix) return true;

  // 剧名为泛化词汇时不做包含检测，避免误命中（如剧名 "tv" 被 "American TV Series" 包含）
  if (_isGenericShowName(swn)) return false;

  // 季文件夹前缀包含剧名，或剧名包含季文件夹前缀
  const normPrefix = _normalizeSimpleName(prefix);
  const normShow = _normalizeSimpleName(swn);

  return normPrefix.includes(normShow) || normShow.includes(normPrefix);
}

function parseSeasonNumberFromName(name) {
  const s = String(name || '').trim();
  if (!s || _isSpecialSeasonFolderName(s)) return 0;

  const m1 = s.match(/^season\s*(\d{1,4})$/i);
  if (m1) return _seasonNumFromMatchText(m1[1]);
  const m2 = s.match(/^s(\d{1,4})$/i);
  if (m2) return _seasonNumFromMatchText(m2[1]);

  // 支持季文件夹名带剧名等前缀，如「权力的游戏 S1」「Game of Thrones Season 1」
  const mSeasonFlex = s.match(/\bseason[.\-_]?\s*(\d{1,4})\b/i);
  if (mSeasonFlex) return _seasonNumFromMatchText(mSeasonFlex[1]);
  const mSFlex = s.match(/\bs[.\-_]?(\d{1,4})\b/i);
  if (mSFlex) return _seasonNumFromMatchText(mSFlex[1]);

  const mIntl = s.match(/\b(?:saison|staffel|temporada|series)\s*[.\-_]?\s*(\d{1,4})\b/i);
  if (mIntl) return _seasonNumFromMatchText(mIntl[1]);

  const m3 = s.match(/第\s*(\d{1,4})\s*季/);
  if (m3) return _seasonNumFromMatchText(m3[1]);
  const m4 = s.match(new RegExp(`第\\s*(${_CN_NUM_CHAR_RE.source})\\s*季`));
  if (m4) return _seasonNumFromMatchText(m4[1]);

  const mJiNum = s.match(/季\s*(\d{1,4})(?:$|\s|[._\-[\]()])/);
  if (mJiNum) return _seasonNumFromMatchText(mJiNum[1]);
  const mJiCn = s.match(new RegExp(`季\\s*(${_CN_NUM_CHAR_RE.source})(?:$|\\s|[._\\-[\\]()])`));
  if (mJiCn) return _seasonNumFromMatchText(mJiCn[1]);
  const mTrailingJi = s.match(/(?:^|[^\d])(\d{1,4})\s*季(?:$|\s|[._\-[\]()])/);
  if (mTrailingJi) return _seasonNumFromMatchText(mTrailingJi[1]);
  const mTrailingJiCn = s.match(new RegExp(`(?:^|[^第])(${_CN_NUM_CHAR_RE.source})\\s*季`));
  if (mTrailingJiCn) return _seasonNumFromMatchText(mTrailingJiCn[1]);

  return 0;
}

function isSeasonFolderName(name) {
  const s = String(name || '').trim();
  if (!s) return false;
  if (_isSpecialSeasonFolderName(s)) return true;
  return parseSeasonNumberFromName(s) > 0;
}

function parseEpisodeFromName(filename) {
  const s = String(filename || '');
  if (!s) return null;

  const base = path.parse(s).name;

  const mSeasonEpCn = s.match(new RegExp(`第\\s*(${_CN_NUM_CHAR_RE.source}|\\d{1,4})\\s*季[\\s\\S]*?第\\s*(${_CN_NUM_CHAR_RE.source}|\\d{1,4})\\s*[集话]`));
  if (mSeasonEpCn) {
    const season = _parseCnNumberText(mSeasonEpCn[1]);
    const episode = _parseCnNumberText(mSeasonEpCn[2]);
    if (season > 0 && episode > 0) return { season, episode };
  }

  const mSxe = s.match(/S(\d{1,4})\s*E(\d{1,4})/i);
  if (mSxe) {
    return { season: Number(mSxe[1]) || 0, episode: Number(mSxe[2]) || 0 };
  }

  const mx = s.match(/\b(\d{1,4})x(\d{1,4})\b/i);
  if (mx) {
    return { season: Number(mx[1]) || 0, episode: Number(mx[2]) || 0 };
  }

  // 支持：aaa-ep1 / aaa_ep01 / aaa.ep001
  const mEp = s.match(/(?:^|[^a-z0-9])ep\s*0*(\d{1,4})(?:$|[^a-z0-9])/i);
  if (mEp) {
    return { season: 0, episode: Number(mEp[1]) || 0 };
  }

  const mEpCn = s.match(/第\s*(\d{1,4})\s*[集话]/);
  if (mEpCn) {
    return { season: 0, episode: Number(mEpCn[1]) || 0 };
  }

  const mEpCnText = s.match(new RegExp(`第\\s*(${_CN_NUM_CHAR_RE.source})\\s*[集话]`));
  if (mEpCnText) {
    const episode = _parseCnNumberText(mEpCnText[1]);
    if (episode > 0) return { season: 0, episode };
  }

  const mE = s.match(/\bE(\d{1,4})\b/i);
  if (mE) {
    return { season: 0, episode: Number(mE[1]) || 0 };
  }

  // 支持：s1/2.mp4
  if (/^\d{1,4}$/.test(base)) {
    return { season: 0, episode: Number(base) || 0 };
  }

  // 支持：aaa/aaa1.mp4（剧名 + 数字）；避免把纯数字当作这一类
  const mTrailing = base.match(/(\d{1,4})$/);
  if (mTrailing && !/^\d{1,4}$/.test(base)) {
    const ep = Number(mTrailing[1]) || 0;
    if (ep > 0) return { season: 0, episode: ep };
  }

  // 支持：01 凡人修仙传.mp4（数字 + 剧名）；避免把纯数字当作这一类
  const mLeading = base.match(/^0*(\d{1,4})/);
  if (mLeading && !/^\d{1,4}$/.test(base)) {
    const ep = Number(mLeading[1]) || 0;
    if (ep > 0) return { season: 0, episode: ep };
  }
  return null;
}

function normalizeNameForNfoGuess(name) {
  const s = String(name || '').trim();
  if (!s) return '';
  return s
    .replace(/\.[^.]+$/, '')
    .replace(/S(\d{1,4})\s*E(\d{1,4})/gi, '')
    .replace(/\b(\d{1,4})x(\d{1,4})\b/gi, '')
    .replace(/第\s*\d{1,4}\s*[集话]/g, '')
    .replace(new RegExp(`第\\s*${_CN_NUM_CHAR_RE.source}\\s*[集话]`, 'g'), '')
    .replace(/第\s*\d{1,4}\s*季/g, '')
    .replace(new RegExp(`第\\s*${_CN_NUM_CHAR_RE.source}\\s*季`, 'g'), '')
    .replace(/\(\s*\d{4}\s*\)/g, '')
    .replace(/\b(19|20)\d{2}\b/g, '')
    .replace(/[._]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function _isBdmvFolderName(name) {
  return String(name || '').trim().toLowerCase() === 'bdmv';
}

function _isVideoTsFolderName(name) {
  return String(name || '').trim().toLowerCase() === 'video_ts';
}

function _isBdromFolderName(name) {
  const normalized = String(name || '').trim().toLowerCase();
  return normalized === 'bdrom' || normalized === 'bd_rom' || normalized === 'bd-rom';
}

function isBdmvFolderPath(fullPath) {
  const resolved = fullPath ? path.resolve(String(fullPath)) : '';
  if (!resolved) return false;
  return _isBdmvFolderName(path.basename(resolved));
}

function isVideoTsFolderPath(fullPath) {
  const resolved = fullPath ? path.resolve(String(fullPath)) : '';
  if (!resolved) return false;
  return _isVideoTsFolderName(path.basename(resolved));
}

function _hasCaseInsensitiveFileInDir(targetDir, expectedName) {
  try {
    const expected = String(expectedName || '').trim().toLowerCase();
    if (!expected) return false;
    const entries = fs.readdirSync(targetDir, { withFileTypes: true });
    return entries.some(ent => ent && ent.isFile && ent.isFile() && String(ent.name || '').trim().toLowerCase() === expected);
  } catch (_) {
    return false;
  }
}

function _hasPlayableFilesInBdmvStreamDir(targetDir) {
  try {
    const streamDir = path.join(targetDir, 'STREAM');
    const entries = fs.readdirSync(streamDir, { withFileTypes: true });
    return entries.some(ent => {
      if (!ent || !ent.isFile || !ent.isFile()) return false;
      const name = String(ent.name || '').trim().toLowerCase();
      return name.endsWith('.m2ts') || name.endsWith('.mts') || name.endsWith('.ssif');
    });
  } catch (_) {
    return false;
  }
}

function _hasDiscMarkerFiles(targetDir) {
  try {
    if (_hasCaseInsensitiveFileInDir(targetDir, 'index.bdmv') && _hasCaseInsensitiveFileInDir(targetDir, 'movieobject.bdmv')) {
      return true;
    }
    return _hasPlayableFilesInBdmvStreamDir(targetDir);
  } catch (_) {
    return false;
  }
}

function _hasVideoTsMarkerFiles(targetDir) {
  try {
    if (_hasCaseInsensitiveFileInDir(targetDir, 'video_ts.ifo')) return true;
    const entries = fs.readdirSync(targetDir, { withFileTypes: true });
    return entries.some(ent => {
      if (!ent || !ent.isFile || !ent.isFile()) return false;
      const name = String(ent.name || '').trim().toLowerCase();
      if (name === 'video_ts.vob') return false;
      return /^vts_\d{2}_\d+\.vob$/i.test(name);
    });
  } catch (_) {
    return false;
  }
}

function _buildBdmvMovieEntryFromBdmvPath(bdmvPath) {
  const resolvedBdmv = bdmvPath ? path.resolve(String(bdmvPath)) : '';
  if (!resolvedBdmv || !_hasDiscMarkerFiles(resolvedBdmv)) return null;

  const parentDir = path.dirname(resolvedBdmv);
  const parentName = path.basename(parentDir);
  if (_isBdromFolderName(parentName)) {
    const movieFolder = path.dirname(parentDir);
    const filename = path.basename(movieFolder);
    const dirPath = path.dirname(movieFolder);
    if (!movieFolder || !filename || !dirPath) return null;
    return {
      folderPath: movieFolder,
      dirPath,
      filename,
      bdmvPath: resolvedBdmv,
      discRootPath: parentDir,
    };
  }

  const movieFolder = parentDir;
  const filename = path.basename(movieFolder);
  const dirPath = path.dirname(movieFolder);
  if (!movieFolder || !filename || !dirPath) return null;
  return {
    folderPath: movieFolder,
    dirPath,
    filename,
    bdmvPath: resolvedBdmv,
    discRootPath: movieFolder,
    mediaType: 'bdmv',
  };
}

function _buildVideoTsMovieEntryFromVideoTsPath(videoTsPath) {
  const resolvedVideoTs = videoTsPath ? path.resolve(String(videoTsPath)) : '';
  if (!resolvedVideoTs || !_hasVideoTsMarkerFiles(resolvedVideoTs)) return null;
  const movieFolder = path.dirname(resolvedVideoTs);
  const filename = path.basename(movieFolder);
  const dirPath = path.dirname(movieFolder);
  if (!movieFolder || !filename || !dirPath) return null;
  return {
    folderPath: movieFolder,
    dirPath,
    filename,
    videoTsPath: resolvedVideoTs,
    discRootPath: movieFolder,
    mediaType: 'video_ts',
  };
}

function detectBdmvMovieFolder(currentDir, dirEntries) {
  const resolved = currentDir ? path.resolve(String(currentDir)) : '';
  if (!resolved) return null;
  const entries = Array.isArray(dirEntries) ? dirEntries : [];

  if (isBdmvFolderPath(resolved) && _hasDiscMarkerFiles(resolved)) {
    return _buildBdmvMovieEntryFromBdmvPath(resolved);
  }

  const bdmvEntry = entries.find(ent => ent && ent.isDirectory && ent.isDirectory() && _isBdmvFolderName(ent.name));
  if (bdmvEntry) {
    const directHit = _buildBdmvMovieEntryFromBdmvPath(path.join(resolved, bdmvEntry.name));
    if (directHit) return directHit;
  }

  const bdromEntry = entries.find(ent => ent && ent.isDirectory && ent.isDirectory() && _isBdromFolderName(ent.name));
  if (!bdromEntry) return null;
  const nestedHit = _buildBdmvMovieEntryFromBdmvPath(path.join(resolved, bdromEntry.name, 'BDMV'));
  return nestedHit || null;
}

function detectVideoTsMovieFolder(currentDir, dirEntries) {
  const resolved = currentDir ? path.resolve(String(currentDir)) : '';
  if (!resolved) return null;
  const entries = Array.isArray(dirEntries) ? dirEntries : [];

  if (isVideoTsFolderPath(resolved) && _hasVideoTsMarkerFiles(resolved)) {
    return _buildVideoTsMovieEntryFromVideoTsPath(resolved);
  }

  const videoTsEntry = entries.find(ent => ent && ent.isDirectory && ent.isDirectory() && _isVideoTsFolderName(ent.name));
  if (!videoTsEntry) return null;
  return _buildVideoTsMovieEntryFromVideoTsPath(path.join(resolved, videoTsEntry.name));
}

function detectBdmvMovieFolderFromPath(targetPath) {
  let cursor = targetPath ? path.resolve(String(targetPath)) : '';
  if (!cursor) return null;

  try {
    const st = fs.statSync(cursor);
    if (st.isFile()) cursor = path.dirname(cursor);
  } catch (_) {
    cursor = path.dirname(cursor);
  }

  while (cursor) {
    if (_isBdmvFolderName(path.basename(cursor))) {
      const found = _buildBdmvMovieEntryFromBdmvPath(cursor);
      if (found) return found;
    }
    const next = path.dirname(cursor);
    if (!next || next === cursor) break;
    cursor = next;
  }
  return null;
}

function detectVideoTsMovieFolderFromPath(targetPath) {
  let cursor = targetPath ? path.resolve(String(targetPath)) : '';
  if (!cursor) return null;

  try {
    const st = fs.statSync(cursor);
    if (st.isFile()) cursor = path.dirname(cursor);
  } catch (_) {
    cursor = path.dirname(cursor);
  }

  while (cursor) {
    if (_isVideoTsFolderName(path.basename(cursor))) {
      const found = _buildVideoTsMovieEntryFromVideoTsPath(cursor);
      if (found) return found;
    }
    const next = path.dirname(cursor);
    if (!next || next === cursor) break;
    cursor = next;
  }
  return null;
}

async function walkVideoEntries(rootPath, { onDirectory, onVideoFile, onDiscFolder, onBdmvFolder }) {
  const cachePath = typeof config.getCachePath === 'function' ? config.getCachePath() : '';
  const cachePrefix = cachePath && cachePath.endsWith(path.sep) ? cachePath : cachePath ? `${cachePath}${path.sep}` : '';

  const resolvedRoot = rootPath ? path.resolve(rootPath) : '';
  if (cachePath && (resolvedRoot === cachePath || resolvedRoot.startsWith(cachePrefix))) {
    return true;
  }

  const stack = [rootPath];
  const seenDiscFolders = new Set();
  while (stack.length > 0) {
    const current = stack.pop();
    const resolvedCurrent = current ? path.resolve(current) : '';
    if (cachePath && (resolvedCurrent === cachePath || resolvedCurrent.startsWith(cachePrefix))) {
      continue;
    }
    let fileNameList;
    try {
      fileNameList = await fs.promises.readdir(current, { withFileTypes: true });
    } catch {
      continue;
    }
    const discFolder = detectBdmvMovieFolder(current, fileNameList) || detectVideoTsMovieFolder(current, fileNameList);
    if (discFolder) {
      const onFolder = typeof onDiscFolder === 'function' ? onDiscFolder : onBdmvFolder;
      if (typeof onFolder === 'function') {
        const res = await onFolder(discFolder);
        if (res === false) return false;
      }
      continue;
    }
    for (const name of fileNameList) {
      const entryName = name && typeof name === 'object' ? name.name : name;
      if (FileUtil.isSystemFile(entryName)) continue;
      const fullPath = path.join(current, entryName);
      const resolvedFull = path.resolve(fullPath);
      if (cachePath && (resolvedFull === cachePath || resolvedFull.startsWith(cachePrefix))) {
        continue;
      }
      let entState;
      try {
        entState = name && typeof name.isDirectory === 'function' ? name : fs.statSync(fullPath);
      } catch {
        continue;
      }

      if (entState.isDirectory()) {
        if (typeof onDirectory === 'function') {
          const res = await onDirectory({ fullPath, dirPath: current, filename: entryName });
          if (res === false) return false;
        }
        stack.push(fullPath);
        continue;
      }

      if (!entState.isFile()) continue;
      if (FileUtil.isHideFile(entryName)) continue;
      if (FileUtil.isTemporaryOrDownloadingFile(entryName)) continue;
      const ext = path.extname(entryName).toLowerCase();
      if (!isVideoFileExt(ext)) continue;
      const discFromFile = detectBdmvMovieFolderFromPath(fullPath) || detectVideoTsMovieFolderFromPath(fullPath);
      if (discFromFile && discFromFile.folderPath) {
        const folderKey = path.resolve(String(discFromFile.folderPath));
        Logger.info('Disc walk file rerouted to folder', {
          filePath: fullPath,
          folderPath: folderKey,
        });
        if (!seenDiscFolders.has(folderKey)) {
          seenDiscFolders.add(folderKey);
          const onFolder = typeof onDiscFolder === 'function' ? onDiscFolder : onBdmvFolder;
          if (typeof onFolder === 'function') {
            const res = await onFolder(discFromFile);
            if (res === false) return false;
          }
        }
        continue;
      }
      if (typeof onVideoFile === 'function') {
        const res = await onVideoFile({ fullPath, dirPath: current, filename: entryName, ext });
        if (res === false) return false;
      }
    }
  }

  return true;
}

module.exports = {
  isVideoFileExt,
  getFirstLetter,
  isSeasonFolderName,
  parseSeasonNumberFromName,
  parseEpisodeFromName,
  normalizeNameForNfoGuess,
  stripSeasonPatternFromName: _stripSeasonPattern,
  isSpecialSeasonFolderName: _isSpecialSeasonFolderName,
  isSeasonFolderOfShow,
  isBdmvFolderPath,
  isVideoTsFolderPath,
  detectBdmvMovieFolder,
  detectBdmvMovieFolderFromPath,
  detectVideoTsMovieFolder,
  detectVideoTsMovieFolderFromPath,
  walkVideoEntries,
};
