/**
 * 终端模块数据模型（对齐 Flutter xterm 终端的 UI 配置结构）：
 * - TerminalUiConfig：前景/背景/光标颜色、字号、行高、光标样式与闪烁（持久化到 Preferences）
 * - 终端渲染由 Web xterm.js 承担，本文件仅承载 UI 配置
 */

/** 默认前景/背景色（对齐 TerminalUiConfig.defaults） */
export const TERMINAL_DEFAULT_FG: string = '#E6E6E6';
export const TERMINAL_DEFAULT_BG: string = '#0B0B0B';

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
    return new TerminalUiConfig('#e6e6e6', '#0b0b0b', '#e6e6e6', 14, 1.0, 'HarmonyOS Sans Mono', 'block', true);
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
      fontFamily.length === 0 ? 'HarmonyOS Sans Mono' : fontFamily,
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
