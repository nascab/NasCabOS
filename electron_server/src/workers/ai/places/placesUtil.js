'use strict';

const fs = require('fs');
const path = require('path');
const sharp = require('../../../utils/sharpConfigured');
const ort = require('onnxruntime-node');
const sharpUtils = require('../../../utils/sharpUtils');
const remoteAssets = require('../../../utils/remoteAssetsManager');
const { getBestExecutionProviders, getLoadedBackends } = require('../../../utils/onnxProviderUtil');
const Logger = require('../../../utils/logger');

try {
  sharp.cache(false);
  sharp.concurrency(1);
} catch (_) {}

const IMAGENET_MEAN = [0.485, 0.456, 0.406];
const IMAGENET_STD = [0.229, 0.224, 0.225];

const MODEL_PATH = () => path.resolve(remoteAssets.resolveOnnxModelsRoot(), 'places365', 'resnet50_places365.onnx');
const LABELS_PATH = () => path.resolve(remoteAssets.resolveOnnxModelsRoot(), 'places365', 'categories_places365.txt');
const PLACES365_BUNDLE_ID = 'onnx_models.places365';

let _labels = null;
let _sessionPromise = null;
let _places365ReadyPromise = null;
let _inputName = null;
let _outputName = null;

async function ensurePlaces365Ready() {
  if (!_places365ReadyPromise) {
    _places365ReadyPromise = remoteAssets.ensureBundle(PLACES365_BUNDLE_ID);
  }
  return _places365ReadyPromise;
}

function isRemoteModelError(err) {
  const code = err && err.code ? String(err.code) : '';
  const msg = err && err.message ? String(err.message) : String(err || '');
  return (
    code === 'ENOENT' &&
    (msg.includes('onnx_models') || msg.includes('remote_assets'))
  );
}

function createSharpFromConverted(converted) {
  if (converted && typeof converted === 'object' && !Buffer.isBuffer(converted) && converted.input && converted.options) {
    return sharp(converted.input, converted.options);
  }
  return sharp(converted, { failOnError: false });
}

function _parsePlaces365Categories(text) {
  const labelByIndex = Array.from({ length: 365 }, () => null);
  const canonicalIdByIndex = Array.from({ length: 365 }, () => null);
  const canonicalByLabel = new Map();
  const lines = String(text || '').split(/\r?\n/);
  for (const raw of lines) {
    const line = String(raw || '').trim();
    if (!line) continue;
    const parts = line.split(/\s+/);
    if (parts.length < 2) continue;
    let name = parts[0];
    const idx = Number.parseInt(parts[1], 10);
    if (!Number.isFinite(idx) || idx < 0 || idx >= 365) continue;
    if (name.startsWith('/') && name.length >= 3 && name[2] === '/') {
      name = name.slice(3);
    }
    name = name.replace(/^\/+/, '').replace(/_/g, ' ').trim();
    if (!name) continue;
    labelByIndex[idx] = name;
    const prev = canonicalByLabel.get(name);
    if (prev === undefined || idx < prev) {
      canonicalByLabel.set(name, idx);
    }
  }
  for (let i = 0; i < 365; i++) {
    const label = labelByIndex[i];
    if (!label) continue;
    const cid = canonicalByLabel.get(label);
    if (cid === undefined) continue;
    canonicalIdByIndex[i] = cid;
  }
  return { labelByIndex, canonicalIdByIndex };
}

async function getPlaces365Labels() {
  if (_labels) return _labels;
  await ensurePlaces365Ready();
  const text = await fs.promises.readFile(LABELS_PATH(), 'utf8');
  _labels = _parsePlaces365Categories(text);
  return _labels;
}

async function getPlacesSession() {
  if (_sessionPromise) return _sessionPromise;
  _sessionPromise = (async () => {
    await ensurePlaces365Ready();
    const sessionOptions = {
      executionProviders: getBestExecutionProviders(),
      enableCpuMemArena: false,
      enableMemPattern: false,
      graphOptimizationLevel: 'all',
    };
    const sess = await ort.InferenceSession.create(MODEL_PATH(), sessionOptions);
    Logger.info(`[placesUtil] Selected providers: ${sessionOptions.executionProviders.join(', ')}`);
    Logger.info(`[placesUtil] Loaded backends: ${getLoadedBackends()}`);
    _inputName = Array.isArray(sess.inputNames) && sess.inputNames.length > 0 ? sess.inputNames[0] : null;
    _outputName = Array.isArray(sess.outputNames) && sess.outputNames.length > 0 ? sess.outputNames[0] : null;
    if (!_inputName) {
      throw new Error('Places365 model input name not found');
    }
    if (!_outputName) {
      throw new Error('Places365 model output name not found');
    }
    return sess;
  })();
  return _sessionPromise;
}

async function _preprocessToChwFloat32(imagePath, inputSize = 224, resizeShorter = 256) {
  const converted = await sharpUtils.transSpcielFormat(imagePath);
  const img = createSharpFromConverted(converted).rotate().toColorspace('srgb').removeAlpha();
  const meta = await img.metadata();
  // .rotate() 按 EXIF 自动旋转；metadata() 的 width/height 是旋转前尺寸，
  // 90°/270°(orientation 5-8) 旋转后宽高互换，须用 autoOrient 的真实旋转后尺寸。
  const oriented = meta && meta.autoOrient;
  const w = Number(oriented && oriented.width) || Number(meta.width) || 0;
  const h = Number(oriented && oriented.height) || Number(meta.height) || 0;
  if (w <= 0 || h <= 0) throw new Error('Invalid image size');

  let newW = 0;
  let newH = 0;
  if (w < h) {
    newW = resizeShorter;
    newH = Math.round(h * (resizeShorter / w));
  } else {
    newH = resizeShorter;
    newW = Math.round(w * (resizeShorter / h));
  }
  newW = Math.max(newW, inputSize);
  newH = Math.max(newH, inputSize);

  const left = Math.floor((newW - inputSize) / 2);
  const top = Math.floor((newH - inputSize) / 2);

  const { data, info } = await img
    .resize(newW, newH, { fit: 'fill', kernel: sharp.kernel.cubic })
    .extract({ left, top, width: inputSize, height: inputSize })
    .raw()
    .toBuffer({ resolveWithObject: true });

  // 强制检查 buffer 长度是否符合预期 (h * w * 3)
  const expected = info.height * info.width * 3;
  if (data.length !== expected) {
    throw new Error(`places preprocess buffer mismatch: got ${data.length}, expected ${expected} (h=${info.height}, w=${info.width}, c=3)`);
  }

  // Use Buffer.from to ensure safe memory
  const safeData = Buffer.from(data);
  const channels = 3; // We forced srgb so it's always 3

  const hw = inputSize * inputSize;
  const out = new Float32Array(3 * hw);
  for (let i = 0; i < hw; i++) {
    const base = i * channels;
    const r = safeData[base] / 255;
    const g = safeData[base + 1] / 255;
    const b = safeData[base + 2] / 255;

    out[i] = (r - IMAGENET_MEAN[0]) / IMAGENET_STD[0];
    out[hw + i] = (g - IMAGENET_MEAN[1]) / IMAGENET_STD[1];
    out[2 * hw + i] = (b - IMAGENET_MEAN[2]) / IMAGENET_STD[2];
  }
  return out;
}

function _top1Softmax(logits) {
  const arr = ArrayBuffer.isView(logits) ? logits : Float32Array.from(logits || []);
  if (!arr || arr.length === 0) return { index: 0, prob: 0 };

  let max = -Infinity;
  let maxIdx = 0;
  for (let i = 0; i < arr.length; i++) {
    const v = arr[i];
    if (v > max) {
      max = v;
      maxIdx = i;
    }
  }

  let sum = 0;
  for (let i = 0; i < arr.length; i++) {
    sum += Math.exp(arr[i] - max);
  }
  const prob = sum > 0 ? Math.exp(arr[maxIdx] - max) / sum : 0;
  return { index: maxIdx, prob };
}

async function predictPlace(imagePath) {
  const fullPath = String(imagePath || '');
  if (!fullPath) throw new Error('Invalid image path');

  await ensurePlaces365Ready();
  const [sess, labels] = await Promise.all([getPlacesSession(), getPlaces365Labels()]);
  const chw = await _preprocessToChwFloat32(fullPath);
  const input = new ort.Tensor('float32', chw, [1, 3, 224, 224]);
  const out = await sess.run({ [_inputName]: input });
  const logitsTensor = out[_outputName];
  const logits = logitsTensor && logitsTensor.data ? logitsTensor.data : null;
  const { index: rawIndex, prob } = _top1Softmax(logits);
  const label = labels && labels.labelByIndex ? labels.labelByIndex[rawIndex] || '' : '';
  const canonicalId = labels && labels.canonicalIdByIndex ? labels.canonicalIdByIndex[rawIndex] : null;
  const mappedIndex = Number.isFinite(Number(canonicalId)) ? Number(canonicalId) : rawIndex;
  return { index: label ? mappedIndex : rawIndex, label, prob };
}

module.exports = {
  predictPlace,
  getPlaces365Labels,
  getPlacesSession,
  ensurePlaces365Ready,
  isRemoteModelError,
};
