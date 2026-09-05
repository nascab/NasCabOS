import { i18n } from '@kit.LocalizationKit';
import { AppEventBus } from '../../common/AppEventBus';
import { PreferencesStore } from '../storage/PreferencesStore';
import { CacheKeys } from '../storage/CacheKeys';
import { L10n } from './L10n';

export class LanguageOption {
  value: string;
  label: string;

  constructor(value: string, label: string) {
    this.value = value;
    this.label = label;
  }
}

/**
 * 全局语言服务（对齐 Flutter LanguageService）。
 * 语言包资源与 Flutter 完全一致，切换后通过 localeChanged 事件通知界面刷新。
 */
export class LanguageService {
  private static instance: LanguageService | undefined = undefined;
  static readonly EVENT_LOCALE_CHANGED: string = 'localeChanged';

  private static readonly supportedLocales: Map<string, string> = new Map([
    ['zh_CN', '简体中文'],
    ['en_US', 'English'],
    ['fr_FR', 'Français'],
    ['de_DE', 'Deutsch'],
    ['pt_BR', 'Português'],
    ['ja_JP', '日本語'],
    ['ru_RU', 'Русский'],
    ['th_TH', 'ไทย'],
    ['ko_KR', '한국어'],
    ['es_ES', 'Español'],
    ['ar_AR', 'العربية'],
    ['vi_VN', 'Tiếng Việt'],
    ['id_ID', 'Bahasa Indonesia'],
  ]);

  private locale: string = 'zh_CN';

  static getInstance(): LanguageService {
    if (!LanguageService.instance) {
      LanguageService.instance = new LanguageService();
    }
    return LanguageService.instance;
  }

  static isSupported(localeCode: string): boolean {
    return LanguageService.supportedLocales.has(localeCode);
  }

  get currentLocale(): string {
    return this.locale;
  }

  get currentLanguageName(): string {
    return LanguageService.supportedLocales.get(this.currentLocale) ?? '未知语言';
  }

  /** 启动初始化：用户保存的语言优先，否则跟随系统（对齐 Flutter init） */
  async init(): Promise<void> {
    const saved = PreferencesStore.getInstance().getString(CacheKeys.SELECTED_LANGUAGE, '');
    if (saved && LanguageService.isSupported(saved)) {
      this.locale = saved;
    } else {
      this.locale = LanguageService.detectSystemLanguage();
    }
    L10n.setLocale(this.locale);
  }

  /** 检测系统语言并匹配到支持的语言（对齐 Flutter _detectSystemLanguage） */
  static detectSystemLanguage(): string {
    let language = '';
    let region = '';
    try {
      const sysLocale = i18n.System.getSystemLanguage();
      const m = sysLocale.match(/^([a-zA-Z]{2,3})(?:[-_]([a-zA-Z]{2,4}))?/);
      if (m) {
        language = m[1].toLowerCase();
        region = (m[2] ?? '').toUpperCase();
      }
    } catch (e) {
      return 'zh_CN';
    }
    if (language.length === 0) {
      return 'zh_CN';
    }
    const fullMatch = `${language}_${region}`;
    if (region.length > 0 && LanguageService.supportedLocales.has(fullMatch)) {
      return fullMatch;
    }
    switch (language) {
      case 'zh': return 'zh_CN';
      case 'pt': return 'pt_BR';
      case 'es': return 'es_ES';
      case 'fr': return 'fr_FR';
      case 'de': return 'de_DE';
      case 'ja': return 'ja_JP';
      case 'ko': return 'ko_KR';
      case 'ru': return 'ru_RU';
      case 'th': return 'th_TH';
      case 'vi': return 'vi_VN';
      case 'id': return 'id_ID';
      case 'ar': return 'ar_AR';
      case 'en': return 'en_US';
      default: return 'en_US';
    }
  }

  /** 切换语言：持久化 + L10n 生效 + 广播刷新（对齐 Flutter changeLanguage） */
  async changeLanguage(localeCode: string): Promise<void> {
    if (!LanguageService.isSupported(localeCode) || localeCode === this.locale) {
      return;
    }
    this.locale = localeCode;
    await PreferencesStore.getInstance().setString(CacheKeys.SELECTED_LANGUAGE, localeCode);
    L10n.setLocale(localeCode);
    AppEventBus.emit(LanguageService.EVENT_LOCALE_CHANGED, localeCode);
  }

  /** 完整语言选项列表（顺序与 Flutter getFullLanguageOptions 一致） */
  static getFullLanguageOptions(): LanguageOption[] {
    return [
      new LanguageOption('en_US', 'English'),
      new LanguageOption('zh_CN', '简体中文'),
      new LanguageOption('ja_JP', '日本語'),
      new LanguageOption('ko_KR', '한국어'),
      new LanguageOption('es_ES', 'Español'),
      new LanguageOption('pt_BR', 'Português (Brasil)'),
      new LanguageOption('fr_FR', 'Français'),
      new LanguageOption('de_DE', 'Deutsch'),
      new LanguageOption('ru_RU', 'Русский'),
      new LanguageOption('id_ID', 'Bahasa Indonesia'),
      new LanguageOption('vi_VN', 'Tiếng Việt'),
      new LanguageOption('th_TH', 'ไทย'),
      new LanguageOption('ar_AR', 'العربية'),
    ];
  }
}
