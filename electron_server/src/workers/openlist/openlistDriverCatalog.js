/**
 * 网盘挂载允许的 OpenList 驱动（固定列表，不请求 OpenList API）。
 * @see https://doc.oplist.org/
 */

const OPENLIST_DOC_BASE = 'https://doc.oplist.org/guide/drivers';

const ALLOWED_OPENLIST_DRIVERS = [
  'BaiduNetdisk',
  '123Pan',
  '115 Open',
  'Onedrive',
  'AliyundriveOpen',
  'S3',
];

/** OpenList 官方驱动文档路径（slug） */
const DRIVER_DOC_SLUG = {
  BaiduNetdisk: 'baidu',
  '123Pan': '123',
  '115 Open': '115_open',
  Onedrive: 'onedrive',
  AliyundriveOpen: 'aliyundrive_open',
  S3: 's3',
};

/** @type {Record<string, { additional: object[] }>} */
const DRIVER_SCHEMAS = {
  BaiduNetdisk: {
    additional: [{ name: 'refresh_token', type: 'string', required: true }],
  },
  '123Pan': {
    additional: [
      { name: 'username', type: 'string', required: true },
      { name: 'password', type: 'string', required: true },
    ],
  },
  '115 Open': {
    additional: [
      { name: 'refresh_token', type: 'string', required: true },
      { name: 'access_token', type: 'string', required: true },
    ],
  },
  Onedrive: {
    additional: [{ name: 'refresh_token', type: 'string', required: true }],
  },
  AliyundriveOpen: {
    additional: [{ name: 'refresh_token', type: 'string', required: true }],
  },
  S3: {
    additional: [
      { name: 'bucket', type: 'string', required: true },
      {
        name: 'endpoint',
        type: 'string',
        required: true,
        help: '腾讯云 COS 填 cos.ap-guangzhou.myqcloud.com（勿带 https、勿带桶名前缀）',
      },
      {
        name: 'region',
        type: 'string',
        required: true,
        help: '与 Endpoint 地域一致，如 ap-guangzhou；留空将自动从 Endpoint 推断',
      },
      { name: 'access_key_id', type: 'string', required: true },
      { name: 'secret_access_key', type: 'string', required: true },
      { name: 'session_token', type: 'string', required: false, help: '三段式临时凭证时填写' },
      {
        name: 'custom_host',
        type: 'string',
        required: false,
        help: 'CDN 加速域名（可选），如 cdn.example.com（勿带 https://）',
      },
      {
        name: 'force_path_style',
        type: 'bool',
        default: false,
        help: 'MinIO 等自建对象存储通常需开启',
      },
    ],
  },
};

function driverDocUrl(driver) {
  const slug = DRIVER_DOC_SLUG[String(driver || '').trim()];
  return slug ? `${OPENLIST_DOC_BASE}/${slug}` : '';
}

function isAllowedOpenlistDriver(driver) {
  const name = String(driver || '').trim();
  return ALLOWED_OPENLIST_DRIVERS.includes(name);
}

function getStaticDriverList() {
  return ALLOWED_OPENLIST_DRIVERS.map(driver => {
    const schema = DRIVER_SCHEMAS[driver] || { additional: [] };
    return {
      driver,
      name: driver,
      docUrl: driverDocUrl(driver),
      common: [],
      additional: schema.additional.slice(),
    };
  });
}

module.exports = {
  ALLOWED_OPENLIST_DRIVERS,
  DRIVER_SCHEMAS,
  DRIVER_DOC_SLUG,
  OPENLIST_DOC_BASE,
  driverDocUrl,
  isAllowedOpenlistDriver,
  getStaticDriverList,
};
