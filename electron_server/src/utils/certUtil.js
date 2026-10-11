'use strict';

const forge = require('node-forge');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const tls = require('tls');
const config = require('../config/config');

// 默认自签名证书文件名
const DEFAULT_KEY_FILE = 'key.pem';
const DEFAULT_CERT_FILE = 'cert.pem';
// 用户自定义证书文件名（Nginx 常用的 PEM 格式）
const CUSTOM_KEY_FILE = 'key_custom.pem';
const CUSTOM_CERT_FILE = 'cert_custom.pem';

// 证书剩余有效期小于该天数时给出警告
const EXPIRE_WARN_DAYS = 30;

/**
 * 获取证书存储目录（用户数据目录下的 certs/）
 */
function getCertDir() {
  return path.join(config.getUserDataPath(), 'certs');
}

/**
 * 默认自签名证书路径
 */
function getDefaultCertPaths() {
  const certDir = getCertDir();
  return {
    keyPath: path.join(certDir, DEFAULT_KEY_FILE),
    certPath: path.join(certDir, DEFAULT_CERT_FILE),
  };
}

/**
 * 用户自定义证书路径
 */
function getCustomCertPaths() {
  const certDir = getCertDir();
  return {
    keyPath: path.join(certDir, CUSTOM_KEY_FILE),
    certPath: path.join(certDir, CUSTOM_CERT_FILE),
  };
}

/**
 * 生成新的默认自签名证书并写入磁盘（覆盖已有文件）。
 * @returns {{ keyPath: string, certPath: string }} 证书文件路径
 */
function generateDefaultCert(certDir, keyPath, certPath) {
  // RSA 2048 密钥对，首次生成约需 0.5~2 秒，之后缓存复用
  const keys = forge.pki.rsa.generateKeyPair(2048);
  const cert = forge.pki.createCertificate();

  cert.publicKey = keys.publicKey;
  cert.serialNumber = '01' + Date.now().toString(16);

  const now = new Date();
  cert.validity.notBefore = now;
  cert.validity.notAfter = new Date(now.getFullYear() + 10, now.getMonth(), now.getDate());

  const attrs = [
    { name: 'commonName', value: 'localhost' },
    { name: 'organizationName', value: 'NasCab OS Self-Signed' },
  ];
  cert.setSubject(attrs);
  cert.setIssuer(attrs);

  // 添加 SAN：localhost、127.0.0.1、本机 IP
  cert.setExtensions([
    {
      name: 'subjectAltName',
      altNames: [
        { type: 2, value: 'localhost' },
        { type: 7, ip: '127.0.0.1' },
      ],
    },
    {
      name: 'basicConstraints',
      cA: false,
    },
  ]);

  cert.sign(keys.privateKey, forge.md.sha256.create());

  const certPem = forge.pki.certificateToPem(cert);
  const keyPem = forge.pki.privateKeyToPem(keys.privateKey);

  fs.writeFileSync(keyPath, keyPem, { mode: 0o600 });
  fs.writeFileSync(certPath, certPem, { mode: 0o644 });

  console.log('[certUtil] Self-signed certificate generated successfully.');
  return { keyPath, certPath };
}

/**
 * 确保证书存在且可用：
 * - 文件缺失 → 生成
 * - 文件存在但内容损坏（被截断/写入乱码/私钥与证书不配对）→ 重新生成
 * - 默认自签名证书已过期 → 重新生成
 * @returns {{ keyPath: string, certPath: string }} 证书文件路径
 */
function ensureCert() {
  const certDir = getCertDir();
  const keyPath = path.join(certDir, DEFAULT_KEY_FILE);
  const certPath = path.join(certDir, DEFAULT_CERT_FILE);

  const bothExist = fs.existsSync(keyPath) && fs.existsSync(certPath);
  if (bothExist && isCertPairFilesUsable(keyPath, certPath)) {
    return { keyPath, certPath };
  }

  try {
    fs.mkdirSync(certDir, { recursive: true });
  } catch (_) {}

  if (bothExist) {
    console.warn(
      '[certUtil] Default certificate is corrupted or expired, regenerating a self-signed certificate...'
    );
  } else {
    console.log('[certUtil] Generating self-signed certificate for HTTPS...');
  }

  return generateDefaultCert(certDir, keyPath, certPath);
}

/**
 * 判断磁盘上的私钥/证书文件是否可直接用于 HTTPS（任意异常均视为不可用）。
 */
function isCertPairFilesUsable(keyPath, certPath) {
  try {
    const keyPem = fs.readFileSync(keyPath, 'utf8');
    const certPem = fs.readFileSync(certPath, 'utf8');
    if (!keyPem || !keyPem.trim() || !certPem || !certPem.trim()) {
      return false;
    }
    return analyzeKeyCertPem(keyPem, certPem).errors.length === 0;
  } catch (_) {
    return false;
  }
}

/**
 * 读取文件文本（失败时返回错误码）
 */
function readPemFile(filePath, readCode, errors, errorDetails) {
  let content = '';
  try {
    content = fs.readFileSync(filePath, 'utf8');
  } catch (err) {
    errors.push(readCode);
    errorDetails.push(`${path.basename(filePath)}: ${err && err.message ? err.message : String(err)}`);
    return null;
  }
  if (!content || !content.trim()) {
    errors.push(readCode);
    errorDetails.push(`${path.basename(filePath)}: file is empty`);
    return null;
  }
  return content;
}

/**
 * 从证书 PEM 中提取所有证书块（支持 Nginx fullchain 形式的证书链）
 */
function extractCertBlocks(certPem) {
  const matches = certPem.match(/-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----/g);
  return Array.isArray(matches) ? matches : [];
}

/**
 * 从 DN 字符串中提取 CN（兼容 Node 各版本 X500Name/string 两种形式）
 */
function extractCn(dn) {
  const raw = String(dn || '');
  const match = raw.match(/CN\s*=\s*([^,\/]+)/i);
  return match ? match[1].trim() : raw;
}

/**
 * 对已读入内存的私钥/证书 PEM 做密码学分析（自定义证书与默认证书健康检查共用）。
 *
 * @returns {object}
 *   - errors {string[]} 阻断性问题代码
 *   - errorDetails {string[]} 原始错误信息（排障用）
 *   - warnings {string[]} 非阻断性警告代码
 *   - warningParams {object} 警告附带参数（如剩余天数）
 *   - cert {object|null} 证书概要
 */
function analyzeKeyCertPem(keyPem, certPem) {
  const errors = [];
  const errorDetails = [];
  const warnings = [];
  const warningParams = {};
  const analysis = { errors, errorDetails, warnings, warningParams, cert: null };

  // 1) 解析私钥（支持 RSA / ECDSA / Ed25519；拒绝加密私钥）
  //    加密私钥的 PEM 特征跨 Node/OpenSSL 版本稳定，直接识别（不同版本 createPrivateKey
  //    对“缺少密码”的报错信息不一致，不能依赖错误文案判断）
  let privateKey = null;
  const isEncryptedPem =
    /-----BEGIN ENCRYPTED PRIVATE KEY-----/i.test(keyPem) ||
    /Proc-Type:\s*4,ENCRYPTED/i.test(keyPem);
  if (isEncryptedPem) {
    errors.push('CUSTOM_KEY_ENCRYPTED');
  } else {
    try {
      privateKey = crypto.createPrivateKey(keyPem);
    } catch (err) {
      const msg = err && err.message ? String(err.message) : String(err);
      if (/passphrase|decrypt|ENCRYPTED/i.test(msg)) {
        errors.push('CUSTOM_KEY_ENCRYPTED');
      } else {
        errors.push('CUSTOM_KEY_INVALID');
      }
      errorDetails.push(msg);
    }
  }

  // 2) 解析证书（leaf 及证书链中的每一张证书）
  const blocks = extractCertBlocks(certPem);
  if (blocks.length === 0) {
    errors.push('CUSTOM_CERT_INVALID');
    errorDetails.push('No valid CERTIFICATE PEM block found');
  }

  let leaf = null;
  const chain = [];
  if (blocks.length > 0) {
    try {
      leaf = new crypto.X509Certificate(blocks[0]);
      chain.push(leaf);
    } catch (err) {
      errors.push('CUSTOM_CERT_INVALID');
      errorDetails.push(`leaf: ${err && err.message ? err.message : String(err)}`);
    }
    for (let i = 1; i < blocks.length; i += 1) {
      try {
        chain.push(new crypto.X509Certificate(blocks[i]));
      } catch (err) {
        warnings.push('CHAIN_INVALID');
        errorDetails.push(`chain[${i}]: ${err && err.message ? err.message : String(err)}`);
      }
    }
  }

  // 3) 私钥与 leaf 证书必须匹配
  if (privateKey && leaf) {
    let matched = false;
    try {
      matched = leaf.checkPrivateKey(privateKey);
    } catch (err) {
      errorDetails.push(`checkPrivateKey: ${err && err.message ? err.message : String(err)}`);
    }
    if (!matched) {
      errors.push('KEY_CERT_MISMATCH');
    }
  }

  // 4) 证书链逐级签名校验（仅警告：顺序异常/缺少中间证书不影响 HTTPS 启动，但部分客户端可能不信任）
  for (let i = 0; i < chain.length - 1; i += 1) {
    try {
      const ok = chain[i].verify(chain[i + 1].publicKey);
      if (!ok) {
        warnings.push('CHAIN_BROKEN');
        break;
      }
    } catch (_) {
      warnings.push('CHAIN_BROKEN');
      break;
    }
  }

  // 5) 有效期检查
  if (leaf) {
    const nowMs = Date.now();
    const notBeforeMs = Date.parse(leaf.validFrom);
    const notAfterMs = Date.parse(leaf.validTo);
    if (Number.isFinite(notBeforeMs) && nowMs < notBeforeMs) {
      errors.push('CERT_NOT_YET_VALID');
    }
    if (Number.isFinite(notAfterMs) && nowMs > notAfterMs) {
      errors.push('CERT_EXPIRED');
    }
    const daysRemaining = Number.isFinite(notAfterMs)
      ? Math.ceil((notAfterMs - nowMs) / (24 * 60 * 60 * 1000))
      : null;
    if (
      !errors.includes('CERT_EXPIRED') &&
      daysRemaining !== null &&
      daysRemaining <= EXPIRE_WARN_DAYS
    ) {
      warnings.push('EXPIRING_SOON');
      warningParams.EXPIRING_SOON = { days: daysRemaining };
    }

    analysis.cert = {
      subject: extractCn(leaf.subject),
      subjectDn: String(leaf.subject || ''),
      issuer: extractCn(leaf.issuer),
      issuerDn: String(leaf.issuer || ''),
      validFrom: leaf.validFrom,
      validTo: leaf.validTo,
      daysRemaining,
      isCa: !!leaf.ca,
      fingerprint256: leaf.fingerprint256 || '',
      chainLength: chain.length,
    };
  }

  // 6) 终极兜底：用 Node TLS 真正加载一次（与 https.createServer 同路径），
  //    捕获前述检查遗漏的加载类问题
  if (privateKey && blocks.length > 0 && !errors.includes('CUSTOM_CERT_INVALID')) {
    try {
      tls.createSecureContext({ key: keyPem, cert: certPem });
    } catch (err) {
      const msg = err && err.message ? err.message : String(err);
      if (!errors.includes('KEY_CERT_MISMATCH') || !/key values mismatch/i.test(msg)) {
        errors.push('TLS_CONTEXT_FAILED');
        errorDetails.push(msg);
      }
    }
  }

  return analysis;
}

/**
 * 校验用户自定义 SSL 证书（key_custom.pem / cert_custom.pem）。
 * 纯读取+密码学校验，不修改任何文件，主进程与 Worker 均可调用。
 *
 * @returns {object} 校验结果
 *   - configured {boolean} 两个自定义文件是否都存在
 *   - valid {boolean} 是否可直接用于 HTTPS（无阻断性错误）
 *   - errors {string[]} 阻断性问题代码（UI 按代码做 i18n）
 *   - errorDetails {string[]} 原始错误信息（排障用）
 *   - warnings {string[]} 非阻断性警告代码
 *   - warningParams {object} 警告附带参数（如剩余天数）
 *   - cert {object|null} 证书概要（主题/签发者/有效期/剩余天数/指纹）
 */
function validateCustomCert() {
  const { keyPath, certPath } = getCustomCertPaths();

  const result = {
    keyPath,
    certPath,
    keyFile: CUSTOM_KEY_FILE,
    certFile: CUSTOM_CERT_FILE,
    configured: false,
    valid: false,
    errors: [],
    errorDetails: [],
    warnings: [],
    warningParams: {},
    cert: null,
  };

  const keyExists = fs.existsSync(keyPath);
  const certExists = fs.existsSync(certPath);
  if (!keyExists) result.errors.push('CUSTOM_KEY_MISSING');
  if (!certExists) result.errors.push('CUSTOM_CERT_MISSING');
  if (!keyExists || !certExists) {
    return result;
  }
  result.configured = true;

  const keyPem = readPemFile(keyPath, 'KEY_READ_FAILED', result.errors, result.errorDetails);
  const certPem = readPemFile(certPath, 'CERT_READ_FAILED', result.errors, result.errorDetails);
  if (!keyPem || !certPem) {
    return result;
  }

  const analysis = analyzeKeyCertPem(keyPem, certPem);
  result.errors.push(...analysis.errors);
  result.errorDetails.push(...analysis.errorDetails);
  result.warnings.push(...analysis.warnings);
  Object.assign(result.warningParams, analysis.warningParams);
  result.cert = analysis.cert;
  result.valid = result.errors.length === 0;
  return result;
}

/**
 * 选择 HTTPS 服务本次启动使用的证书：
 * 自定义证书存在且校验通过时优先使用；否则回退默认自签名证书。
 *
 * @returns {{ keyPath: string, certPath: string, source: 'custom'|'default', custom: object }}
 */
function resolveServerCert() {
  // 先确保默认证书可用（回退保底）
  const defaultPaths = ensureCert();
  let custom = null;
  try {
    custom = validateCustomCert();
  } catch (err) {
    console.warn('[certUtil] Custom certificate validation failed unexpectedly:', err && err.message ? err.message : err);
  }

  if (custom && custom.configured) {
    if (custom.valid) {
      console.log('[certUtil] Using custom SSL certificate for HTTPS.');
      return {
        keyPath: custom.keyPath,
        certPath: custom.certPath,
        source: 'custom',
        custom,
      };
    }
    console.warn(
      `[certUtil] Custom certificate is invalid (${custom.errors.join(', ')}), falling back to the default self-signed certificate.`
    );
    if (custom.errorDetails && custom.errorDetails.length) {
      console.warn(`[certUtil] Custom certificate details: ${custom.errorDetails.join(' | ')}`);
    }
  }

  return {
    keyPath: defaultPaths.keyPath,
    certPath: defaultPaths.certPath,
    source: 'default',
    custom,
  };
}

module.exports = {
  getCertDir,
  getDefaultCertPaths,
  getCustomCertPaths,
  ensureCert,
  validateCustomCert,
  resolveServerCert,
  CUSTOM_KEY_FILE,
  CUSTOM_CERT_FILE,
};
