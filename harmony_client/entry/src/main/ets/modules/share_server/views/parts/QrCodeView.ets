import { util } from '@kit.ArkTS';

/**
 * 内建 QR Code 生成器（替代 Flutter qr_flutter，项目无三方 QR 依赖）：
 * - 字节模式 + 纠错级别 M + 版本 1-40 自动选择
 * - 8 种掩码按标准罚分（连续/2x2/类定位图形/黑白平衡）自动择优
 * 输出布尔模块矩阵，true = 深色。
 */

/** 纠错级别 M：每块纠错码字数（下标 = 版本，0 位占位） */
const ECC_PER_BLOCK_M: number[] = [
  -1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26,
  26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28,
  28, 28, 28
];

/** 纠错级别 M：块数（下标 = 版本，0 位占位） */
const NUM_BLOCKS_M: number[] = [
  -1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17,
  18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49
];

function getBit(bits: number, i: number): boolean {
  return ((bits >>> i) & 1) !== 0;
}

/** GF(2^8) 乘法（生成多项式 0x11D） */
function gfMul(x: number, y: number): number {
  let z = 0;
  for (let i = 0; i < 8; i++) {
    z = (z << 1) ^ ((z >>> 7) * 0x11D);
    z ^= ((y >>> i) & 1) * x;
  }
  return z & 0xFF;
}

/** RS 生成多项式（降幂系数，长度 = degree） */
function rsDivisor(degree: number): number[] {
  const result: number[] = [];
  for (let i = 0; i < degree - 1; i++) {
    result.push(0);
  }
  result.push(1);
  let root = 1;
  for (let i = 0; i < degree; i++) {
    for (let j = 0; j < result.length; j++) {
      result[j] = gfMul(result[j], root);
      if (j + 1 < result.length) {
        result[j] ^= result[j + 1];
      }
    }
    root = gfMul(root, 0x02);
  }
  return result;
}

/** RS 余数（纠错码字） */
function rsRemainder(data: number[], divisor: number[]): number[] {
  const result: number[] = [];
  for (let i = 0; i < divisor.length; i++) {
    result.push(0);
  }
  for (let d = 0; d < data.length; d++) {
    const factor = data[d] ^ (result.shift() ?? 0);
    result.push(0);
    for (let i = 0; i < divisor.length; i++) {
      result[i] ^= gfMul(divisor[i], factor);
    }
  }
  return result;
}

function numRawDataModules(ver: number): number {
  let result = (16 * ver + 128) * ver + 64;
  if (ver >= 2) {
    const numAlign = Math.floor(ver / 7) + 2;
    result -= (25 * numAlign - 10) * numAlign - 55;
    if (ver >= 7) {
      result -= 36;
    }
  }
  return result;
}

function numDataCodewords(ver: number): number {
  return Math.floor(numRawDataModules(ver) / 8) - ECC_PER_BLOCK_M[ver] * NUM_BLOCKS_M[ver];
}

function alignPositions(ver: number): number[] {
  if (ver === 1) {
    return [];
  }
  const numAlign = Math.floor(ver / 7) + 2;
  const step = ver === 32 ? 26
    : Math.ceil((ver * 4 + 4) / (numAlign * 2 - 2)) * 2;
  const result: number[] = [6];
  for (let pos = ver * 4 + 17 - 7; result.length < numAlign; pos -= step) {
    result.unshift(pos);
  }
  return result;
}

class QrMatrix {
  readonly size: number;
  modules: boolean[][];
  private isFunction: boolean[][];

  constructor(ver: number) {
    this.size = ver * 4 + 17;
    this.modules = [];
    this.isFunction = [];
    for (let i = 0; i < this.size; i++) {
      this.modules.push(new Array<boolean>(this.size).fill(false));
      this.isFunction.push(new Array<boolean>(this.size).fill(false));
    }
  }

  setFn(x: number, y: number, dark: boolean): void {
    if (x < 0 || y < 0 || x >= this.size || y >= this.size) {
      return;
    }
    this.isFunction[y][x] = true;
    this.modules[y][x] = dark;
  }

  drawFinder(cx: number, cy: number): void {
    for (let dy = -4; dy <= 4; dy++) {
      for (let dx = -4; dx <= 4; dx++) {
        const dist = Math.max(Math.abs(dx), Math.abs(dy));
        this.setFn(cx + dx, cy + dy, dist !== 2 && dist !== 4);
      }
    }
  }

  drawAlign(cx: number, cy: number): void {
    for (let dy = -2; dy <= 2; dy++) {
      for (let dx = -2; dx <= 2; dx++) {
        this.setFn(cx + dx, cy + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
      }
    }
  }

  drawFormatBits(msk: number): void {
    // 纠错级别 M 的 formatBits = 0
    const data = msk;
    let rem = data;
    for (let i = 0; i < 10; i++) {
      rem = (rem << 1) ^ ((rem >>> 9) * 0x537);
    }
    const bits = ((data << 10) | rem) ^ 0x5412;
    for (let i = 0; i <= 5; i++) {
      this.setFn(8, i, getBit(bits, i));
    }
    this.setFn(8, 7, getBit(bits, 6));
    this.setFn(8, 8, getBit(bits, 7));
    this.setFn(7, 8, getBit(bits, 8));
    for (let i = 9; i < 15; i++) {
      this.setFn(14 - i, 8, getBit(bits, i));
    }
    for (let i = 0; i < 8; i++) {
      this.setFn(this.size - 1 - i, 8, getBit(bits, i));
    }
    for (let i = 8; i < 15; i++) {
      this.setFn(8, this.size - 15 + i, getBit(bits, i));
    }
    this.setFn(8, this.size - 8, true);
  }

  drawVersion(ver: number): void {
    if (ver < 7) {
      return;
    }
    let rem = ver;
    for (let i = 0; i < 12; i++) {
      rem = (rem << 1) ^ ((rem >>> 11) * 0x1F25);
    }
    const bits = (ver << 12) | rem;
    for (let i = 0; i < 18; i++) {
      const color = getBit(bits, i);
      const a = this.size - 11 + (i % 3);
      const b = Math.floor(i / 3);
      this.setFn(a, b, color);
      this.setFn(b, a, color);
    }
  }

  drawFunctionPatterns(ver: number): void {
    for (let i = 0; i < this.size; i++) {
      this.setFn(6, i, i % 2 === 0);
      this.setFn(i, 6, i % 2 === 0);
    }
    this.drawFinder(3, 3);
    this.drawFinder(this.size - 4, 3);
    this.drawFinder(3, this.size - 4);
    const pos = alignPositions(ver);
    for (let i = 0; i < pos.length; i++) {
      for (let j = 0; j < pos.length; j++) {
        const skip = (i === 0 && j === 0) || (i === 0 && j === pos.length - 1)
          || (i === pos.length - 1 && j === 0);
        if (!skip) {
          this.drawAlign(pos[i], pos[j]);
        }
      }
    }
    this.drawFormatBits(0);
    this.drawVersion(ver);
  }

  drawCodewords(data: number[]): void {
    let i = 0;
    for (let right = this.size - 1; right >= 1; right -= 2) {
      if (right === 6) {
        right = 5;
      }
      for (let vert = 0; vert < this.size; vert++) {
        for (let j = 0; j < 2; j++) {
          const x = right - j;
          const upward = ((right + 1) & 2) === 0;
          const y = upward ? this.size - 1 - vert : vert;
          if (!this.isFunction[y][x] && i < data.length * 8) {
            this.modules[y][x] = getBit(data[i >>> 3], 7 - (i & 7));
            i++;
          }
        }
      }
    }
  }

  applyMask(msk: number): void {
    for (let y = 0; y < this.size; y++) {
      for (let x = 0; x < this.size; x++) {
        let invert = false;
        if (msk === 0) {
          invert = (x + y) % 2 === 0;
        } else if (msk === 1) {
          invert = y % 2 === 0;
        } else if (msk === 2) {
          invert = x % 3 === 0;
        } else if (msk === 3) {
          invert = (x + y) % 3 === 0;
        } else if (msk === 4) {
          invert = (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0;
        } else if (msk === 5) {
          invert = (x * y) % 2 + (x * y) % 3 === 0;
        } else if (msk === 6) {
          invert = ((x * y) % 2 + (x * y) % 3) % 2 === 0;
        } else if (msk === 7) {
          invert = ((x + y) % 2 + (x * y) % 3) % 2 === 0;
        }
        if (!this.isFunction[y][x] && invert) {
          this.modules[y][x] = !this.modules[y][x];
        }
      }
    }
  }

  /** 单行/列连续同色罚分（规则 1） */
  private linePenalty(get: (i: number) => boolean): number {
    let p = 0;
    let run = 1;
    for (let i = 1; i < this.size; i++) {
      if (get(i) === get(i - 1)) {
        run++;
      } else {
        if (run >= 5) {
          p += run - 2;
        }
        run = 1;
      }
    }
    if (run >= 5) {
      p += run - 2;
    }
    return p;
  }

  /** 行/列中 1:1:3:1:1 定位图形（一侧 4 浅模块）罚分（规则 3） */
  private finderLinePenalty(get: (i: number) => boolean): number {
    let p = 0;
    const n = this.size;
    for (let s = 0; s + 10 < n; s++) {
      // [深,浅,深,深,深,浅,深] + 右侧 4 浅
      const a = get(s) && !get(s + 1) && get(s + 2) && get(s + 3) && get(s + 4)
        && !get(s + 5) && get(s + 6) && !get(s + 7) && !get(s + 8) && !get(s + 9) && !get(s + 10);
      // 左侧 4 浅 + [深,浅,深,深,深,浅,深]
      const b = !get(s) && !get(s + 1) && !get(s + 2) && !get(s + 3) && get(s + 4)
        && !get(s + 5) && get(s + 6) && get(s + 7) && get(s + 8) && !get(s + 9) && get(s + 10);
      if (a || b) {
        p += 40;
      }
    }
    return p;
  }

  penaltyScore(): number {
    const n = this.size;
    let result = 0;
    for (let y = 0; y < n; y++) {
      result += this.linePenalty((i: number): boolean => this.modules[y][i]);
      result += this.linePenalty((i: number): boolean => this.modules[i][y]);
      result += this.finderLinePenalty((i: number): boolean => this.modules[y][i]);
      result += this.finderLinePenalty((i: number): boolean => this.modules[i][y]);
    }
    for (let y = 0; y < n - 1; y++) {
      for (let x = 0; x < n - 1; x++) {
        const c = this.modules[y][x];
        if (c === this.modules[y][x + 1] && c === this.modules[y + 1][x]
          && c === this.modules[y + 1][x + 1]) {
          result += 3;
        }
      }
    }
    let dark = 0;
    for (let y = 0; y < n; y++) {
      for (let x = 0; x < n; x++) {
        if (this.modules[y][x]) {
          dark++;
        }
      }
    }
    const total = n * n;
    const k = Math.ceil(Math.abs(dark * 20 - total * 10) / total) - 1;
    result += Math.max(0, Math.min(9, k)) * 10;
    return result;
  }
}

/** 数据码字组装（字节模式 + 终止符 + 补齐填充） */
function encodeBytesToCodewords(bytes: number[], ver: number): number[] {
  const capBits = numDataCodewords(ver) * 8;
  const bits: number[] = [];
  const pushBits = (val: number, len: number): void => {
    for (let i = len - 1; i >= 0; i--) {
      bits.push((val >>> i) & 1);
    }
  };
  const cciBits = ver <= 9 ? 8 : 16;
  pushBits(0x4, 4);
  pushBits(bytes.length, cciBits);
  for (let i = 0; i < bytes.length; i++) {
    pushBits(bytes[i], 8);
  }
  const termLen = Math.min(4, capBits - bits.length);
  for (let i = 0; i < termLen; i++) {
    bits.push(0);
  }
  while (bits.length % 8 !== 0) {
    bits.push(0);
  }
  const padBytes: number[] = [0xEC, 0x11];
  for (let i = 0; bits.length < capBits; i++) {
    pushBits(padBytes[i % 2], 8);
  }
  const out: number[] = [];
  for (let i = 0; i < bits.length; i += 8) {
    let b = 0;
    for (let j = 0; j < 8; j++) {
      b = (b << 1) | bits[i + j];
    }
    out.push(b);
  }
  return out;
}

/** 分块纠错 + 交织（对齐 QR 规范） */
function addEccAndInterleave(data: number[], ver: number): number[] {
  const numBlocks = NUM_BLOCKS_M[ver];
  const blockEccLen = ECC_PER_BLOCK_M[ver];
  const rawCodewords = Math.floor(numRawDataModules(ver) / 8);
  const numShortBlocks = numBlocks - (rawCodewords % numBlocks);
  const shortBlockLen = Math.floor(rawCodewords / numBlocks);
  const blocks: number[][] = [];
  const div = rsDivisor(blockEccLen);
  let k = 0;
  for (let i = 0; i < numBlocks; i++) {
    const datLen = shortBlockLen - blockEccLen + (i < numShortBlocks ? 0 : 1);
    const dat: number[] = data.slice(k, k + datLen);
    k += dat.length;
    const ecc = rsRemainder(dat, div);
    if (i < numShortBlocks) {
      dat.push(0);
    }
    blocks.push(dat.concat(ecc));
  }
  const result: number[] = [];
  for (let i = 0; i < blocks[0].length; i++) {
    for (let j = 0; j < blocks.length; j++) {
      if (i !== shortBlockLen - blockEccLen || j >= numShortBlocks) {
        result.push(blocks[j][i]);
      }
    }
  }
  return result;
}

/** 生成 QR 模块矩阵；内容超长或编码失败返回 undefined */
export function buildQrMatrix(text: string): boolean[][] | undefined {
  try {
    const encoder = new util.TextEncoder();
    const raw: Uint8Array = encoder.encodeInto(text);
    const bytes: number[] = [];
    for (let i = 0; i < raw.length; i++) {
      bytes.push(raw[i]);
    }
    let ver = 0;
    for (let v = 1; v <= 40; v++) {
      const cciBits = v <= 9 ? 8 : 16;
      if (4 + cciBits + bytes.length * 8 <= numDataCodewords(v) * 8) {
        ver = v;
        break;
      }
    }
    if (ver === 0) {
      return undefined;
    }
    const m = new QrMatrix(ver);
    m.drawFunctionPatterns(ver);
    const dataCw = encodeBytesToCodewords(bytes, ver);
    m.drawCodewords(addEccAndInterleave(dataCw, ver));
    let bestMask = 0;
    let bestPenalty = Number.MAX_VALUE;
    for (let msk = 0; msk < 8; msk++) {
      m.applyMask(msk);
      m.drawFormatBits(msk);
      const p = m.penaltyScore();
      if (p < bestPenalty) {
        bestPenalty = p;
        bestMask = msk;
      }
      m.applyMask(msk);
    }
    m.applyMask(bestMask);
    m.drawFormatBits(bestMask);
    return m.modules;
  } catch (_e) {
    return undefined;
  }
}

/**
 * 二维码渲染组件（白底 + 4 模块静区，对齐 Flutter QrImageView 白底样式）。
 * text 变化时自动重绘。
 */
@ComponentV2
export struct QrCodeView {
  @Param text: string = '';
  @Param viewSize: number = 200;
  @Param darkColor: string = '#000000';
  @Param lightColor: string = '#FFFFFF';
  private context: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private ready: boolean = false;

  aboutToAppear(): void {
    this.ready = false;
  }

  @Monitor('text')
  onTextChange(): void {
    this.redraw();
  }

  private redraw(): void {
    if (this.ready) {
      this.draw();
    }
  }

  private draw(): void {
    const ctx = this.context;
    const side = this.viewSize;
    ctx.fillStyle = this.lightColor;
    ctx.fillRect(0, 0, side, side);
    const matrix = buildQrMatrix(this.text);
    if (matrix === undefined) {
      return;
    }
    const n = matrix.length + 8;
    const scale = Math.floor(side / n);
    if (scale < 1) {
      return;
    }
    const offset = Math.floor((side - scale * n) / 2);
    ctx.fillStyle = this.darkColor;
    for (let y = 0; y < matrix.length; y++) {
      const row = matrix[y];
      for (let x = 0; x < row.length; x++) {
        if (row[x]) {
          ctx.fillRect(offset + (x + 4) * scale, offset + (y + 4) * scale, scale, scale);
        }
      }
    }
  }

  build() {
    Canvas(this.context)
      .width(this.viewSize)
      .height(this.viewSize)
      .onReady(() => {
        this.ready = true;
        this.draw();
      })
  }
}
