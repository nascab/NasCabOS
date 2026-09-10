/**
 * 终端模块数据模型（对齐 Flutter xterm 终端的 UI 配置与缓冲行结构）：
 * - TerminalUiConfig：前景/背景/光标颜色、字号、行高、光标样式与闪烁（持久化到 Preferences）
 * - TerminalLine：单行终端输出（简化渲染：整行单色 + 粗体，SGR 按 Flutter TerminalTheme 调色板取色）
 * - TerminalLineSource：LazyForEach 虚拟化数据源（支持最多 10000 行滚动缓冲）
 */

/** 滚动缓冲上限（对齐 Flutter Terminal(maxLines: 10000)） */
export const TERMINAL_MAX_LINES: number = 10000;

/** 默认前景/背景色（对齐 TerminalUiConfig.defaults） */
export const TERMINAL_DEFAULT_FG: string = '#E6E6E6';
export const TERMINAL_DEFAULT_BG: string = '#0B0B0B';

/** 复制到剪贴板的缓冲行数上限（防止超长文本阻塞） */
export const TERMINAL_COPY_MAX_LINES: number = 500;

const ANSI_PALETTE: string[] = [
  '#000000', // 0 black
  '#CD3131', // 1 red
  '#0DBC79', // 2 green
  '#E5E510', // 3 yellow
  '#2472C8', // 4 blue
  '#BC3FBC', // 5 magenta
  '#11A8CD', // 6 cyan
  '#E5E5E5', // 7 white
  '#666666', // 8 brightBlack
  '#FF0000', // 9 brightRed
  '#14CE14', // 10 brightGreen
  '#FFFF00', // 11 brightYellow
  '#3B8EEA', // 12 brightBlue
  '#D670D6', // 13 brightMagenta
  '#29B8DB', // 14 brightCyan
  '#FFFFFF' // 15 brightWhite
];

/** ANSI SGR 颜色码 → 调色板颜色（index 0-15，越界返回 ''） */
export function ansiFgColor(index: number): string {
  if (index < 0 || index >= ANSI_PALETTE.length) {
    return '';
  }
  return ANSI_PALETTE[index];
}

/** 光标样式 → 占位字形（block ▏bar ▏underline，对齐 Flutter cursorStyle） */
export function cursorGlyph(style: string): string {
  const v = style.trim().toLowerCase();
  if (v === 'underline') {
    return '▁';
  }
  if (v === 'bar' || v === 'line' || v === 'verticalbar') {
    return '▏';
  }
  return '█';
}

function isHexChar(ch: string): boolean {
  return (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F');
}

/** 终端 UI 配置（对齐 Flutter TerminalUiConfig；字段只读，修改时整体替换实例） */
export class TerminalUiConfig {
  readonly foreground: string;
  readonly background: string;
  readonly cursor: string;
  readonly fontSize: number;
  readonly lineHeight: number;
  readonly fontFamily: string;
  readonly cursorStyle: string;
  readonly cursorBlink: boolean;

  constructor(foreground: string, background: string, cursor: string, fontSize: number,
    lineHeight: number, fontFamily: string, cursorStyle: string, cursorBlink: boolean) {
    this.foreground = foreground;
    this.background = background;
    this.cursor = cursor;
    this.fontSize = fontSize;
    this.lineHeight = lineHeight;
    this.fontFamily = fontFamily;
    this.cursorStyle = cursorStyle;
    this.cursorBlink = cursorBlink;
  }

  static defaults(): TerminalUiConfig {
    return new TerminalUiConfig('#e6e6e6', '#0b0b0b', '#e6e6e6', 14, 1.0, 'RobotoMono', 'block', true);
  }

  toJson(): Record<string, string | number | boolean> {
    const obj: Record<string, string | number | boolean> = {
      'foreground': this.foreground,
      'background': this.background,
      'cursor': this.cursor,
      'fontSize': this.fontSize,
      'lineHeight': this.lineHeight,
      'fontFamily': this.fontFamily,
      'cursorStyle': this.cursorStyle,
      'cursorBlink': this.cursorBlink
    };
    return obj;
  }

  static tryFromJson(raw: Object | undefined | null): TerminalUiConfig | undefined {
    if (raw === undefined || raw === null) {
      return undefined;
    }
    const obj = raw as Record<string, Object>;
    const s = (v: Object | undefined): string => {
      return v === undefined || v === null ? '' : `${v}`;
    };
    const i = (v: Object | undefined): number => {
      const n = parseInt(s(v));
      return Number.isNaN(n) ? -1 : n;
    };
    const d = (v: Object | undefined): number => {
      const n = parseFloat(s(v));
      return Number.isNaN(n) ? -1 : n;
    };
    const b = (v: Object | undefined): boolean => {
      return v === true || s(v).toLowerCase() === 'true';
    };

    const fontSize = i(obj['fontSize']);
    const lineHeight = d(obj['lineHeight']);
    const fg = s(obj['foreground']).trim();
    const bg = s(obj['background']).trim();
    const cursor = s(obj['cursor']).trim();
    const fontFamily = s(obj['fontFamily']).trim();
    const cursorStyle = s(obj['cursorStyle']).trim();

    if (fg.length === 0 || bg.length === 0 || cursor.length === 0) {
      return undefined;
    }
    if (fontSize < 8 || fontSize > 24) {
      return undefined;
    }
    if (lineHeight <= 0) {
      return undefined;
    }
    return new TerminalUiConfig(
      fg, bg, cursor, fontSize, lineHeight,
      fontFamily.length === 0 ? 'RobotoMono' : fontFamily,
      cursorStyle.length === 0 ? 'block' : cursorStyle,
      b(obj['cursorBlink']));
  }

  static tryFromJsonString(text: string): TerminalUiConfig | undefined {
    try {
      return TerminalUiConfig.tryFromJson(JSON.parse(text) as Object);
    } catch (_e) {
      return undefined;
    }
  }

  /** 解析 #RRGGBB / #AARRGGBB，非法返回 ''（对齐 Flutter parseColor，仅接受 6/8 位 hex） */
  static parseColor(raw: string): string {
    const s = raw.trim();
    if (s.length === 0) {
      return '';
    }
    const hex = s.startsWith('#') ? s.substring(1) : s;
    if (hex.length !== 6 && hex.length !== 8) {
      return '';
    }
    for (let i = 0; i < hex.length; i++) {
      if (!isHexChar(hex.charAt(i))) {
        return '';
      }
    }
    return `#${hex.toUpperCase()}`;
  }

  /** 解析颜色并带兜底（对齐 Flutter parseColor(fallback:)） */
  static parseColorWithFallback(raw: string, fallback: string): string {
    const v = TerminalUiConfig.parseColor(raw);
    return v.length > 0 ? v : fallback;
  }
}

/** 单行终端输出（提交后的完整行；color 为 '' 时使用当前前景色） */
export class TerminalLine {
  text: string;
  color: string;
  bold: boolean;

  constructor(text: string, color: string, bold: boolean) {
    this.text = text;
    this.color = color;
    this.bold = bold;
  }
}

/**
 * 终端行数据源（LazyForEach IDataSource）：仅追加 + 超限裁剪，
 * 由控制器在 50ms 批量 flush 时驱动增量回调，避免高频输出全量重建。
 */
export class TerminalLineSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private items: TerminalLine[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): TerminalLine {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener): boolean => l !== listener);
  }

  /** 整体重置（清屏/裁剪时使用，走 onDataReloaded） */
  reset(items: TerminalLine[]): void {
    this.items = items.slice();
    this.listeners.forEach((l: DataChangeListener): void => {
      l.onDataReloaded();
    });
  }

  /** 追加一行（走 onDataAdd 增量刷新） */
  append(line: TerminalLine): void {
    this.items.push(line);
    const idx = this.items.length - 1;
    this.listeners.forEach((l: DataChangeListener): void => {
      l.onDataAdd(idx);
    });
  }

  /** 超出上限时裁掉最早的行（走 onDataReloaded） */
  trimTo(max: number): void {
    if (this.items.length <= max) {
      return;
    }
    const overflow = this.items.length - max;
    this.items.splice(0, overflow);
    this.listeners.forEach((l: DataChangeListener): void => {
      l.onDataReloaded();
    });
  }
}
