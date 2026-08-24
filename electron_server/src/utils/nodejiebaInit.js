'use strict';

const path = require('path');
const fs = require('fs');

let loaded = false;

function pathInsideAppAsar(p) {
  const norm = p.split(path.sep).join('/');
  return norm.includes('/app.asar/') || norm.endsWith('/app.asar');
}

/**
 * Electron 打包后，Worker 里 nodejieba 的 __dirname 可能仍落在 app.asar 内；
 * C++ 侧用 std::ifstream 无法从 asar 读文件（部分 Windows 必现失败）。
 * 通过 require.resolve 取包路径，并优先使用 app.asar.unpacked 下的真实词典路径。
 */
function resolveDictDir() {
  const pkgRoot = path.dirname(require.resolve('nodejieba/package.json'));
  const rel = path.join('submodules', 'cppjieba', 'dict');
  const candidates = [];

  if (pathInsideAppAsar(pkgRoot)) {
    const unpackedRoot = pkgRoot.replace(/app\.asar(?=[\\/]|$)/g, 'app.asar.unpacked');
    if (unpackedRoot !== pkgRoot) {
      candidates.push(path.join(unpackedRoot, rel));
    }
  }
  candidates.push(path.join(pkgRoot, rel));

  for (const dir of candidates) {
    if (fs.existsSync(path.join(dir, 'jieba.dict.utf8'))) {
      return dir;
    }
  }
  return path.join(pkgRoot, rel);
}

function ensureNodejiebaDictLoaded() {
  if (loaded) return;
  const nodejieba = require('nodejieba');
  const dictDir = resolveDictDir();
  nodejieba.load({
    dict: path.join(dictDir, 'jieba.dict.utf8'),
    hmmDict: path.join(dictDir, 'hmm_model.utf8'),
    userDict: path.join(dictDir, 'user.dict.utf8'),
    idfDict: path.join(dictDir, 'idf.utf8'),
    stopWordDict: path.join(dictDir, 'stop_words.utf8'),
  });
  loaded = true;
}

module.exports = { ensureNodejiebaDictLoaded, resolveDictDir };
