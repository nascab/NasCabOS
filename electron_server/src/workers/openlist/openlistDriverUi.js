/** OpenList 驱动字段：前端仅展示用户需填写的凭证类字段 */

const OPENLIST_COMMON_HIDDEN = new Set([
  'mount_path',
  'order',
  'remark',
  'cache_expiration',
  'custom_cache_policies',
  'web_proxy',
  'webdav_policy',
  'down_proxy_url',
  'disable_proxy_sign',
  'extract_folder',
  'disable_index',
  'enable_sign',
  'client_id',
  'client_secret',
  'redirect_uri',
  'api_url_address',
  'use_online_api',
  'region',
  'is_sharepoint',
  'site_id',
  'chunk_size',
]);

/** 使用 OpenList 在线授权页（api.oplist.org）获取 token 的驱动，无需填写 Client ID/Secret */
const OPENLIST_ONLINE_AUTH_DRIVERS = new Set([
  'BaiduNetdisk',
  'AliyundriveOpen',
  'Onedrive',
  '115 Open',
]);

/** S3 对象存储需在界面填写的连接参数（见 OpenList S3 文档） */
const S3_UI_FIELD_NAMES = new Set([
  'bucket',
  'endpoint',
  'region',
  'access_key_id',
  'secret_access_key',
  'session_token',
  'custom_host',
  'force_path_style',
]);

const TOKEN_LIKE_FIELD_NAMES = new Set([
  'refresh_token',
  'access_token',
  'token',
  'cookie',
  'cookies',
  'mail_cookies',
  'qrcode_token',
  'share_code',
  'share_pwd',
  'share_id',
  'share_ids',
  'share_name',
  'sharekey',
  'shareurl',
  'receive_code',
  'captcha_sign',
  'authorization',
  'username',
  'user_name',
  'password',
  'email',
  'phone',
  'access_key',
  'secret_access_key',
  'access_key_id',
  'app_id',
  'app_secret',
  'owner',
  'safe_password',
  'sign_key',
]);

function isOneOfRequiredField(field) {
  const help = String((field && field.help) || '').toLowerCase();
  return help.includes('one of') && help.includes('required');
}

function isUiCredentialField(field, driver) {
  if (!field || !field.name) return false;
  const name = String(field.name);
  if (OPENLIST_COMMON_HIDDEN.has(name)) return false;

  const driverName = String(driver || '').trim();
  if (driverName === 'S3' && S3_UI_FIELD_NAMES.has(name)) {
    return true;
  }
  if (driverName && OPENLIST_ONLINE_AUTH_DRIVERS.has(driverName)) {
    if (TOKEN_LIKE_FIELD_NAMES.has(name) || TOKEN_LIKE_FIELD_NAMES.has(name.toLowerCase())) {
      return true;
    }
    return isOneOfRequiredField(field);
  }

  if (TOKEN_LIKE_FIELD_NAMES.has(name) || TOKEN_LIKE_FIELD_NAMES.has(name.toLowerCase())) {
    return true;
  }
  if (isOneOfRequiredField(field)) return true;
  return false;
}

function filterUiDriverFields(fields, driver) {
  if (!Array.isArray(fields)) return [];
  return fields.filter(f => isUiCredentialField(f, driver));
}

/** 写入 OpenList storage addition 时，为隐藏必填项补默认值（勿放驱动专属排序/UA） */
const ADDITION_FIELD_DEFAULTS = {
  root_folder_path: '/',
  root_folder_id: '0',
};

/** 各驱动隐藏字段预设（与 OpenList 官方默认一致） */
const DRIVER_ADDITION_PRESETS = {
  BaiduNetdisk: {
    custom_crack_ua: 'netdisk',
    order_by: 'name',
    order_direction: 'asc',
    api_url_address: 'https://api.oplist.org/baiduyun/renewapi',
  },
  AliyundriveOpen: {
    root_folder_id: 'root',
    order_by: 'name',
    order_direction: 'ASC',
    api_url_address: 'https://api.oplist.org/alicloud/renewapi',
    remove_way: 'trash',
    alipan_type: 'default',
    // 勿用 default：非达人账号会映射到 backup 盘，根目录等同「备份文件」内部
    drive_type: 'resource',
  },
  Aliyundrive: {
    root_folder_id: 'root',
    order_by: 'name',
    order_direction: 'ASC',
  },
  Onedrive: {
    region: 'global',
    redirect_uri: 'https://api.oplist.org/onedrive/callback',
    api_url_address: 'https://api.oplist.org/onedrive/renewapi',
    is_sharepoint: false,
    chunk_size: 10,
  },
  S3: {
    list_object_version: 'v2',
    sign_url_expire: 4,
  },
};

const ONLINE_API_URL_BY_DRIVER = {
  BaiduNetdisk: 'https://api.oplist.org/baiduyun/renewapi',
  AliyundriveOpen: 'https://api.oplist.org/alicloud/renewapi',
  Onedrive: 'https://api.oplist.org/onedrive/renewapi',
};

/** 去掉协议、路径；虚拟主机域名还原为服务 Endpoint */
function normalizeS3Endpoint(raw) {
  let ep = String(raw || '').trim();
  if (!ep) return '';
  ep = ep.replace(/^https?:\/\//i, '');
  ep = ep.split('/')[0].replace(/\/+$/, '').toLowerCase();

  const cosVh = ep.match(/^(?:[^.]+\.)?(cos\.[a-z0-9-]+\.myqcloud\.com)$/);
  if (cosVh) return cosVh[1];

  const ossVh = ep.match(/^(?:[^.]+\.)?(oss-[a-z0-9-]+\.aliyuncs\.com)$/);
  if (ossVh) return ossVh[1];

  const s3Vh = ep.match(/^(?:[^.]+\.)?(s3\.[a-z0-9-]+\.amazonaws\.com)$/);
  if (s3Vh) return s3Vh[1];

  return ep;
}

/** 从 Endpoint 推断 Region（腾讯云 COS 必填，否则 OpenList 会用 openlist 导致目录为空） */
function inferS3RegionFromEndpoint(endpoint) {
  const ep = normalizeS3Endpoint(endpoint);
  if (!ep) return '';
  const cos = ep.match(/^cos\.([a-z0-9-]+)\.myqcloud\.com$/);
  if (cos) return cos[1];
  const oss = ep.match(/^(oss-[a-z0-9-]+)\.aliyuncs\.com$/);
  if (oss) return oss[1];
  const s3 = ep.match(/^s3\.([a-z0-9-]+)\.amazonaws\.com$/);
  if (s3) return s3[1];
  return '';
}

/** 虚拟主机样式域名中的桶名：mybucket-1250000000.cos.ap-guangzhou.myqcloud.com */
function extractS3BucketFromVirtualHost(raw) {
  const ep = String(raw || '').trim().replace(/^https?:\/\//i, '').split('/')[0].toLowerCase();
  const cos = ep.match(/^([a-z0-9][a-z0-9-]*)\.cos\.[a-z0-9-]+\.myqcloud\.com$/);
  if (cos) return cos[1];
  const oss = ep.match(/^([a-z0-9][a-z0-9-]*)\.oss-[a-z0-9-]+\.aliyuncs\.com$/);
  if (oss) return oss[1];
  return '';
}

function normalizeS3Addition(out) {
  delete out.root_folder_id;

  if (!String(out.root_folder_path || '').trim()) {
    out.root_folder_path = '/';
  }

  const rawEndpoint = out.endpoint;
  out.endpoint = normalizeS3Endpoint(out.endpoint);

  if (!String(out.bucket || '').trim()) {
    const fromHost = extractS3BucketFromVirtualHost(rawEndpoint);
    if (fromHost) out.bucket = fromHost;
  }

  let region = String(out.region || '').trim();
  if (region === 'openlist') region = '';

  if (!region && out.endpoint) {
    region = inferS3RegionFromEndpoint(out.endpoint);
  }

  if (region && (region.includes('myqcloud.com') || region.includes('aliyuncs.com'))) {
    const inferred = inferS3RegionFromEndpoint(region);
    if (inferred) {
      if (!out.endpoint) out.endpoint = normalizeS3Endpoint(region);
      region = inferred;
    }
  }

  if (region) {
    out.region = region;
  } else {
    delete out.region;
  }

  if (!String(out.list_object_version || '').trim()) {
    out.list_object_version = 'v2';
  }
}

function mergeAdditionDefaults(driver, userAddition) {
  const user = userAddition && typeof userAddition === 'object' ? userAddition : {};
  const driverName = String(driver || '').trim();
  const preset = DRIVER_ADDITION_PRESETS[driverName];
  const out = { ...ADDITION_FIELD_DEFAULTS, ...(preset || {}), ...user };
  if (preset) {
    for (const [key, value] of Object.entries(preset)) {
      if (user[key] !== undefined && user[key] !== null && user[key] !== '') continue;
      out[key] = value;
    }
  }
  // 从 api.oplist.org 授权页获取的 refresh_token 默认走 Online API（须同时填 api_url_address）
  if (driverName === 'BaiduNetdisk' || OPENLIST_ONLINE_AUTH_DRIVERS.has(driverName)) {
    const clientId = String(out.client_id || '').trim();
    const clientSecret = String(out.client_secret || '').trim();
    if (!clientId || !clientSecret) {
      out.use_online_api = true;
      const apiUrl = ONLINE_API_URL_BY_DRIVER[driverName];
      if (apiUrl && !String(out.api_url_address || '').trim()) {
        out.api_url_address = apiUrl;
      }
      if (driverName === 'Onedrive' && !String(out.redirect_uri || '').trim()) {
        out.redirect_uri = 'https://api.oplist.org/onedrive/callback';
      }
    }
  }
  if (driverName === 'AliyundriveOpen' && !String(out.root_folder_id || '').trim()) {
    out.root_folder_id = 'root';
  }
  // 阿里云 Open 要求 order_direction 为大写 ASC/DESC，小写 asc 会导致列目录失败、挂载目录为空
  if (driverName === 'AliyundriveOpen' || driverName === 'Aliyundrive') {
    const dir = String(out.order_direction || '').trim();
    if (!dir || dir === 'asc') out.order_direction = 'ASC';
    if (dir === 'desc') out.order_direction = 'DESC';
    // 历史错误 preset 曾写入 default，非达人会进备份盘
    if (driverName === 'AliyundriveOpen' && String(out.drive_type || '').trim() === 'default') {
      out.drive_type = 'resource';
    }
  }
  if (driverName === 'S3') {
    normalizeS3Addition(out);
  }
  return out;
}

const OPENLIST_OAUTH_PAGE_URL = 'https://api.oplist.org/';

module.exports = {
  OPENLIST_COMMON_HIDDEN,
  S3_UI_FIELD_NAMES,
  OPENLIST_ONLINE_AUTH_DRIVERS,
  TOKEN_LIKE_FIELD_NAMES,
  isUiCredentialField,
  filterUiDriverFields,
  normalizeS3Endpoint,
  inferS3RegionFromEndpoint,
  normalizeS3Addition,
  mergeAdditionDefaults,
  OPENLIST_OAUTH_PAGE_URL,
};
