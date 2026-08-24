'use strict';

function normalizeHwAccelProfile(parsed) {
  if (!parsed || typeof parsed !== 'object') return null;
  const name = parsed.name ? String(parsed.name) : null;
  const encoder = parsed.encoder ? String(parsed.encoder) : null;
  const kind = parsed.kind ? String(parsed.kind) : null;
  const hwType = parsed.hwType ? String(parsed.hwType) : null;
  const device = parsed.device ? String(parsed.device) : null;
  const hwUploadFilter = parsed.hwUploadFilter ? String(parsed.hwUploadFilter) : null;
  const decodeArgs = Array.isArray(parsed.decodeArgs) ? parsed.decodeArgs.filter(v => typeof v === 'string') : null;
  const inputArgs = Array.isArray(parsed.inputArgs) ? parsed.inputArgs.filter(v => typeof v === 'string') : null;
  const initDeviceArgs = Array.isArray(parsed.initDeviceArgs) ? parsed.initDeviceArgs.filter(v => typeof v === 'string') : null;
  if (!name && !encoder && !hwType) return null;
  return {
    name,
    kind,
    encoder,
    decodeArgs,
    hwType,
    device,
    hwUploadFilter,
    inputArgs,
    initDeviceArgs,
  };
}

function getCodecKeyFromEncoder(encoder) {
  const value = String(encoder || '').toLowerCase();
  if (!value) return '';
  return value.includes('hevc') || value.includes('265') ? 'h265' : 'h264';
}

function getHwAccelGroupMeta(profile) {
  const name = String(profile && profile.name ? profile.name : '').toLowerCase();
  if (name.startsWith('nvidia_')) {
    return { key: 'nvidia', label: 'NVIDIA CUDA / NVENC', kind: 'discrete' };
  }
  if (name.startsWith('amd_')) {
    return { key: 'amd', label: 'AMD AMF', kind: 'discrete' };
  }
  if (name.startsWith('intel_')) {
    return { key: 'intel_qsv', label: 'Intel Quick Sync', kind: 'integrated' };
  }
  if (name.startsWith('videotoolbox_')) {
    return { key: 'videotoolbox', label: 'Apple VideoToolbox', kind: profile && profile.kind ? profile.kind : 'integrated' };
  }
  if (name.startsWith('linux_vaapi_')) {
    const device = profile && profile.device ? String(profile.device) : '';
    return { key: device ? `vaapi:${device}` : 'vaapi', label: device ? `VAAPI (${device})` : 'VAAPI', kind: profile && profile.kind ? profile.kind : 'integrated' };
  }
  if (name.startsWith('linux_qsv_')) {
    const device = profile && profile.device ? String(profile.device) : '';
    return {
      key: device ? `qsv:${device}` : 'qsv',
      label: device ? `Intel Quick Sync (${device})` : 'Intel Quick Sync',
      kind: profile && profile.kind ? profile.kind : 'integrated',
    };
  }
  return {
    key: name || String(profile && profile.encoder ? profile.encoder : 'unknown'),
    label: profile && profile.name ? String(profile.name) : String(profile && profile.encoder ? profile.encoder : 'Unknown'),
    kind: profile && profile.kind ? profile.kind : null,
  };
}

function createAvailableEntry(groupMeta) {
  return {
    key: String(groupMeta.key),
    label: String(groupMeta.label),
    kind: groupMeta.kind ? String(groupMeta.kind) : null,
    device: null,
    profiles: {
      h264: null,
      h265: null,
    },
  };
}

function buildAvailableHwAccelList(attempts) {
  const list = Array.isArray(attempts) ? attempts : [];
  const map = new Map();
  for (const item of list) {
    if (!item || item.ok !== true) continue;
    if (Array.isArray(item.decodeArgs) && item.decodeArgs.length > 0) {
      const okType = item.okType ? String(item.okType).toLowerCase() : '';
      if (okType && okType !== 'file') continue;
    }
    const profile = normalizeHwAccelProfile(item);
    if (!profile || !profile.encoder) continue;
    const groupMeta = getHwAccelGroupMeta(profile);
    const entry = map.get(groupMeta.key) || createAvailableEntry(groupMeta);
    if (!entry.device && profile.device) entry.device = profile.device;
    const codecKey = getCodecKeyFromEncoder(profile.encoder);
    if (!codecKey) continue;
    if (!entry.profiles[codecKey]) {
      entry.profiles[codecKey] = profile;
    }
    map.set(groupMeta.key, entry);
  }
  return Array.from(map.values())
    .filter(entry => entry.profiles.h264 || entry.profiles.h265)
    .map(entry => normalizeAvailableHwAccelEntry(entry))
    .filter(Boolean);
}

function normalizeAvailableHwAccelEntry(entry) {
  if (!entry || typeof entry !== 'object') return null;
  const key = entry.key ? String(entry.key).trim() : '';
  if (!key) return null;
  const label = entry.label ? String(entry.label).trim() : key;
  const kind = entry.kind ? String(entry.kind).trim() : null;
  const device = entry.device ? String(entry.device).trim() : null;
  const h264 = entry && entry.profiles && entry.profiles.h264 ? normalizeHwAccelProfile(entry.profiles.h264) : null;
  const h265 = entry && entry.profiles && entry.profiles.h265 ? normalizeHwAccelProfile(entry.profiles.h265) : null;
  if (!h264 && !h265) return null;
  const codecs = [];
  if (h264) codecs.push('h264');
  if (h265) codecs.push('h265');
  return {
    key,
    label,
    kind,
    device,
    codecs,
    profiles: {
      h264: h264 || null,
      h265: h265 || null,
    },
  };
}

function normalizeAvailableHwAccelList(value) {
  let parsed = value;
  if (typeof parsed === 'string') {
    const raw = parsed.trim();
    if (!raw) return [];
    try {
      parsed = JSON.parse(raw);
    } catch (_) {
      return [];
    }
  }
  if (!Array.isArray(parsed)) return [];
  return parsed.map(item => normalizeAvailableHwAccelEntry(item)).filter(Boolean);
}

function normalizeHwAccelConfig(parsed) {
  if (!parsed || typeof parsed !== 'object') return null;
  const base = normalizeHwAccelProfile(parsed);
  if (!base) return null;
  const result = { ...base };
  if (parsed.key) result.key = String(parsed.key);
  if (parsed.displayName) result.displayName = String(parsed.displayName);
  const profilesRaw = parsed && parsed.profiles && typeof parsed.profiles === 'object' ? parsed.profiles : null;
  if (profilesRaw) {
    const h264 = normalizeHwAccelProfile(profilesRaw.h264);
    const h265 = normalizeHwAccelProfile(profilesRaw.h265);
    if (h264 || h265) {
      result.profiles = { h264: h264 || null, h265: h265 || null };
    }
  }
  return result;
}

function combineHwAccelEntryToConfig(entry) {
  const normalized = normalizeAvailableHwAccelEntry(entry);
  if (!normalized) return null;
  const h264 = normalized.profiles.h264;
  const h265 = normalized.profiles.h265;
  const base = h264 || h265;
  if (!base) return null;
  return {
    key: normalized.key,
    displayName: normalized.label,
    name: base.name,
    kind: normalized.kind || base.kind || null,
    encoder: base.encoder,
    decodeArgs: base.decodeArgs,
    hwType: base.hwType,
    device: normalized.device || base.device || null,
    hwUploadFilter: base.hwUploadFilter,
    inputArgs: base.inputArgs,
    initDeviceArgs: base.initDeviceArgs,
    profiles: {
      h264: h264 || null,
      h265: h265 || null,
    },
  };
}

function findAvailableHwAccelEntry(availableList, preferredKey) {
  const key = String(preferredKey || '').trim();
  if (!key) return null;
  const list = normalizeAvailableHwAccelList(availableList);
  return list.find(item => item.key === key) || null;
}

function pickEffectiveHwAccelConfig({ availableList, preferredKey, autoSelected }) {
  const preferred = findAvailableHwAccelEntry(availableList, preferredKey);
  if (preferred) {
    return combineHwAccelEntryToConfig(preferred);
  }
  return normalizeHwAccelConfig(autoSelected);
}

module.exports = {
  buildAvailableHwAccelList,
  combineHwAccelEntryToConfig,
  findAvailableHwAccelEntry,
  getHwAccelGroupMeta,
  normalizeAvailableHwAccelEntry,
  normalizeAvailableHwAccelList,
  normalizeHwAccelConfig,
  normalizeHwAccelProfile,
  pickEffectiveHwAccelConfig,
};
