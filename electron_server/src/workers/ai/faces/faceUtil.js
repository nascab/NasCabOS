'use strict';

const fs = require('fs');
const path = require('path');
const sharp = require('../../../utils/sharpConfigured');
const onnx = require('onnxruntime-node');
const sharpUtils = require('../../../utils/sharpUtils');
const Logger = require('../../../utils/logger');
const remoteAssets = require('../../../utils/remoteAssetsManager');
const { getBestExecutionProviders, getLoadedBackends } = require('../../../utils/onnxProviderUtil');
try {
  sharp.cache(false);
  sharp.concurrency(1);
} catch (_) {}

// 模型路径配置：默认放在 userData/onnx_models/faces 或安装包 onnx_models/faces。
const MODELS_DIR = () => path.join(remoteAssets.resolveOnnxModelsRoot(), 'faces');
const FACE_LMK_E2E_MODEL_PATH = () => path.join(MODELS_DIR(), 'faceLandMark', 'faceLandMark.onnx');
const FACE_FEAT_MODEL_PATH = () => path.join(MODELS_DIR(), 'insightFace', 'model.onnx');

const E2E_INPUT_SIZE = Math.max(256, Number(process.env.FACE_LMK_E2E_INPUT_SIZE ?? 960));
// 检测置信度阈值：低于该 score 的候选框直接丢弃；越高越少误检，但也更容易漏检。
const DET_SCORE_THRESH = Math.max(0, Math.min(1, Number(process.env.FACE_DET_SCORE_THRESH ?? 0.8)));
// 人脸最小尺寸（像素）：过小的人脸通常特征不稳定，容易导致误分类/分裂。
// 该限制基于检测框的 width/height 的较小值。
const FACE_MIN_BOX_SIZE_PX = Math.max(0, Math.min(4096, Number(process.env.FACE_MIN_BOX_SIZE_PX ?? 80)));

// 特征提取输入尺寸：绝大多数 insightFace/arcface 模型都使用 112x112 对齐人脸。
const FEAT_INPUT_SIZE = 112;
// 特征模型归一化均值：按通道减去该值；127.5/128 与常见 insighthFace 预处理对齐。
const FEAT_MEAN = Number(process.env.FACE_FEAT_MEAN ?? 127.5);
// 特征模型归一化标准差：按通道除以该值；配合 FEAT_MEAN 控制到模型训练时的分布。
const FEAT_STD = Number(process.env.FACE_FEAT_STD ?? 128.0);
// 特征模型使用的通道顺序：有的 ONNX 是 BGR，有的是 RGB；需与模型训练设置一致，否则相似度会明显下降。
const FEAT_ORDER = (process.env.FACE_FEAT_ORDER || 'BGR').toUpperCase() === 'RGB' ? 'RGB' : 'BGR';
const FEAT_LUMA_NORM_ENABLED = String(process.env.FACE_FEAT_LUMA_NORM ?? '1') !== '0';
const FEAT_LUMA_NORM_MODE = String(process.env.FACE_FEAT_LUMA_NORM_MODE ?? 'MEAN').toUpperCase();
const FEAT_LUMA_TARGET_MEAN = Number(process.env.FACE_FEAT_LUMA_TARGET_MEAN ?? 127.5);
const FEAT_LUMA_TARGET_STD = Number(process.env.FACE_FEAT_LUMA_TARGET_STD ?? 64.0);
const FEAT_LUMA_EPS = Number(process.env.FACE_FEAT_LUMA_EPS ?? 1e-6);

function createSharpFromConverted(converted) {
  if (converted && typeof converted === 'object' && !Buffer.isBuffer(converted) && converted.input && converted.options) {
    return sharp(converted.input, converted.options);
  }
  return sharp(converted);
}

function bgrToRgbUint8(data) {
  if (!data || data.length % 3 !== 0) return null;
  const out = new Uint8Array(data.length);
  for (let i = 0; i < data.length; i += 3) {
    out[i] = data[i + 2];
    out[i + 1] = data[i + 1];
    out[i + 2] = data[i];
  }
  return out;
}

function rgbToBgrInplace(data) {
  if (!data || data.length % 3 !== 0) return null;
  const buf = Buffer.isBuffer(data) ? data : Buffer.from(data);
  for (let i = 0; i < buf.length; i += 3) {
    const r = buf[i];
    buf[i] = buf[i + 2];
    buf[i + 2] = r;
  }
  return buf;
}

function _clampUint8(v) {
  if (v <= 0) return 0;
  if (v >= 255) return 255;
  return v & 255;
}

function lumaNormalizeRgbInplace(rgb, mode, targetMean, targetStd, eps) {
  if (!rgb || rgb.length % 3 !== 0) return rgb;
  const buf = Buffer.isBuffer(rgb) ? rgb : Buffer.from(rgb);
  const pixels = buf.length / 3;
  if (!pixels) return buf;

  let sum = 0;
  let sum2 = 0;
  let minY = 255;
  let maxY = 0;
  for (let i = 0; i < buf.length; i += 3) {
    const r = buf[i];
    const g = buf[i + 1];
    const b = buf[i + 2];
    const y = 0.299 * r + 0.587 * g + 0.114 * b;
    sum += y;
    sum2 += y * y;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }

  const meanY = sum / pixels;
  const safeEps = Number.isFinite(eps) && eps > 0 ? eps : 1e-6;
  let scale = 1;
  let offset = (Number.isFinite(targetMean) ? targetMean : 127.5) - meanY;

  const m = String(mode || '').toUpperCase();
  if (m === 'MEAN_STD') {
    const varY = Math.max(0, sum2 / pixels - meanY * meanY);
    const stdY = Math.sqrt(varY);
    const tStd = Number.isFinite(targetStd) && targetStd > 0 ? targetStd : 64.0;
    scale = tStd / (stdY + safeEps);
    offset = (Number.isFinite(targetMean) ? targetMean : 127.5) - scale * meanY;
  } else if (m === 'MINMAX') {
    const range = maxY - minY;
    if (range > safeEps) {
      scale = 255 / range;
      offset = -minY * scale;
    }
  }

  if (!Number.isFinite(scale) || !Number.isFinite(offset) || (scale === 1 && offset === 0)) return buf;

  for (let i = 0; i < buf.length; i++) {
    const v = Math.round(buf[i] * scale + offset);
    buf[i] = _clampUint8(v);
  }
  return buf;
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

function safeExtractBox(box, width, height) {
  const left = Math.max(0, Math.floor(box.left));
  const top = Math.max(0, Math.floor(box.top));
  const right = Math.min(width, Math.ceil(box.left + box.width));
  const bottom = Math.min(height, Math.ceil(box.top + box.height));
  const w = right - left;
  const h = bottom - top;
  if (w <= 1 || h <= 1) return null;
  return { left, top, width: w, height: h };
}

function isFaceBoxAcceptable(box, rotatedMeta) {
  if (!box || !rotatedMeta) return false;
  const ow = Number(rotatedMeta.ow) || 0;
  const oh = Number(rotatedMeta.oh) || 0;
  if (!ow || !oh) return false;
  const w = Number(box.width) || 0;
  const h = Number(box.height) || 0;
  if (!(w > 1 && h > 1)) return false;
  const minSide = Math.min(w, h);
  if (FACE_MIN_BOX_SIZE_PX > 0 && minSide < FACE_MIN_BOX_SIZE_PX) return false;
  return true;
}

function normalizeL2(vec) {
  let sum = 0;
  for (let i = 0; i < vec.length; i++) sum += vec[i] * vec[i];
  const norm = Math.sqrt(sum) || 1;
  const out = new Float32Array(vec.length);
  for (let i = 0; i < vec.length; i++) out[i] = vec[i] / norm;
  return out;
}

function getNumericVal(arr, idx) {
  const val = arr[idx];
  return typeof val === 'bigint' ? Number(val) : val;
}

function bufferToFloat32(buf) {
  if (!buf || buf.length % 4 !== 0) return null;
  const view = new Float32Array(buf.buffer, buf.byteOffset, buf.byteLength / 4);
  return new Float32Array(view);
}

function float32ToBuffer(arr) {
  const f = arr instanceof Float32Array ? arr : new Float32Array(arr);
  return Buffer.from(f.buffer, f.byteOffset, f.byteLength);
}

function _toFinitePositiveInt(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n) || n <= 0) return fallback;
  return Math.floor(n);
}

function _dimIsThree(dim) {
  if (dim === 3) return true;
  if (typeof dim === 'bigint') return Number(dim) === 3;
  if (typeof dim === 'string') return Number(dim) === 3;
  return false;
}

function _hwcBgrToChwUint8(bgr, h, w) {
  const hh = _toFinitePositiveInt(h);
  const ww = _toFinitePositiveInt(w);
  const hw = hh * ww;
  const expected = hw * 3;
  if (!bgr || bgr.length !== expected) {
    throw new Error(`bad bgr buffer length, got=${bgr ? bgr.length : 0}, expected=${expected}`);
  }
  const out = new Uint8Array(expected);
  for (let i = 0; i < hw; i++) {
    const base = i * 3;
    out[i] = bgr[base];
    out[i + hw] = bgr[base + 1];
    out[i + 2 * hw] = bgr[base + 2];
  }
  return out;
}

function _hwcBgrToChwFloat32(bgr, h, w) {
  const hh = _toFinitePositiveInt(h);
  const ww = _toFinitePositiveInt(w);
  const hw = hh * ww;
  const expected = hw * 3;
  if (!bgr || bgr.length !== expected) {
    throw new Error(`bad bgr buffer length, got=${bgr ? bgr.length : 0}, expected=${expected}`);
  }
  const out = new Float32Array(expected);
  for (let i = 0; i < hw; i++) {
    const base = i * 3;
    out[i] = bgr[base];
    out[i + hw] = bgr[base + 1];
    out[i + 2 * hw] = bgr[base + 2];
  }
  return out;
}

function _hwcBgrToHwcFloat32(bgr, h, w) {
  const hh = _toFinitePositiveInt(h);
  const ww = _toFinitePositiveInt(w);
  const expected = hh * ww * 3;
  if (!bgr || bgr.length !== expected) {
    throw new Error(`bad bgr buffer length, got=${bgr ? bgr.length : 0}, expected=${expected}`);
  }
  const out = new Float32Array(expected);
  for (let i = 0; i < expected; i++) out[i] = bgr[i];
  return out;
}

function _getFirstName(arr, fallback) {
  if (Array.isArray(arr) && arr.length > 0 && arr[0]) return String(arr[0]);
  return fallback;
}

function _pickFeatOutputName(sess) {
  if (!sess) return null;
  const names = Array.isArray(sess.outputNames) ? sess.outputNames : [];
  if (names.includes('1333')) return '1333';
  return _getFirstName(names, null);
}

function _roundUpToMultiple(v, m) {
  const n = Math.max(0, Math.floor(Number(v) || 0));
  const mm = Math.max(1, Math.floor(Number(m) || 1));
  return Math.ceil(n / mm) * mm;
}

function _buildAlignInputTensor(sess, bgr, info, inputName) {
  const h = _toFinitePositiveInt(info && info.height ? info.height : 0);
  const w = _toFinitePositiveInt(info && info.width ? info.width : 0);
  if (!h || !w) throw new Error(`bad input image shape, h=${h}, w=${w}`);

  const meta = sess && sess.inputMetadata && inputName ? sess.inputMetadata[inputName] : null;
  const metaType = meta && meta.type ? String(meta.type) : 'uint8';
  const dimsTemplate = meta && Array.isArray(meta.dimensions) ? meta.dimensions : null;
  const dimsLen = dimsTemplate ? dimsTemplate.length : 0;

  let layout = 'HWC';
  if (dimsLen === 4) {
    layout = _dimIsThree(dimsTemplate[1]) ? 'NCHW' : 'NHWC';
  } else if (dimsLen === 3) {
    layout = _dimIsThree(dimsTemplate[0]) ? 'CHW' : 'HWC';
  }

  let tensorType = metaType;
  if (!['uint8', 'float32'].includes(tensorType)) tensorType = 'uint8';

  let data = null;
  let dims = null;

  if (layout === 'NCHW') {
    dims = [1, 3, h, w];
    data = tensorType === 'float32' ? _hwcBgrToChwFloat32(bgr, h, w) : _hwcBgrToChwUint8(bgr, h, w);
  } else if (layout === 'CHW') {
    dims = [3, h, w];
    data = tensorType === 'float32' ? _hwcBgrToChwFloat32(bgr, h, w) : _hwcBgrToChwUint8(bgr, h, w);
  } else {
    // NHWC or HWC
    dims = layout === 'NHWC' ? [1, h, w, 3] : [h, w, 3];
    if (tensorType === 'float32') {
      data = _hwcBgrToHwcFloat32(bgr, h, w);
    } else {
      // Validate buffer length for uint8 HWC/NHWC
      const expected = h * w * 3;
      if (!bgr || bgr.length !== expected) {
        throw new Error(`bad bgr buffer length for ${layout}, got=${bgr ? bgr.length : 0}, expected=${expected}`);
      }
      data = bgr;
    }
  }

  const tensor = new onnx.Tensor(tensorType, data, dims);
  return {
    tensor,
    debug: {
      inputName,
      metaType,
      tensorType,
      layout,
      dims,
      bufferLength: bgr ? bgr.length : 0,
      expectedLength: h * w * 3,
      isBuffer: Buffer.isBuffer(bgr),
    },
  };
}

class FaceEngine {
  constructor() {
    this._sessions = null;
    this._alignInputName = null;
    this._featInputName = null;
    this._featOutputName = null;
  }

  dispose() {
    const sess = this._sessions;
    this._sessions = null;
    this._alignInputName = null;
    this._featInputName = null;
    this._featOutputName = null;
    if (!sess) return;
    try {
      if (sess.align && typeof sess.align.release === 'function') sess.align.release();
    } catch {}
    try {
      if (sess.feat && typeof sess.feat.release === 'function') sess.feat.release();
    } catch {}
  }

  async init() {
    if (this._sessions) return;
    const sessionOptions = {
      executionProviders: ['cpu'],
      enableCpuMemArena: false,
      enableMemPattern: false,
      graphOptimizationLevel: 'all',
    };
    const [align, feat] = await Promise.all([
      onnx.InferenceSession.create(FACE_LMK_E2E_MODEL_PATH(), sessionOptions),
      onnx.InferenceSession.create(FACE_FEAT_MODEL_PATH(), sessionOptions),
    ]);

    this._sessions = { align, feat };
    Logger.info(`[faceUtil] Selected providers: ${sessionOptions.executionProviders.join(', ')}`);
    Logger.info(`[faceUtil] Loaded backends: ${getLoadedBackends()}`);
    this._alignInputName = _getFirstName(align && align.inputNames ? align.inputNames : null, 'input');
    this._featInputName = _getFirstName(feat && feat.inputNames ? feat.inputNames : null, 'input.1');
    this._featOutputName = _pickFeatOutputName(feat);

    try {

      if (align && align.inputMetadata && this._alignInputName && align.inputMetadata[this._alignInputName]) {
        Logger.info(`🧠 align input meta: ${JSON.stringify(align.inputMetadata[this._alignInputName])}`);
      }
      if (feat && feat.inputMetadata && this._featInputName && feat.inputMetadata[this._featInputName]) {
        Logger.info(`🧠 feat input meta: ${JSON.stringify(feat.inputMetadata[this._featInputName])}`);
      }
    } catch {}
  }

  async _preprocessE2E(imagePath) {
    const converted = await sharpUtils.transSpcielFormat(imagePath);
    const rotated = createSharpFromConverted(converted).rotate();
    const meta = await rotated.metadata();
    const orientedWidth = meta && meta.autoOrient ? Number(meta.autoOrient.width) || 0 : 0;
    const orientedHeight = meta && meta.autoOrient ? Number(meta.autoOrient.height) || 0 : 0;
    const ow = orientedWidth || Number(meta.width) || 0;
    const oh = orientedHeight || Number(meta.height) || 0;
    if (!ow || !oh) throw new Error('bad image metadata');
    const targetSize = Math.max(256, Math.min(E2E_INPUT_SIZE, _roundUpToMultiple(Math.max(ow, oh), 32)));
    const scale = Math.min(1, targetSize / ow, targetSize / oh);
    const newW = Math.max(1, Math.round(ow * scale));
    const newH = Math.max(1, Math.round(oh * scale));
    const padW = targetSize - newW;
    const padH = targetSize - newH;
    const padX = Math.floor(padW / 2);
    const padY = Math.floor(padH / 2);
    const padRight = padW - padX;
    const padBottom = padH - padY;
    const { data, info } = await rotated
      .clone()
      .resize(newW, newH, { fit: 'fill', kernel: sharp.kernel.cubic })
      .extend({ top: padY, bottom: padBottom, left: padX, right: padRight, background: { r: 0, g: 0, b: 0, alpha: 1 } })
      .toColorspace('srgb')
      .removeAlpha()
      .raw()
      .toBuffer({ resolveWithObject: true });

    // 强制检查 buffer 长度是否符合预期 (h * w * 3)
    const expected = info.height * info.width * 3;
    if (data.length !== expected) {
      throw new Error(`preprocess buffer mismatch: got ${data.length}, expected ${expected} (h=${info.height}, w=${info.width}, c=3)`);
    }

    const bgr = rgbToBgrInplace(data);
    if (!bgr) throw new Error('bad e2e preprocess buffer');
    return { rotatedMeta: { ow, oh }, tensorInfo: { bgr, info }, affine: { scale, padX, padY, targetSize } };
  }

  _postprocessE2E(results, affine, rotatedMeta) {
    const bboxes = results && results.bboxes ? results.bboxes : null;
    const scores = results && results.scores ? results.scores : null;
    const alignImgs = results && results.align_imgs ? results.align_imgs : null;
    if (!bboxes || !bboxes.dims || bboxes.dims.length < 2) return [];
    const numFaces = Number(bboxes.dims[0]) || 0;
    if (!numFaces) return [];
    const faces = [];
    const padX = Number(affine && affine.padX ? affine.padX : 0) || 0;
    const padY = Number(affine && affine.padY ? affine.padY : 0) || 0;
    const scale = Number(affine && affine.scale ? affine.scale : 1) || 1;
    const alignW = alignImgs && alignImgs.dims && alignImgs.dims.length >= 4 ? Number(alignImgs.dims[1]) || 224 : 224;
    const alignH = alignImgs && alignImgs.dims && alignImgs.dims.length >= 4 ? Number(alignImgs.dims[2]) || 224 : 224;
    const alignC = alignImgs && alignImgs.dims && alignImgs.dims.length >= 4 ? Number(alignImgs.dims[3]) || 3 : 3;
    const alignSize = alignW * alignH * alignC;

    for (let i = 0; i < numFaces; i++) {
      const scoreRaw = scores && scores.data ? getNumericVal(scores.data, i) : 0;
      const score = Number(scoreRaw) || 0;
      if (!Number.isFinite(score) || score < DET_SCORE_THRESH) continue;

      const x1 = Number((getNumericVal(bboxes.data, i * 4 + 0) - padX) / scale) || 0;
      const y1 = Number((getNumericVal(bboxes.data, i * 4 + 1) - padY) / scale) || 0;
      const x2 = Number((getNumericVal(bboxes.data, i * 4 + 2) - padX) / scale) || 0;
      const y2 = Number((getNumericVal(bboxes.data, i * 4 + 3) - padY) / scale) || 0;
      const safe = safeExtractBox({ left: x1, top: y1, width: x2 - x1, height: y2 - y1 }, rotatedMeta.ow, rotatedMeta.oh);
      if (!safe) continue;
      if (!isFaceBoxAcceptable(safe, rotatedMeta)) continue;

      let alignedImage = null;
      if (alignImgs && alignImgs.data && alignImgs.data.length >= (i + 1) * alignSize) {
        const start = i * alignSize;
        const end = start + alignSize;
        alignedImage = alignImgs.data.slice(start, end);
      }

      faces.push({ box: { ...safe, score }, alignedImage, alignSize: { w: alignW, h: alignH, c: alignC } });
    }
    return faces;
  }

  async detectFaces(imagePath) {
    await this.init();
    let preprocess = await this._preprocessE2E(imagePath);
    const { rotatedMeta, tensorInfo, affine } = preprocess;

    let inputTensor = null;
    let out = null;
    try {
      const built = _buildAlignInputTensor(this._sessions.align, tensorInfo.bgr, tensorInfo.info, this._alignInputName);
      inputTensor = built.tensor;
      let startTime = Date.now();
      out = await this._sessions.align.run({ [this._alignInputName]: inputTensor });
      const memoryAfter = process.memoryUsage();
      // console.log('Face推理后堆内存：', (memoryAfter.heapUsed / 1024 / 1024).toFixed(2), 'mb', '总计可用', (memoryAfter.heapTotal / 1024 / 1024).toFixed(2), 'mb');
      // console.log('Face推理耗时：', Date.now() - startTime, 'ms');
    } catch (err) {
      console.error('❌ onnx align run error:', err);
      throw err;
    } finally {
      if (inputTensor) {
        try {
          inputTensor.dispose();
        } catch {}
        inputTensor = null;
      }
      if (preprocess && preprocess.tensorInfo) {
        preprocess.tensorInfo.bgr = null;
      }
      preprocess = null;
    }

    let faces = [];
    try {
      faces = this._postprocessE2E(out, affine, rotatedMeta);
    } finally {
      if (out != null) {
        try {
          Object.values(out).forEach(tensor => tensor.dispose());
        } catch {}
        out = null;
      }
    }

    return { rotatedMeta, faces };
  }

  async _extractAlignedFace112(face) {
    const alignedRaw = face && face.alignedImage ? face.alignedImage : null;
    const alignSize = face && face.alignSize ? face.alignSize : null;
    const aw = alignSize && Number(alignSize.w) ? Number(alignSize.w) : 224;
    const ah = alignSize && Number(alignSize.h) ? Number(alignSize.h) : 224;
    const ac = alignSize && Number(alignSize.c) ? Number(alignSize.c) : 3;
    if (!alignedRaw || alignedRaw.length < aw * ah * ac || ac !== 3) return null;

    const rgb224 = bgrToRgbUint8(alignedRaw);
    if (!rgb224) return null;
    const aligned = sharp(rgb224, { raw: { width: aw, height: ah, channels: 3 } });
    let data;
    let info;
    try {
      ({ data, info } = await aligned.clone().resize(FEAT_INPUT_SIZE, FEAT_INPUT_SIZE, { fit: 'cover', kernel: sharp.kernel.cubic }).raw().toBuffer({ resolveWithObject: true }));
    } catch {
      ({ data, info } = await aligned
        .clone()
        .resize(FEAT_INPUT_SIZE, FEAT_INPUT_SIZE, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 1 }, kernel: sharp.kernel.cubic })
        .raw()
        .toBuffer({ resolveWithObject: true }));
    }
    const rgb112 = data;
    if (FEAT_LUMA_NORM_ENABLED) {
      lumaNormalizeRgbInplace(rgb112, FEAT_LUMA_NORM_MODE, FEAT_LUMA_TARGET_MEAN, FEAT_LUMA_TARGET_STD, FEAT_LUMA_EPS);
    }
    const mean = [FEAT_MEAN, FEAT_MEAN, FEAT_MEAN];
    const std = [FEAT_STD, FEAT_STD, FEAT_STD];
    const chw = chwFromHwcUint8(rgb112, info.height, info.width, FEAT_ORDER, mean, std, 1);
    return { chw };
  }

  async extractFaceFeatures(imagePath) {
    await this.init();
    if (!imagePath || !fs.existsSync(imagePath)) return [];
    const { rotatedMeta, faces } = await this.detectFaces(imagePath);
    if (!faces || faces.length === 0) return [];
    const results = [];
    for (const face of faces) {
      const box = face && face.box ? face.box : null;
      if (!box) continue;
      if (!isFaceBoxAcceptable(box, rotatedMeta)) continue;
      let aligned;
      try {
        aligned = await this._extractAlignedFace112(face);
      } catch (err) {
        Logger.error('❌ Align face extract error:', err);
        aligned = null;
      }
      if (!aligned) continue;

      let featInput = null;
      let out = null;
      let emb = null;

      try {
        featInput = new onnx.Tensor('float32', aligned.chw, [1, 3, FEAT_INPUT_SIZE, FEAT_INPUT_SIZE]);
        const featInputName = this._featInputName || 'input.1';
        out = await this._sessions.feat.run({ [featInputName]: featInput });
        const outName = this._featOutputName || '1333';
        const vec = out && out[outName] && out[outName].data ? out[outName].data : null;
        if (vec && vec.length === 512) {
          emb = normalizeL2(vec);
        }
      } catch (err) {
        Logger.error('❌ Face feature extract error:', err);
      } finally {
        // 确保释放 featInput
        if (featInput) {
          try {
            featInput.dispose();
          } catch (e) {}
          featInput = null;
        }
        // 确保释放 out
        if (out) {
          try {
            Object.values(out).forEach(tensor => tensor.dispose());
          } catch (e) {}
          out = null;
        }
        // 释放 aligned 数据引用
        if (aligned) {
          aligned.chw = null;
          aligned = null;
        }
      }

      if (!emb) continue;
      const quality = Math.max(0, Math.min(100, Math.round((Number(box.score) || 0) * 100)));

      results.push({
        box,
        feature: emb,
        qualityScore: quality,
      });
    }
    return results;
  }
}

let singleton = null;
async function getFaceEngine() {
  if (singleton) return singleton;
  await remoteAssets.ensureBundle('onnx_models.faces');
  const eng = new FaceEngine();
  await eng.init();
  singleton = eng;
  return singleton;
}

module.exports = {
  getFaceEngine,
  bufferToFloat32,
  float32ToBuffer,
  normalizeL2,
};
