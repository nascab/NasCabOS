import { ThemeManager } from './ThemeManager';

/**
 * 主题色板：颜色值与 Flutter 端 core/theme/light_theme.dart、dark_theme.dart 一一对应。
 * - light: primary=blue.shade800(#1565C0), scaffold=#F5F5F5, card=#FFFFFF, onSurface=#333333
 * - dark:  primary=#007AFF, scaffold=#1A1A1A, card=#121212, surface=#2A2A2A, onSurface=白
 */
export class ThemePalette {
  /** 页面/脚手架背景（Flutter scaffoldBackgroundColor） */
  readonly pageBg: string;
  /** 卡片背景（Flutter cardColor） */
  readonly cardBg: string;
  /** surface 背景/弹窗背景（Flutter colorScheme.surface） */
  readonly surfaceBg: string;
  /** 主色（Flutter colorScheme.primary） */
  readonly primary: string;
  /** 主要文本色（Flutter colorScheme.onSurface） */
  readonly onSurface: string;
  /** 次要文本色（onSurface 60% 透明，Flutter subtitle 用法一致） */
  readonly subText: string;
  /** 提示/箭头图标色（onSurface 40% 透明） */
  readonly hint: string;
  /** 分割线颜色（Flutter dividerTheme） */
  readonly divider: string;
  /** 输入框填充色（Flutter inputDecorationTheme.fillColor） */
  readonly inputFill: string;
  /** 输入框边框色（Flutter enabledBorder borderSide） */
  readonly inputBorder: string;
  /** 主按钮背景（Flutter elevatedButtonTheme） */
  readonly buttonBg: string;
  /** 主按钮文字色 */
  readonly buttonText: string;
  /** 标题栏背景（Flutter appBarTheme.backgroundColor） */
  readonly appBarBg: string;
  /** 标题栏前景色（Flutter appBarTheme.foregroundColor） */
  readonly appBarFg: string;
  /** 错误色（Flutter colorScheme.error） */
  readonly error: string;
  /** 次要色（Flutter colorScheme.secondary） */
  readonly secondary: string;
  /** 状态栏文字颜色 */
  readonly statusBarContent: string;

  constructor(pageBg: string, cardBg: string, surfaceBg: string, primary: string,
    onSurface: string, subText: string, hint: string, divider: string,
    inputFill: string, inputBorder: string, buttonBg: string, buttonText: string,
    appBarBg: string, appBarFg: string, error: string, secondary: string,
    statusBarContent: string) {
    this.pageBg = pageBg;
    this.cardBg = cardBg;
    this.surfaceBg = surfaceBg;
    this.primary = primary;
    this.onSurface = onSurface;
    this.subText = subText;
    this.hint = hint;
    this.divider = divider;
    this.inputFill = inputFill;
    this.inputBorder = inputBorder;
    this.buttonBg = buttonBg;
    this.buttonText = buttonText;
    this.appBarBg = appBarBg;
    this.appBarFg = appBarFg;
    this.error = error;
    this.secondary = secondary;
    this.statusBarContent = statusBarContent;
  }
}

const LIGHT_PALETTE = new ThemePalette(
  '#F5F5F5', // scaffoldBackgroundColor (245,245,245)
  '#FFFFFF', // cardColor
  '#F5F5F5', // surface
  '#1565C0', // primary blue.shade800
  '#333333', // onSurface (51,51,51)
  '#99333333', // onSurface 60%
  '#66333333', // onSurface 40%
  '#E0E0E0', // divider grey.shade300
  '#F5F5F5', // inputFill grey.shade100
  '#BDBDBD', // inputBorder grey.shade400
  '#42A5F5', // elevatedButton blue.shade400
  '#FFFFFF',
  '#1565C0', // appBar blue.shade800
  '#FFFFFF',
  '#FF3B30',
  '#FFAB40', // orangeAccent
  '#000000'
);

const DARK_PALETTE = new ThemePalette(
  '#1A1A1A', // scaffoldBackgroundColor (26,26,26)
  '#121212', // cardColor (18,18,18)
  '#2A2A2A', // surface (42,42,42)
  '#007AFF', // primary (0,122,255)
  '#FFFFFF', // onSurface
  '#99FFFFFF', // onSurface 60%
  '#66FFFFFF', // onSurface 40%
  '#757575', // divider grey.shade600
  '#424242', // inputFill grey.shade800
  '#757575', // inputBorder grey.shade600
  '#1565C0', // elevatedButton blue.shade800
  '#FFFFFF',
  '#424242', // appBar grey.shade800
  '#FFFFFF',
  '#FF3B30',
  '#FB8C00', // orange.shade500
  '#FFFFFF'
);

/** 主题访问入口：全局任意位置获取当前色板，主题切换后重新调用即得新色。 */
export class AppTheme {
  static current(): ThemePalette {
    return ThemeManager.getInstance().isDark() ? DARK_PALETTE : LIGHT_PALETTE;
  }

  static isDark(): boolean {
    return ThemeManager.getInstance().isDark();
  }

  /** 十六进制颜色附加透明度：#RRGGBB → #AARRGGBB */
  static withAlpha(color: string, alpha: number): string {
    const c = color.replace('#', '');
    const a = Math.round(Math.min(1, Math.max(0, alpha)) * 255);
    const aa = a < 16 ? `0${a.toString(16)}` : a.toString(16);
    return `#${aa}${c.toUpperCase()}`;
  }
}
