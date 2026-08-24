const fs = require('fs');
const path = require('path');
const sharp = require('../../../utils/sharpConfigured');
const onnx = require('onnxruntime-node');
const sharpUtils = require('../../../utils/sharpUtils');
const remoteAssets = require('../../../utils/remoteAssetsManager');
const { getBestExecutionProviders, getLoadedBackends } = require('../../../utils/onnxProviderUtil');
const Logger = require('../../../utils/logger');

try {
  sharp.cache(false);
  sharp.concurrency(1);
} catch (_) {}

const MODELS_DIR = () => path.join(remoteAssets.resolveOnnxModelsRoot(), 'ppocrv5');
const DET_MODEL_PATH = () => path.join(MODELS_DIR(), 'det/det.onnx');
const CLS_MODEL_PATH = () => path.join(MODELS_DIR(), 'cls/cls.onnx');
const REC_MODEL_PATH = () => path.join(MODELS_DIR(), 'rec/rec.onnx');
const DICT_PATH = () => path.join(MODELS_DIR(), 'ppocrv5_dict.txt');

const DET_LIMIT_SIDE_LEN = Number(process.env.DET_LIMIT_SIDE_LEN ?? 960);
const DET_UPSCALE_MIN_SIDE = Number(process.env.DET_UPSCALE_MIN_SIDE ?? 960);
const DET_UPSCALE_MAX_SCALE = Number(process.env.DET_UPSCALE_MAX_SCALE ?? 4);
const DET_BIN_THRESH = Number(process.env.DET_BIN_THRESH ?? 0.25);
const DET_MIN_PIXELS = Number(process.env.DET_MIN_PIXELS ?? 6);
const DET_MIN_BOX_SIZE = Number(process.env.DET_MIN_BOX_SIZE ?? 6);
const DET_DILATE_X = Number(process.env.DET_DILATE_X ?? 7);
const DET_DILATE_Y = Number(process.env.DET_DILATE_Y ?? 1);
const DET_BOX_SCORE_THRESH = Number(process.env.DET_BOX_SCORE_THRESH ?? 0.4);

const REC_IMG_H = 48;
const REC_MAX_W = 960;
const REC_MIN_W = 8;

const CLS_IMG_H = 48;
const CLS_IMG_W = 192;
const CLS_THRESHOLD = 0.9;

const PPOCR_COLOR = (process.env.PPOCR_COLOR || 'BGR').toUpperCase() === 'RGB' ? 'RGB' : 'BGR';
const OCR_FILTER_RESULTS = (process.env.OCR_FILTER_RESULTS ?? 'true').toLowerCase() === 'true';

function loadDict(dictPath) {
  const content = fs.readFileSync(dictPath, 'utf8');
  const lines = content.split(/\r?\n/).filter(l => l !== '');
  return ['<blank>', ...lines, ' '];
}

function safeExtractBox(box, width, height) {
  const left = Math.max(0, Math.floor(box.x));
  const top = Math.max(0, Math.floor(box.y));
  const right = Math.min(width, Math.ceil(box.x + box.w));
  const bottom = Math.min(height, Math.ceil(box.y + box.h));
  const w = right - left;
  const h = bottom - top;
  if (w <= 0 || h <= 0) return null;
  return { left, top, width: w, height: h };
}

function chwFromHwcUint8(data, h, w, order, mean, std, scale) {
  const hw = h * w;
  const out = new Float32Array(3 * hw);
  for (let i = 0; i < hw; i++) {
    const r = data[i * 3];
    const g = data[i * 3 + 1];
    const b = data[i * 3 + 2];
    const ch = order === 'BGR' ? [b, g, r] : [r, g, b];
    out[i] = (ch[0] * scale - mean[0]) / std[0];
    out[i + hw] = (ch[1] * scale - mean[1]) / std[1];
    out[i + 2 * hw] = (ch[2] * scale - mean[2]) / std[2];
  }
  return out;
}

function computeDetResize(width, height, limitSideLen) {
  const maxSide = Math.max(width, height);
  const effectiveMinSide = Math.min(Math.max(0, DET_UPSCALE_MIN_SIDE), limitSideLen);
  let ratio = 1.0;
  if (effectiveMinSide > 0 && maxSide < effectiveMinSide) {
    ratio = effectiveMinSide / maxSide;
    if (DET_UPSCALE_MAX_SCALE > 0) ratio = Math.min(ratio, DET_UPSCALE_MAX_SCALE);
  }
  if (maxSide * ratio > limitSideLen) ratio = limitSideLen / maxSide;
  const scaledW = Math.max(2, Math.round(width * ratio));
  const scaledH = Math.max(2, Math.round(height * ratio));
  const padW = Math.max(32, Math.ceil(scaledW / 32) * 32);
  const padH = Math.max(32, Math.ceil(scaledH / 32) * 32);
  return { scaledW, scaledH, padW, padH, ratioW: width / scaledW, ratioH: height / scaledH, ratio };
}

function createSharpFromConverted(converted) {
  if (converted && typeof converted === 'object' && !Buffer.isBuffer(converted) && converted.input && converted.options) {
    return sharp(converted.input, converted.options);
  }
  return sharp(converted);
}

async function preprocessDet(imagePath) {
  const converted = await sharpUtils.transSpcielFormat(imagePath);
  const rotated = createSharpFromConverted(converted).rotate();
  // .rotate() 按 EXIF 自动旋转；metadata() 返回的是未旋转的源图尺寸，
  // 必须先输出旋转后的缓冲，取真实输出尺寸（90°/270° 旋转会交换宽高）。
  const { data: rotatedBuffer, info: rotatedInfo } = await rotated
    .clone()
    .toColorspace('srgb')
    .removeAlpha()
    .jpeg({ quality: 70 })
    .toBuffer({ resolveWithObject: true });

  const rotatedW = rotatedInfo.width;
  const rotatedH = rotatedInfo.height;
  const { scaledW, scaledH, padW, padH, ratioW, ratioH } = computeDetResize(rotatedW, rotatedH, DET_LIMIT_SIDE_LEN);
  let pipeline = sharp(rotatedBuffer).resize(scaledW, scaledH, { fit: 'fill', kernel: sharp.kernel.cubic });
  if (rotatedW && rotatedH && Math.max(rotatedW, rotatedH) < DET_UPSCALE_MIN_SIDE) {
    pipeline = pipeline.sharpen();
  }
  if (padW !== scaledW || padH !== scaledH) {
    pipeline = pipeline.extend({
      top: 0,
      bottom: padH - scaledH,
      left: 0,
      right: padW - scaledW,
      background: { r: 0, g: 0, b: 0, alpha: 1 },
    });
  }
  const { data, info } = await pipeline.toColorspace('srgb').removeAlpha().raw().toBuffer({ resolveWithObject: true });

  const expected = info.height * info.width * 3;
  if (data.length !== expected) {
    throw new Error(`ocr det preprocess buffer mismatch: got ${data.length}, expected ${expected}`);
  }
  const safeData = Buffer.from(data);

  const mean = [0.485, 0.456, 0.406];
  const std = [0.229, 0.224, 0.225];
  const scale = 1 / 255;
  const chw = chwFromHwcUint8(safeData, info.height, info.width, PPOCR_COLOR, mean, std, scale);
  const tensor = new onnx.Tensor('float32', chw, [1, 3, info.height, info.width]);

  return {
    tensor,
    detW: info.width,
    detH: info.height,
    ratioW,
    ratioH,
    rotatedBuffer,
    rotatedW,
    rotatedH,
  };
}

function extractProbMap(output) {
  const dims = output.dims;
  if (dims.length === 4) {
    const h = dims[2];
    const w = dims[3];
    return { data: output.data, h, w, offset: 0, stride: w };
  }
  if (dims.length === 3) {
    const h = dims[1];
    const w = dims[2];
    return { data: output.data, h, w, offset: 0, stride: w };
  }
  throw new Error(`Unexpected det output dims: ${JSON.stringify(dims)}`);
}

function binarizeProb(probData, thresh) {
  const bin = new Uint8Array(probData.length);
  for (let i = 0; i < probData.length; i++) bin[i] = probData[i] >= thresh ? 1 : 0;
  return bin;
}

function dilateBinary(bin, h, w, rx, ry) {
  if (rx <= 0 && ry <= 0) return bin;
  const out = new Uint8Array(h * w);
  for (let y = 0; y < h; y++) {
    const y0 = Math.max(0, y - ry);
    const y1 = Math.min(h - 1, y + ry);
    for (let x = 0; x < w; x++) {
      const x0 = Math.max(0, x - rx);
      const x1 = Math.min(w - 1, x + rx);
      let v = 0;
      for (let yy = y0; yy <= y1 && !v; yy++) {
        const base = yy * w;
        for (let xx = x0; xx <= x1; xx++) {
          if (bin[base + xx]) {
            v = 1;
            break;
          }
        }
      }
      out[y * w + x] = v;
    }
  }
  return out;
}

function boxMeanScore(probData, mapW, rect) {
  const { minX, minY, maxX, maxY } = rect;
  let sum = 0;
  let cnt = 0;
  for (let y = minY; y <= maxY; y++) {
    const base = y * mapW;
    for (let x = minX; x <= maxX; x++) {
      sum += probData[base + x];
      cnt++;
    }
  }
  return cnt ? sum / cnt : 0;
}

function connectedComponentsBoxesBinary(bin, h, w, minPixels) {
  const visited = new Uint8Array(h * w);
  const boxes = [];
  const qx = new Int32Array(h * w);
  const qy = new Int32Array(h * w);
  const idx = (yy, xx) => yy * w + xx;

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const p = idx(y, x);
      if (visited[p]) continue;
      if (!bin[p]) continue;
      visited[p] = 1;
      let head = 0;
      let tail = 0;
      qx[tail] = x;
      qy[tail] = y;
      tail++;
      let minX = x;
      let maxX = x;
      let minY = y;
      let maxY = y;
      let count = 0;

      while (head < tail) {
        const cx = qx[head];
        const cy = qy[head];
        head++;
        count++;
        if (cx < minX) minX = cx;
        if (cx > maxX) maxX = cx;
        if (cy < minY) minY = cy;
        if (cy > maxY) maxY = cy;

        for (let dy = -1; dy <= 1; dy++) {
          for (let dx = -1; dx <= 1; dx++) {
            if (dx === 0 && dy === 0) continue;
            const nx = cx + dx;
            const ny = cy + dy;
            if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
            const np = idx(ny, nx);
            if (visited[np]) continue;
            if (!bin[np]) continue;
            visited[np] = 1;
            qx[tail] = nx;
            qy[tail] = ny;
            tail++;
          }
        }
      }

      if (count >= minPixels) {
        boxes.push({ minX, minY, maxX, maxY, count });
      }
    }
  }
  return boxes;
}

function postprocessDetToBoxes(detOutput, detInputW, detInputH, ratioW, ratioH, origW, origH) {
  const prob = extractProbMap(detOutput);
  const h = prob.h;
  const w = prob.w;

  const bin = binarizeProb(prob.data, DET_BIN_THRESH);
  const dilated = dilateBinary(bin, h, w, DET_DILATE_X, DET_DILATE_Y);
  const comps = connectedComponentsBoxesBinary(dilated, h, w, DET_MIN_PIXELS);
  const scaleX = detInputW / w;
  const scaleY = detInputH / h;

  const mapped = comps
    .map(c => ({ minX: c.minX, minY: c.minY, maxX: c.maxX, maxY: c.maxY, score: boxMeanScore(prob.data, w, c) }))
    .filter(c => c.score >= DET_BOX_SCORE_THRESH)
    .map(b => {
      const x1 = Math.max(0, Math.floor(b.minX * scaleX));
      const y1 = Math.max(0, Math.floor(b.minY * scaleY));
      const x2 = Math.min(detInputW, Math.ceil((b.maxX + 1) * scaleX));
      const y2 = Math.min(detInputH, Math.ceil((b.maxY + 1) * scaleY));
      const ox1 = Math.floor(x1 * ratioW);
      const oy1 = Math.floor(y1 * ratioH);
      const ox2 = Math.ceil(x2 * ratioW);
      const oy2 = Math.ceil(y2 * ratioH);
      const cx1 = Math.max(0, Math.min(origW, ox1));
      const cy1 = Math.max(0, Math.min(origH, oy1));
      const cx2 = Math.max(0, Math.min(origW, ox2));
      const cy2 = Math.max(0, Math.min(origH, oy2));
      return { x: cx1, y: cy1, w: cx2 - cx1, h: cy2 - cy1 };
    })
    .filter(b => b.w >= DET_MIN_BOX_SIZE && b.h >= DET_MIN_BOX_SIZE);

  mapped.sort((a, b) => a.y - b.y || a.x - b.x);
  return mapped;
}

async function preprocessClsFromBuffer(rotatedBuffer, rotatedMeta, box) {
  const safeBox = safeExtractBox(box, rotatedMeta.width, rotatedMeta.height);
  if (!safeBox) return null;
  let pipeline = sharp(rotatedBuffer).extract(safeBox);
  if (safeBox.width < CLS_IMG_W || safeBox.height < CLS_IMG_H) pipeline = pipeline.sharpen();
  const { data, info } = await pipeline.resize(CLS_IMG_W, CLS_IMG_H, { fit: 'fill', kernel: sharp.kernel.cubic }).toColorspace('srgb').removeAlpha().raw().toBuffer({ resolveWithObject: true });

  const expected = info.height * info.width * 3;
  if (data.length !== expected) {
    throw new Error(`ocr cls preprocess buffer mismatch: got ${data.length}, expected ${expected}`);
  }
  const safeData = Buffer.from(data);

  const mean = [0.5, 0.5, 0.5];
  const std = [0.5, 0.5, 0.5];
  const scale = 1 / 255;
  const chw = chwFromHwcUint8(safeData, info.height, info.width, PPOCR_COLOR, mean, std, scale);
  return new onnx.Tensor('float32', chw, [1, 3, info.height, info.width]);
}

function softmax1d(arr) {
  let max = -Infinity;
  for (let i = 0; i < arr.length; i++) {
    if (arr[i] > max) max = arr[i];
  }
  let sum = 0;
  const exps = new Float32Array(arr.length);
  for (let i = 0; i < arr.length; i++) {
    const v = Math.exp(arr[i] - max);
    exps[i] = v;
    sum += v;
  }
  for (let i = 0; i < arr.length; i++) exps[i] = exps[i] / sum;
  return exps;
}

async function preprocessRecFromBuffer(rotatedBuffer, rotatedMeta, box, rotateAngle) {
  const safeBox = safeExtractBox(box, rotatedMeta.width, rotatedMeta.height);
  if (!safeBox) return null;

  let pipeline = sharp(rotatedBuffer).extract(safeBox);
  if (rotateAngle === 180) {
    pipeline = pipeline.rotate(180);
  }
  if (safeBox.height < REC_IMG_H) pipeline = pipeline.sharpen();

  const srcW = safeBox.width;
  const srcH = safeBox.height;
  let targetW = Math.floor(srcW * (REC_IMG_H / srcH));
  if (targetW > REC_MAX_W) targetW = REC_MAX_W;
  if (targetW < REC_MIN_W) targetW = REC_MIN_W;

  const { data, info } = await pipeline.resize({ height: REC_IMG_H, width: targetW, fit: 'fill', kernel: sharp.kernel.cubic }).removeAlpha().raw().toBuffer({ resolveWithObject: true });

  const mean = [0.5, 0.5, 0.5];
  const std = [0.5, 0.5, 0.5];
  const scale = 1 / 255;
  const chw = chwFromHwcUint8(data, info.height, info.width, PPOCR_COLOR, mean, std, scale);
  return new onnx.Tensor('float32', chw, [1, 3, info.height, info.width]);
}

function decodeCTCGreedy(data, dims, dict) {
  const seqLen = dims[1];
  const vocab = dims[2];
  const blankIdx = 0;
  let prev = -1;
  const chars = [];
  let confSum = 0;
  let confCount = 0;

  for (let t = 0; t < seqLen; t++) {
    const base = t * vocab;
    let bestIdx = 0;
    let bestVal = -Infinity;
    for (let k = 0; k < vocab; k++) {
      const v = data[base + k];
      if (v > bestVal) {
        bestVal = v;
        bestIdx = k;
      }
    }
    if (bestIdx !== blankIdx && bestIdx !== prev) {
      const ch = dict[bestIdx] ?? '';
      if (ch !== '<blank>') {
        chars.push(ch);
        confSum += bestVal;
        confCount++;
      }
    }
    prev = bestIdx;
  }

  return { text: chars.join(''), confidence: confCount ? confSum / confCount : 0 };
}

function normalizeAndFilterText(text) {
  const stripped = text.replace(/[\s\u3000]+/g, '');
  if (stripped.length === 0) return null;
  if (!/[\p{L}\p{N}]/u.test(stripped)) return null;
  return stripped;
}

class OnnxOcrEngine {
  constructor() {
    this.dict = null;
    this.detSession = null;
    this.recSession = null;
    this.clsSession = null;
  }

  async init() {
    this.dict = loadDict(DICT_PATH());
        const sessionOptions = {
      executionProviders: getBestExecutionProviders(),
      enableCpuMemArena: false,
      enableMemPattern: false,
      graphOptimizationLevel: 'all',
    };
    this.detSession = await onnx.InferenceSession.create(DET_MODEL_PATH(), sessionOptions);
    this.recSession = await onnx.InferenceSession.create(REC_MODEL_PATH(), sessionOptions);
    Logger.info(`[ocrOnnx] Selected providers: ${sessionOptions.executionProviders.join(', ')}`);
    Logger.info(`[ocrOnnx] Loaded backends: ${getLoadedBackends()}`);
    try {
      if (fs.existsSync(CLS_MODEL_PATH())) {
        this.clsSession = await onnx.InferenceSession.create(CLS_MODEL_PATH(), sessionOptions);
      }
    } catch (e) {
      this.clsSession = null;
    }
    return this;
  }

  async ocrImage(imagePath, filterResults = OCR_FILTER_RESULTS) {
    if (!imagePath || !fs.existsSync(imagePath)) return '';

    let detPrep = null;
    try {
      detPrep = await preprocessDet(imagePath);
      const detFeeds = {};
      detFeeds[this.detSession.inputNames[0]] = detPrep.tensor;
      const detRes = await this.detSession.run(detFeeds);
      const detOut = detRes[this.detSession.outputNames[0]];

      const boxes = postprocessDetToBoxes(detOut, detPrep.detW, detPrep.detH, detPrep.ratioW, detPrep.ratioH, detPrep.rotatedW, detPrep.rotatedH);
      const rotatedMeta = await sharp(detPrep.rotatedBuffer).metadata();

      const results = [];

      for (const box of boxes) {
        let rotateAngle = 0;
        if (this.clsSession) {
          const clsTensor = await preprocessClsFromBuffer(detPrep.rotatedBuffer, rotatedMeta, box);
          if (clsTensor) {
            const clsFeeds = {};
            clsFeeds[this.clsSession.inputNames[0]] = clsTensor;
            const clsRes = await this.clsSession.run(clsFeeds);
            const clsOut = clsRes[this.clsSession.outputNames[0]];
            const probs = softmax1d(clsOut.data);
            const idx = probs[1] > probs[0] ? 1 : 0;
            const score = probs[idx];
            if (idx === 1 && score >= CLS_THRESHOLD) rotateAngle = 180;
          }
        }

        const recTensor = await preprocessRecFromBuffer(detPrep.rotatedBuffer, rotatedMeta, box, rotateAngle);
        if (!recTensor) continue;
        const recFeeds = {};
        recFeeds[this.recSession.inputNames[0]] = recTensor;
        const recRes = await this.recSession.run(recFeeds);
        const recOut = recRes[this.recSession.outputNames[0]];

        if (this.dict.length !== recOut.dims[2]) return '';

        const decoded = decodeCTCGreedy(recOut.data, recOut.dims, this.dict);
        let text = decoded.text;
        if (filterResults) {
          text = normalizeAndFilterText(decoded.text);
          if (!text) continue;
        } else {
          if (!text || text.replace(/[\s\u3000]+/g, '').length === 0) continue;
        }
        results.push({ box, text, confidence: decoded.confidence, rotateAngle });
      }

      if (results.length === 0) return '';
      return {
        imagePath,
        results,
        text: results.map(r => r.text).join('\n'),
      };
    } finally {
      if (detPrep && detPrep.tensor) detPrep.tensor = null;
      if (detPrep && detPrep.rotatedBuffer) detPrep.rotatedBuffer = null;
      detPrep = null;
    }
  }

  async ocrImages(imagePaths, filterResults = OCR_FILTER_RESULTS) {
    const inputs = Array.isArray(imagePaths) ? imagePaths : [imagePaths];
    const outputs = [];
    for (const p of inputs) {
      outputs.push(await this.ocrImage(p, filterResults));
    }
    return outputs;
  }
}

let _enginePromise = null;

async function getOcrEngine() {
  if (!_enginePromise) {
    _enginePromise = (async () => {
      const remoteAssets = require('../../../utils/remoteAssetsManager');
      await remoteAssets.ensureBundle('onnx_models.ppocrv5');
      return new OnnxOcrEngine().init();
    })();
  }
  return _enginePromise;
}

async function ocrImage(imagePath, filterResults = OCR_FILTER_RESULTS) {
  const engine = await getOcrEngine();
  return engine.ocrImage(imagePath, filterResults);
}

async function ocrImages(imagePaths, filterResults = OCR_FILTER_RESULTS) {
  const engine = await getOcrEngine();
  return engine.ocrImages(imagePaths, filterResults);
}

async function main() {
  const data = await ocrImages(['./ocrtest.jpg', './ocrtest3.jpg'], OCR_FILTER_RESULTS);
  console.log(data);
}

module.exports = { OnnxOcrEngine, getOcrEngine, ocrImage, ocrImages };

if (require.main === module) {
  main().catch(e => {
    console.error(e);
    process.exitCode = 1;
  });
}
