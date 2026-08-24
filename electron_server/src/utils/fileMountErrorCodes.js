/**
 * 远程挂载 worker 与 API 共用的错误码（与 language 中 messages.fileMount.* 对应）
 */

function ensureString(v) {
  if (v === undefined || v === null) return '';
  return String(v);
}

function truncate(s, max) {
  const t = ensureString(s);
  if (t.length > max) return `${t.slice(0, max)}…`;
  return t;
}

/**
 * 从 rclone 输出中提取独立出现的三位状态码（FTP 响应码 / HTTP 状态码），按优先级匹配
 */
function matchTransportStatusCode(stderr) {
  const raw = ensureString(stderr);
  const matches = new Set();
  const re = /\b(\d{3})\b/g;
  let m;
  while ((m = re.exec(raw)) !== null) matches.add(m[1]);
  const priority = [
    ['530', 'fileMount.RCLONE_FTP_530'],
    ['534', 'fileMount.RCLONE_FTP_534'],
    ['531', 'fileMount.RCLONE_FTP_531'],
    ['401', 'fileMount.RCLONE_AUTH'],
    ['403', 'fileMount.RCLONE_PERMISSION_DENIED'],
    ['404', 'fileMount.RCLONE_NOT_FOUND'],
    ['421', 'fileMount.RCLONE_FTP_421'],
    ['425', 'fileMount.RCLONE_FTP_425'],
    ['550', 'fileMount.RCLONE_FTP_550'],
    ['552', 'fileMount.RCLONE_FTP_552'],
    ['502', 'fileMount.RCLONE_HTTP_502'],
    ['503', 'fileMount.RCLONE_HTTP_503'],
    ['504', 'fileMount.RCLONE_HTTP_504'],
  ];
  for (const [code, key] of priority) {
    if (matches.has(code)) {
      return { code: key, detail: '' };
    }
  }
  return null;
}

/** 将 rclone stderr / 探测输出归类为 fileMount.* 码 */
function classifyRcloneStderr(stderr) {
  const t = ensureString(stderr).toLowerCase();
  if (!t) {
    return { code: 'fileMount.RCLONE_UNKNOWN', detail: '' };
  }
  if (t.includes('probe_timeout')) {
    return { code: 'fileMount.RCLONE_PROBE_TIMEOUT', detail: '' };
  }
  if (t.includes('connection refused')) {
    return { code: 'fileMount.RCLONE_CONNECTION_REFUSED', detail: '' };
  }
  if (t.includes('no such host') || (t.includes('lookup') && t.includes('failed'))) {
    return { code: 'fileMount.RCLONE_DNS', detail: '' };
  }
  const byCode = matchTransportStatusCode(stderr);
  if (byCode) {
    return byCode;
  }
  if (
    t.includes('authentication failed') ||
    t.includes('401') ||
    t.includes('unauthorized') ||
    t.includes('invalid credentials')
  ) {
    return { code: 'fileMount.RCLONE_AUTH', detail: '' };
  }
  if (t.includes('certificate') || t.includes('x509') || t.includes('tls handshake') || t.includes('cert verify')) {
    return { code: 'fileMount.RCLONE_TLS', detail: '' };
  }
  if (t.includes('timeout') || t.includes('i/o timeout') || t.includes('deadline exceeded')) {
    return { code: 'fileMount.RCLONE_TIMEOUT', detail: '' };
  }
  if (t.includes('403') || t.includes('permission denied')) {
    return { code: 'fileMount.RCLONE_PERMISSION_DENIED', detail: '' };
  }
  if (t.includes('404') || t.includes('not found')) {
    return { code: 'fileMount.RCLONE_NOT_FOUND', detail: '' };
  }
  if (t.includes('host key')) {
    return { code: 'fileMount.RCLONE_HOST_KEY', detail: '' };
  }
  if (t.includes("couldn't connect") || t.includes('could not connect')) {
    return { code: 'fileMount.RCLONE_CONNECTION_FAILED', detail: '' };
  }
  if (t.includes('is not empty') && t.includes('allow-non-empty')) {
    return { code: 'fileMount.MOUNT_POINT_NOT_EMPTY', detail: '' };
  }
  /** WinFsp：挂载点目录已存在且非空、或已有占用时；Windows 上 --allow-non-empty 无效 */
  if (t.includes('mountpoint path already exists') || t.includes('mount point already exists')) {
    return { code: 'fileMount.MOUNT_POINT_NOT_EMPTY', detail: '' };
  }
  return { code: 'fileMount.RCLONE_UNKNOWN', detail: truncate(stderr, 480) };
}

function packLastError({ code, detail }) {
  const c = ensureString(code).trim();
  const d = ensureString(detail).trim();
  if (!c) return 'fileMount.RCLONE_UNKNOWN';
  if (!d) return c;
  return `${c}|${d}`;
}

/**
 * mount 前 lsd 探测、或 mount 失败后再次 lsd 时的归类。
 * rclone 对连接超时常输出 i/o timeout / deadline exceeded，会落到 RCLONE_TIMEOUT；
 * 在此场景下与「探测远程存储」文案一致，使用 RCLONE_PROBE_TIMEOUT。
 */
function classifyForRemoteProbe(stderr) {
  const cls = classifyRcloneStderr(stderr);
  if (cls.code === 'fileMount.RCLONE_TIMEOUT') {
    return { code: 'fileMount.RCLONE_PROBE_TIMEOUT', detail: '' };
  }
  return cls;
}

/** 将父目录检查结果映射为可存储的错误码 */
function parentCheckToCode(parentErr) {
  const p = ensureString(parentErr).trim();
  if (p === 'mount_parent_not_found') return 'fileMount.MOUNT_PARENT_NOT_FOUND';
  if (p === 'mount_parent_not_dir') return 'fileMount.MOUNT_PARENT_NOT_DIR';
  if (p === 'mount_parent_no_access') return 'fileMount.MOUNT_PARENT_NO_ACCESS';
  return 'fileMount.MOUNT_PARENT_NO_ACCESS';
}

function autoMountSkipCode(parentErr) {
  const p = ensureString(parentErr).trim();
  if (p === 'mount_parent_not_found') return 'fileMount.AUTO_MOUNT_PARENT_NOT_FOUND';
  if (p === 'mount_parent_not_dir') return 'fileMount.AUTO_MOUNT_PARENT_NOT_DIR';
  if (p === 'mount_parent_no_access') return 'fileMount.AUTO_MOUNT_PARENT_NO_ACCESS';
  return 'fileMount.AUTO_MOUNT_SKIPPED';
}

module.exports = {
  classifyRcloneStderr,
  classifyForRemoteProbe,
  packLastError,
  parentCheckToCode,
  autoMountSkipCode,
};
