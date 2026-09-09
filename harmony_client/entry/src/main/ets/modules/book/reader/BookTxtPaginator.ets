import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import measure, { MeasureOptions } from '@ohos.measure';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'BookTxtPaginator';

/** 单行渲染数据 */
export interface TxtLine {
  /** 行文本；空串表示空段落间隔 */
  text: string;
  /** 章节标题行 */
  isTitle: boolean;
  /** 段落首行 */
  isParaStart: boolean;
  /** 全文起始字符偏移（进度恢复用） */
  charStart: number;
}

/** 单页数据 */
export interface TxtPage {
  chapterIndex: number;
  lines: TxtLine[];
  /** 页首字符偏移 */
  charStart: number;
}

/** 阅读样式（对齐 Flutter ReadStyle 持久化字段） */
@ObservedV2
export class TxtReadStyle {
  @Trace fontSize: number = 16;
  @Trace textColor: string = '#000000';
  @Trace bgColor: string = '#FFFFFF';
  @Trace lineSpacing: number = 4;
  @Trace padL: number = 20;
  @Trace padT: number = 16;
  @Trace padR: number = 20;
  @Trace padB: number = 16;

  clone(): TxtReadStyle {
    const s = new TxtReadStyle();
    s.fontSize = this.fontSize;
    s.textColor = this.textColor;
    s.bgColor = this.bgColor;
    s.lineSpacing = this.lineSpacing;
    s.padL = this.padL;
    s.padT = this.padT;
    s.padR = this.padR;
    s.padB = this.padB;
    return s;
  }

  static fromJson(obj: Object | undefined | null): TxtReadStyle {
    const s = new TxtReadStyle();
    if (obj === undefined || obj === null) {
      return s;
    }
    const m = obj as Record<string, Object>;
    s.fontSize = TxtReadStyle.numOf(m['fontSize'], s.fontSize);
    s.textColor = TxtReadStyle.colorOf(m['textColor'], s.textColor);
    s.bgColor = TxtReadStyle.colorOf(m['bgColor'], s.bgColor);
    s.lineSpacing = TxtReadStyle.numOf(m['lineSpacing'], s.lineSpacing);
    s.padL = TxtReadStyle.numOf(m['paddingL'], s.padL);
    s.padT = TxtReadStyle.numOf(m['paddingT'], s.padT);
    s.padR = TxtReadStyle.numOf(m['paddingR'], s.padR);
    s.padB = TxtReadStyle.numOf(m['paddingB'], s.padB);
    return s;
  }

  toJson(): Record<string, Object> {
    const m: Record<string, Object> = {};
    m['fontSize'] = this.fontSize;
    m['textColor'] = TxtReadStyle.argbOf(this.textColor);
    m['bgColor'] = TxtReadStyle.argbOf(this.bgColor);
    m['lineSpacing'] = this.lineSpacing;
    m['wordSpacing'] = 0;
    m['paddingL'] = this.padL;
    m['paddingT'] = this.padT;
    m['paddingR'] = this.padR;
    m['paddingB'] = this.padB;
    return m;
  }

  private static numOf(v: Object | undefined, fallback: number): number {
    if (v === undefined || v === null) {
      return fallback;
    }
    const n = Number(`${v}`);
    return Number.isNaN(n) ? fallback : n;
  }

  /** Flutter 颜色 int（ARGB）转 #RRGGBB */
  private static colorOf(v: Object | undefined, fallback: string): string {
    const n = TxtReadStyle.numOf(v, -1);
    if (n < 0) {
      return fallback;
    }
    const rgb = Math.floor(n) & 0xFFFFFF;
    return `#${rgb.toString(16).padStart(6, '0')}`;
  }

  /** #RRGGBB 转 Flutter 颜色 int（ARGB，Alpha=FF） */
  private static argbOf(color: string): number {
    const hex = color.replace('#', '');
    const parsed = parseInt(hex, 16);
    if (Number.isNaN(parsed)) {
      return 0xFF000000;
    }
    return 0xFF000000 | (parsed & 0xFFFFFF);
  }
}

/**
 * TXT 分页引擎：
 * - 本地文件读取 + 编码检测（BOM/UTF-8 校验 → utf-8 / gbk）
 * - 章节切分（第 x 章 / Chapter n 等正则，章节起新页）
 * - measure 字符宽度缓存 + 贪心换行 + 按高度分页
 * - 页首字符偏移：样式变化重排后可按偏移恢复阅读位置
 */
export class BookTxtPaginator {
  content: string = '';
  /** 每章起始字符偏移（含 0） */
  chapterStarts: number[] = [];
  chapterTitles: string[] = [];
  pages: TxtPage[] = [];
  /** 实际使用的解码编码（'utf-8' | 'gbk'） */
  resolvedEncoding: string = 'utf-8';
  /** 内容是否为空（打开失败） */
  isEmpty: boolean = true;

  /** 读取本地文件字节 */
  static async readFileBytes(path: string): Promise<Uint8Array> {
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const st = fs.statSync(file.fd);
      const size = Math.min(st.size, 64 * 1024 * 1024);
      const out = new Uint8Array(size);
      const chunk = 1024 * 1024;
      let read = 0;
      while (read < size) {
        const len = Math.min(chunk, size - read);
        const buf = new ArrayBuffer(len);
        const n = fs.readSync(file.fd, buf, { offset: read, length: len });
        if (n <= 0) {
          break;
        }
        out.set(new Uint8Array(buf.slice(0, n)), read);
        read += n;
      }
      return read === size ? out : out.slice(0, read);
    } finally {
      if (file !== undefined) {
        try {
          fs.closeSync(file);
        } catch (_e) {
        }
      }
    }
  }

  /** 编码检测：BOM → 严格 UTF-8 校验 → gbk */
  static detectEncoding(bytes: Uint8Array): 'utf-8' | 'gbk' {
    const n = bytes.length;
    if (n >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) {
      return 'utf-8';
    }
    if (n >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) {
      return 'utf-8'; // UTF-16LE 少见，退化为 utf-8 解码（BOM 残留由解码容错）
    }
    // 严格 UTF-8 序列校验
    let i = 0;
    while (i < n) {
      const b = bytes[i];
      let need = 0;
      if (b < 0x80) {
        need = 0;
      } else if ((b & 0xE0) === 0xC0) {
        need = 1;
      } else if ((b & 0xF0) === 0xE0) {
        need = 2;
      } else if ((b & 0xF8) === 0xF0) {
        need = 3;
      } else {
        return 'gbk';
      }
      if (i + need >= n + 1 && need > 0) {
        return 'gbk';
      }
      for (let k = 1; k <= need; k++) {
        if (i + k >= n || (bytes[i + k] & 0xC0) !== 0x80) {
          return 'gbk';
        }
      }
      i += need + 1;
    }
    return 'utf-8';
  }

  /** 解码全文（encoding: auto/utf8/gbk） */
  decode(encoding: string): boolean {
    if (this.rawBytes.length === 0) {
      this.isEmpty = true;
      return false;
    }
    let enc = encoding.trim().toLowerCase();
    if (enc.length === 0 || enc === 'auto') {
      enc = BookTxtPaginator.detectEncoding(this.rawBytes);
    } else if (enc === 'utf8') {
      enc = 'utf-8';
    }
    try {
      const decoder = util.TextDecoder.create(enc === 'gbk' ? 'gbk' : 'utf-8');
      // 去 UTF-8 BOM
      let data = this.rawBytes;
      if (data.length >= 3 && data[0] === 0xEF && data[1] === 0xBB && data[2] === 0xBF) {
        data = data.slice(3);
      }
      this.content = decoder.decodeWithStream(data);
    } catch (e) {
      hilog.error(0x0000, TAG, 'decode failed: %{public}s', JSON.stringify(e));
      // gbk 失败回退 utf-8
      try {
        this.content = util.TextDecoder.create('utf-8').decodeWithStream(this.rawBytes);
      } catch (_e) {
        this.content = '';
      }
    }
    this.resolvedEncoding = enc;
    this.isEmpty = this.content.length === 0;
    return !this.isEmpty;
  }

  private rawBytes: Uint8Array = new Uint8Array(0);

  /** 加载本地文件并解码（返回是否成功） */
  async load(localPath: string, encoding: string): Promise<boolean> {
    try {
      this.rawBytes = await BookTxtPaginator.readFileBytes(localPath);
    } catch (e) {
      hilog.error(0x0000, TAG, 'read file failed: %{public}s', JSON.stringify(e));
      this.rawBytes = new Uint8Array(0);
    }
    return this.decode(encoding);
  }

  /** 章节切分：命中标题行的段落开启新章 */
  splitChapters(): void {
    this.chapterStarts = [];
    this.chapterTitles = [];
    if (this.content.length === 0) {
      return;
    }
    this.chapterStarts.push(0);
    this.chapterTitles.push('');
    const re = BookTxtPaginator.chapterRegex();
    // 逐段扫描（按 \n），跟踪字符偏移
    let offset = 0;
    const lines = this.content.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const raw = lines[i];
      const text = raw.replace(/\r$/, '').trim();
      if (text.length > 0 && text.length <= 60 && re.test(text)) {
        // 章标题（行首偏移）
        this.chapterStarts.push(offset);
        this.chapterTitles.push(text);
      }
      offset += raw.length + 1;
    }
  }

  private static chapterRegexInstance: RegExp | undefined = undefined;

  private static chapterRegex(): RegExp {
    if (BookTxtPaginator.chapterRegexInstance === undefined) {
      BookTxtPaginator.chapterRegexInstance = new RegExp(
        '^(第\\s*[0-9０-９一二两三四五六七八九十百千万零〇]{1,7}\\s*[章节卷回部集幅篇话話][^。\\n]{0,30}|' +
        '(Chapter|CHAPTER)\\s+([0-9]+|[IVXLC]+).{0,30}|' +
        '序章|楔子|前言|引子|后记|尾声|番外|终章).{0,20}$');
    }
    return BookTxtPaginator.chapterRegexInstance;
  }

  /** 行高（与页面渲染一致） */
  static lineHeightOf(style: TxtReadStyle, isTitle: boolean): number {
    const fs = isTitle ? style.fontSize + 2 : style.fontSize;
    return Math.ceil(fs * 1.35 + style.lineSpacing);
  }

  /**
   * 分页（同步，大文本约数百毫秒）。
   * 章节 = 独立分页序列（章首起新页）。
   */
  paginate(style: TxtReadStyle): void {
    const t0 = Date.now();
    this.pages = [];
    if (this.content.length === 0) {
      return;
    }
    // 统一外部通过 setViewport 传入
    const width = this.viewportW;
    const height = this.viewportH;
    if (width <= 0 || height <= 0) {
      return;
    }
    const usableW = width - style.padL - style.padR - Math.ceil(style.fontSize * 0.2);
    const usableH = height - style.padT - style.padB;
    if (usableW <= 0 || usableH <= 0) {
      return;
    }
    const widthCache = new Map<string, number>();

    const charWidth = (ch: string): number => {
      const cached = widthCache.get(ch);
      if (cached !== undefined) {
        return cached;
      }
      let w = 0;
      try {
        const opts: MeasureOptions = { textContent: ch, fontSize: style.fontSize };
        w = Math.ceil(measure.measureText(opts));
      } catch (_e) {
        w = 0;
      }
      if (w <= 0) {
        w = style.fontSize; // 兜底
      }
      widthCache.set(ch, w);
      return w;
    };

    const startNewPage = (chapterIndex: number, charStart: number): TxtPage => {
      const p: TxtPage = { chapterIndex: chapterIndex, lines: [], charStart: charStart };
      this.pages.push(p);
      return p;
    };

    for (let ci = 0; ci < this.chapterStarts.length; ci++) {
      const cs = this.chapterStarts[ci];
      const ce = ci + 1 < this.chapterStarts.length ? this.chapterStarts[ci + 1] : this.content.length;
      let page = startNewPage(ci, cs);
      let y = 0;
      // 章节标题行
      const chapterTitle = this.chapterTitles[ci];
      if (chapterTitle.length > 0) {
        page.lines.push({ text: chapterTitle, isTitle: true, isParaStart: true, charStart: cs });
        y += BookTxtPaginator.lineHeightOf(style, true) + Math.ceil(style.fontSize * 0.6);
      }
      // 段落遍历
      let pos = cs;
      const body = this.content.substring(cs, ce);
      const paras = body.split('\n');
      for (let pi = 0; pi < paras.length; pi++) {
        const para = paras[pi].replace(/\r$/, '');
        const paraCharStart = pos;
        pos += paras[pi].length + 1;
        if (para.trim().length === 0) {
          // 空段落：半行间隔
          y += Math.ceil(BookTxtPaginator.lineHeightOf(style, false) * 0.45);
          if (y > usableH) {
            page = startNewPage(ci, paraCharStart);
            y = 0;
          }
          continue;
        }
        // 贪心换行（拉丁文优先在空格/标点断行，避免单词被硬切）
        const chars = Array.from(para);
        let lineBuf = '';
        let lineW = 0;
        let lineStart = 0; // 当前行首字符相对段落首字符下标
        let lastBreak = -1; // 行内最后一个可断点下标（含断点字符）
        for (let k = 0; k < chars.length; k++) {
          const ch = chars[k];
          const w = charWidth(ch);
          if (lineW + w > usableW && lineBuf.length > 0) {
            let lineText = lineBuf;
            let consumed = lineBuf.length;
            if (lastBreak > 0 && lastBreak < lineBuf.length) {
              lineText = lineBuf.substring(0, lastBreak);
              consumed = lastBreak + 1;
            }
            if (y + BookTxtPaginator.lineHeightOf(style, false) > usableH) {
              page = startNewPage(ci, paraCharStart + lineStart);
              y = 0;
            }
            page.lines.push({
              text: lineText, isTitle: false,
              isParaStart: lineStart === 0, charStart: paraCharStart + lineStart
            });
            y += BookTxtPaginator.lineHeightOf(style, false);
            lineStart += consumed;
            lineBuf = lineBuf.substring(consumed);
            lineW = 0;
            const rest = Array.from(lineBuf);
            for (const rc of rest) {
              lineW += charWidth(rc);
            }
            lastBreak = -1;
          }
          lineBuf += ch;
          lineW += w;
          if (BookTxtPaginator.isBreakChar(ch)) {
            lastBreak = lineBuf.length;
          }
        }
        if (lineBuf.length > 0 || chars.length === 0) {
          if (y + BookTxtPaginator.lineHeightOf(style, false) > usableH) {
            page = startNewPage(ci, paraCharStart + lineStart);
            y = 0;
          }
          page.lines.push({
            text: lineBuf, isTitle: false,
            isParaStart: lineStart === 0, charStart: paraCharStart + lineStart
          });
          y += BookTxtPaginator.lineHeightOf(style, false);
        }
        // 段间距
        y += Math.ceil(style.fontSize * 0.35);
      }
    }
    hilog.info(0x0000, TAG, 'paginate done: %{public}d pages, %{public}dms',
      this.pages.length, Date.now() - t0);
  }

  private static isBreakChar(ch: string): boolean {
    return ch === ' ' || ch === ',' || ch === '.' || ch === '，' || ch === '。' || ch === '；' || ch === '、';
  }

  private viewportW: number = 0;
  private viewportH: number = 0;

  setViewport(width: number, height: number): void {
    this.viewportW = width;
    this.viewportH = height;
  }

  /** 按字符偏移定位页下标（二分） */
  findPageByCharOffset(offset: number): number {
    if (this.pages.length === 0) {
      return 0;
    }
    let lo = 0;
    let hi = this.pages.length - 1;
    let ans = 0;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      if (this.pages[mid].charStart <= offset) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }
}
