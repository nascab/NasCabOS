const fs = require('fs');
const path = require('path');
const ResponseUtil = require('../../../apiUtils/responseUtil');
const tableConfig = require('../../../../db/table/tableConfig');
const dbUtil = require('../../../../db/dbUtil');
const knexUtil = require('../../../../db/knexUtil');
const nascabAccountUtil = require('../../service/utils/nascabAccountUtil');
const { TmdbClient } = require('../../../../workers/videoIndex/nfoFetchWorker/tmdbClient');
const config = require('../../../../config/config');
const {
  buildAvailableHwAccelList,
  combineHwAccelEntryToConfig,
  findAvailableHwAccelEntry,
  getHwAccelGroupMeta,
  normalizeAvailableHwAccelList,
  pickEffectiveHwAccelConfig,
} = require('../../../../utils/transcodeHwAccelUtil');
function _parseBoolTo01(v) {
  return v === 1 || v === '1' || v === true ? 1 : 0;
}

function _parseText(v) {
  const s = v === undefined || v === null ? '' : String(v).trim();
  return s;
}

function _safeJsonParse(raw) {
  if (!raw) return null;
  const v = String(raw).trim();
  if (!v) return null;
  try {
    return JSON.parse(v);
  } catch (_) {
    return null;
  }
}

async function _repairTranscodeHwAccelConfigIfNeeded() {
  const [reportRaw, availableRaw, selectedRaw, preferredRaw] = await Promise.all([
    tableConfig.getConfigByKey('transcode_hwaccel_report'),
    tableConfig.getConfigByKey('transcode_hwaccel_available'),
    tableConfig.getConfigByKey('transcode_hwaccel_selected'),
    tableConfig.getConfigByKey('transcode_hwaccel_preferred'),
  ]);

  const report = _safeJsonParse(reportRaw);
  const candidates = report && Array.isArray(report.candidates) ? report.candidates : [];
  if (candidates.length === 0) return;

  const existingAvailable = normalizeAvailableHwAccelList(availableRaw);
  const derivedAvailable =
    existingAvailable.length > 0
      ? existingAvailable
      : normalizeAvailableHwAccelList(report && report.available ? report.available : null);
  const available = derivedAvailable.length > 0 ? derivedAvailable : buildAvailableHwAccelList(candidates);

  const savePairs = [];
  if (existingAvailable.length === 0 && available.length > 0) {
    savePairs.push(tableConfig.setConfigByKey('transcode_hwaccel_available', JSON.stringify(available)));
  }

  const preferredKey = preferredRaw ? String(preferredRaw).trim() : '';
  const preferredExists = preferredKey ? !!findAvailableHwAccelEntry(available, preferredKey) : false;
  const nextPreferredKey = preferredExists ? preferredKey : '';
  if (nextPreferredKey !== preferredKey) {
    savePairs.push(tableConfig.setConfigByKey('transcode_hwaccel_preferred', nextPreferredKey));
  }

  const selectedParsed = _safeJsonParse(selectedRaw);
  const selectedHasKey =
    selectedParsed && typeof selectedParsed === 'object' && typeof selectedParsed.key === 'string' && selectedParsed.key.trim();
  if (!selectedHasKey) {
    const reportSelected = report && report.selected && typeof report.selected === 'object' ? report.selected : null;
    const profiles = reportSelected && reportSelected.profiles && typeof reportSelected.profiles === 'object' ? reportSelected.profiles : null;
    const baseProfile =
      (profiles && profiles.h264 && typeof profiles.h264 === 'object' ? profiles.h264 : null) ||
      (profiles && profiles.h265 && typeof profiles.h265 === 'object' ? profiles.h265 : null) ||
      reportSelected;
    if (baseProfile) {
      const groupMeta = getHwAccelGroupMeta(baseProfile);
      const entryKey = groupMeta && groupMeta.key ? String(groupMeta.key) : '';
      const entry = entryKey ? findAvailableHwAccelEntry(available, entryKey) : null;
      const nextSelected = entry ? combineHwAccelEntryToConfig(entry) : null;
      if (nextSelected) {
        if (profiles) {
          nextSelected.profiles = {
            h264: profiles.h264 && typeof profiles.h264 === 'object' ? profiles.h264 : null,
            h265: profiles.h265 && typeof profiles.h265 === 'object' ? profiles.h265 : null,
          };
        }
        savePairs.push(tableConfig.setConfigByKey('transcode_hwaccel_selected', JSON.stringify(nextSelected)));
      }
    }
  }

  if (savePairs.length > 0) {
    await Promise.all(savePairs);
  }
}

async function _testWritableDir(dirPath) {
  const raw = String(dirPath || '').trim();
  if (!raw) return { ok: true, resolved: '' };
  const resolved = path.resolve(raw);
  const safeFolderName = config.getTranscodeTempSafeFolderName();
  let st;
  try {
    st = await fs.promises.stat(resolved);
  } catch (_) {
    return { ok: false, code: 'video.TRANSCODE_TEMP_DIR_NOT_EXIST' };
  }
  if (!st || !st.isDirectory()) {
    return { ok: false, code: 'video.TRANSCODE_TEMP_DIR_NOT_DIR' };
  }
  try {
    await fs.promises.access(resolved, fs.constants.W_OK);
  } catch (_) {
    return { ok: false, code: 'video.TRANSCODE_TEMP_DIR_NOT_WRITABLE' };
  }

  const safeDir = path.join(resolved, safeFolderName);
  try {
    await fs.promises.mkdir(safeDir, { recursive: true });
    await fs.promises.access(safeDir, fs.constants.W_OK);
  } catch (_) {
    return { ok: false, code: 'video.TRANSCODE_TEMP_DIR_NOT_WRITABLE' };
  }

  const name = `.nascabos_write_test_${Date.now()}_${Math.random().toString(16).slice(2)}.tmp`;
  const p = path.join(safeDir, name);
  try {
    await fs.promises.writeFile(p, 'ok', 'utf8');
    await fs.promises.unlink(p);
  } catch (_) {
    try {
      await fs.promises.unlink(p);
    } catch (_) {}
    return { ok: false, code: 'video.TRANSCODE_TEMP_DIR_NOT_WRITABLE' };
  }
  return { ok: true, resolved };
}

function _normalizeProxyUrlString(proxyUrlStr) {
  const raw = String(proxyUrlStr || '').trim();
  if (!raw) return '';
  if (raw.includes('://')) return raw;
  return `http://${raw}`;
}

function _parseHttpProxyUrlOrEmpty(proxyUrlStr) {
  const normalized = _normalizeProxyUrlString(proxyUrlStr);
  if (!normalized) return '';
  let u;
  try {
    u = new URL(normalized);
  } catch (_) {
    return '';
  }
  const isHttpsProxy = u.protocol === 'https:';
  const isHttpProxy = u.protocol === 'http:';
  if (!isHttpsProxy && !isHttpProxy) return '';
  if (!u.hostname) return '';
  const port = Number(u.port || (isHttpsProxy ? 443 : 80)) || (isHttpsProxy ? 443 : 80);
  if (!port) return '';
  return normalized;
}

function _normalizeToTmdbLanguage(locale) {
  const raw = String(locale || '').trim();
  if (!raw || raw === 'system') return '';
  const primary = raw.split(/[-_]/)[0].toLowerCase();
  const map = {
    zh: 'zh-CN',
    en: 'en-US',
    es: 'es-ES',
    fr: 'fr-FR',
    de: 'de-DE',
    ja: 'ja-JP',
    pt: 'pt-BR',
    ru: 'ru-RU',
    ar: 'ar-SA',
    ko: 'ko-KR',
    th: 'th-TH',
    vi: 'vi-VN',
    id: 'id-ID',
  };
  if (map[primary]) return map[primary];
  if (/^[a-z]{2}-[A-Z]{2}$/.test(raw)) return raw;
  return '';
}

function _normalizeApiUrlString(apiUrlStr) {
  const raw = String(apiUrlStr || '').trim();
  if (!raw) return '';
  if (raw.includes('://')) return raw;
  return `https://${raw}`;
}

async function _resolveTmdbApiUrl() {
  const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
  const fromDb = await nascabAccountUtil.getDecryptedConfigValue(knex, tableConfig, 'tmdbApiUrl');
  const apiUrl = fromDb ? _normalizeApiUrlString(fromDb) : '';
  if (apiUrl) return apiUrl;
  const defaults = config.getDefaultTmdbConfig();
  return defaults.tmdbApiUrl ? String(defaults.tmdbApiUrl).trim() : '';
}

async function _resolveTmdbToken(overrideToken = '') {
  const t = String(overrideToken || '').trim();
  if (t) return t;
  const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
  const [fromUserToken, fromDefaultToken] = await Promise.all([
    nascabAccountUtil.getDecryptedConfigValue(knex, tableConfig, 'tmdbApiToken'),
    nascabAccountUtil.getDecryptedConfigValue(knex, tableConfig, 'tmdbApiTokenDefault'),
  ]);
  const userToken = fromUserToken ? String(fromUserToken).trim() : '';
  if (userToken) return userToken;
  const defaultToken = fromDefaultToken ? String(fromDefaultToken).trim() : '';
  if (defaultToken) return defaultToken;
  const defaults = config.getDefaultTmdbConfig();
  return defaults.tmdbApiToken ? String(defaults.tmdbApiToken).trim() : '';
}

async function _testTmdbConnection({ accessToken, proxyUrl }) {
  const apiUrl = await _resolveTmdbApiUrl();
  const apiToken = await _resolveTmdbToken(accessToken);
  console.log('[TMDB proxy test] apiUrl=', apiUrl ? `${apiUrl.slice(0, 50)}...` : '(empty)', 'proxyUrl=', proxyUrl ? `${proxyUrl.slice(0, 60)}...` : '(none)', 'hasToken=', !!apiToken);
  if (!apiToken) return false;
  const client = new TmdbClient({ apiUrl, apiToken, proxyUrl });
  try {
    await client.requestJson('/3/configuration/languages', null);
    return { ok: true, reason: '' };
  } catch (e) {
    console.log('[TMDB proxy test] request failed:', e && e.code, e && e.message);
    let reason = '';
    const statusCode = e && e.statusCode ? Number(e.statusCode) : 0;
    if (statusCode) {
      try {
        const json = e && e.body ? JSON.parse(String(e.body || '')) : null;
        const msg = json && json.status_message ? String(json.status_message) : '';
        reason = msg ? `HTTP ${statusCode} ${msg}` : `HTTP ${statusCode}`;
      } catch (_) {
        reason = `HTTP ${statusCode}`;
      }
    } else if (e && e.code) {
      reason = String(e.code);
      if (e.message) reason += ` ${String(e.message)}`;
    } else if (e && e.message) {
      reason = String(e.message);
    }
    reason = reason.trim();
    if (reason.length > 200) reason = reason.slice(0, 200);
    return { ok: false, reason };
  }
}

async function _loadTranscodeHwAccelState() {
  await _repairTranscodeHwAccelConfigIfNeeded();
  const [availableRaw, preferredRaw, selectedRaw] = await Promise.all([
    tableConfig.getConfigByKey('transcode_hwaccel_available'),
    tableConfig.getConfigByKey('transcode_hwaccel_preferred'),
    tableConfig.getConfigByKey('transcode_hwaccel_selected'),
  ]);
  const available = normalizeAvailableHwAccelList(availableRaw);
  const preferredKey = preferredRaw ? String(preferredRaw).trim() : '';
  const effective = pickEffectiveHwAccelConfig({
    availableList: available,
    preferredKey,
    autoSelected: selectedRaw ? _safeJsonParse(selectedRaw) : null,
  });
  return {
    available,
    preferredKey: findAvailableHwAccelEntry(available, preferredKey) ? preferredKey : '',
    effective,
  };
}

class VideoConfigController {
  async getTmdbConfig(req, res) {
    try {
      const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
      // 远程默认 token（加密存储）不应返回给前端展示/回填
      // 兼容旧版本：若 token 曾被远程加密写入到 tmdbApiToken，也一并隐藏
      const [tokenRaw, tokenDec, proxyEnable, proxyUrl, language] = await Promise.all([
        tableConfig.getConfigByKey('tmdbApiToken'),
        nascabAccountUtil.getDecryptedConfigValue(knex, tableConfig, 'tmdbApiToken'),
        tableConfig.getConfigByKey('tmdbProxyEnable'),
        tableConfig.getConfigByKey('tmdbProxyUrl'),
        tableConfig.getConfigByKey('tmdbLanguage'),
      ]);
      const isEncryptedToken = tokenRaw ? String(tokenRaw).trim().startsWith('enc.') : false;
      const token = isEncryptedToken ? '' : tokenDec ? String(tokenDec) : '';

      return ResponseUtil.success(
        req,
        res,
        {
          accessToken: token ? String(token) : '',
          proxyEnable: proxyEnable === '1' || proxyEnable === 1 ? 1 : 0,
          proxyUrl: proxyUrl ? String(proxyUrl) : '',
          language: language ? String(language) : '',
        },
        'common.SUCCESS',
        200
      );
    } catch (_) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async getTranscodeConfig(req, res) {
    try {
      const [tempDir, hwState] = await Promise.all([tableConfig.getConfigByKey('transcodeTempDir'), _loadTranscodeHwAccelState()]);
      return ResponseUtil.success(
        req,
        res,
        {
          tempDir: tempDir ? String(tempDir) : '',
          preferredHwDecoder: hwState.preferredKey,
          availableHwDecoders: hwState.available.map(item => ({
            key: item.key,
            label: item.label,
            kind: item.kind,
            codecs: item.codecs,
          })),
          effectiveHwDecoder: hwState.effective
            ? {
                key: hwState.effective.key || '',
                label: hwState.effective.displayName || hwState.effective.name || hwState.effective.encoder || '',
              }
            : null,
        },
        'common.SUCCESS',
        200
      );
    } catch (_) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async setTmdbConfig(req, res) {
    try {
      const body = req.body || {};
      const accessToken = _parseText(body.accessToken ?? body.tmdbAccessToken ?? body.tmdb_access_token);
      const proxyEnable = _parseBoolTo01(body.proxyEnable ?? body.enableProxy ?? body.proxy_enable);
      const proxyUrlRaw = _parseText(body.proxyUrl ?? body.tmdbProxyUrl ?? body.proxy_url);
      const languageRaw = _parseText(body.language ?? body.tmdbLanguage ?? body.tmdb_language);
      const language = _normalizeToTmdbLanguage(languageRaw);

      if (languageRaw && !language) {
        return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);
      }

      const proxyUrl = proxyEnable === 1 ? _parseHttpProxyUrlOrEmpty(proxyUrlRaw) : '';
      if (proxyEnable === 1) {
        console.log('[setTmdbConfig] proxyEnable=1 proxyUrlRaw=', proxyUrlRaw, 'parsed proxyUrl=', proxyUrl || '(empty)');
      }
      if (proxyEnable === 1 && !proxyUrl) {
        return ResponseUtil.error(req, res, 'video.TMDB_PROXY_REQUIRED', 400);
      }
      if (proxyEnable === 1 && proxyUrlRaw && !proxyUrl) {
        return ResponseUtil.error(req, res, 'video.TMDB_PROXY_INVALID', 400);
      }

      if (proxyEnable === 1) {
        const test = await _testTmdbConnection({ accessToken, proxyUrl });
        if (!test || !test.ok) {
          const reason = test && test.reason ? String(test.reason) : '';
          if (reason) {
            return ResponseUtil.errorWithArgs(req, res, 'video.TMDB_PROXY_TEST_FAILED_DETAIL', [reason], 400);
          }
          return ResponseUtil.error(req, res, 'video.TMDB_PROXY_TEST_FAILED', 400);
        }
      }

      const savePairs = [
        tableConfig.setConfigByKey('tmdbApiToken', accessToken),
        tableConfig.setConfigByKey('tmdbProxyEnable', String(proxyEnable)),
        tableConfig.setConfigByKey('tmdbProxyUrl', proxyEnable === 1 ? proxyUrl : ''),
        tableConfig.setConfigByKey('tmdbLanguage', language),
      ];
      const results = await Promise.all(savePairs);
      const allOk = results.every(Boolean);
      if (!allOk) return ResponseUtil.error(req, res, 'common.ERROR', 500);

      return ResponseUtil.success(req, res, { accessToken, proxyEnable, proxyUrl: proxyEnable === 1 ? proxyUrl : '', language }, 'video.TMDB_CONFIG_SAVED', 200);
    } catch (_) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async getSubtitleConfig(req, res) {
    try {
      const raw = await tableConfig.getConfigByKey('subtitlePreExtractEnable');
      let preExtractEnable = 1;
      if (raw !== null && raw !== undefined && String(raw).trim() !== '') {
        preExtractEnable = _parseBoolTo01(raw);
      }
      return ResponseUtil.success(
        req,
        res,
        { preExtractEnable },
        'common.SUCCESS',
        200
      );
    } catch (_) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async setSubtitleConfig(req, res) {
    try {
      const body = req.body || {};
      const preExtractEnable = _parseBoolTo01(
        body.preExtractEnable ?? body.subtitlePreExtractEnable ?? body.subtitle_pre_extract_enable
      );
      const ok = await tableConfig.setConfigByKey('subtitlePreExtractEnable', String(preExtractEnable));
      if (!ok) return ResponseUtil.error(req, res, 'common.ERROR', 500);
      return ResponseUtil.success(req, res, { preExtractEnable }, 'video.SUBTITLE_CONFIG_SAVED', 200);
    } catch (_) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async setTranscodeConfig(req, res) {
    try {
      const body = req.body || {};
      const tempDirRaw = _parseText(body.tempDir ?? body.transcodeTempDir ?? body.transcode_temp_dir);
      const hasPreferredField =
        Object.prototype.hasOwnProperty.call(body, 'preferredHwDecoder') ||
        Object.prototype.hasOwnProperty.call(body, 'transcodeHwDecoder') ||
        Object.prototype.hasOwnProperty.call(body, 'preferred_hw_decoder');
      const preferredHwDecoder = hasPreferredField ? _parseText(body.preferredHwDecoder ?? body.transcodeHwDecoder ?? body.preferred_hw_decoder) : null;
      const test = await _testWritableDir(tempDirRaw);
      if (!test.ok) {
        return ResponseUtil.error(req, res, test.code || 'common.PARAM_ERROR', 400);
      }
      const tempDir = test.resolved || '';
      let nextPreferredKey = null;
      if (hasPreferredField) {
        const available = normalizeAvailableHwAccelList(await tableConfig.getConfigByKey('transcode_hwaccel_available'));
        if (preferredHwDecoder && !findAvailableHwAccelEntry(available, preferredHwDecoder)) {
          return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);
        }
        nextPreferredKey = preferredHwDecoder || '';
      }

      const savePairs = [tableConfig.setConfigByKey('transcodeTempDir', tempDir)];
      if (hasPreferredField) {
        savePairs.push(tableConfig.setConfigByKey('transcode_hwaccel_preferred', nextPreferredKey));
      }
      const results = await Promise.all(savePairs);
      if (!results.every(Boolean)) return ResponseUtil.error(req, res, 'common.ERROR', 500);

      return ResponseUtil.success(
        req,
        res,
        { tempDir, preferredHwDecoder: hasPreferredField ? nextPreferredKey : undefined },
        'video.TRANSCODE_CONFIG_SAVED',
        200
      );
    } catch (_) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }
}

module.exports = new VideoConfigController();
