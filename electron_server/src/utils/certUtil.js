'use strict';

const forge = require('node-forge');
const fs = require('fs');
const path = require('path');
const config = require('../config/config');

/**
 * 获取证书存储目录（用户数据目录下的 certs/）
 */
function getCertDir() {
  return path.join(config.getUserDataPath(), 'certs');
}

/**
 * 确保证书存在，不存在则自动生成自签名证书。
 * @returns {{ keyPath: string, certPath: string }} 证书文件路径
 */
function ensureCert() {
  const certDir = getCertDir();
  const keyPath = path.join(certDir, 'key.pem');
  const certPath = path.join(certDir, 'cert.pem');

  if (fs.existsSync(keyPath) && fs.existsSync(certPath)) {
    return { keyPath, certPath };
  }

  try {
    fs.mkdirSync(certDir, { recursive: true });
  } catch (_) {}

  console.log('[certUtil] Generating self-signed certificate for HTTPS...');

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

module.exports = { ensureCert, getCertDir };
