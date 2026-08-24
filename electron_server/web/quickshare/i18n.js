(() => {
  window.QS_LOCALES = {};
  window.QS_I18N = null;

  // Language order: en-US, zh-CN, ja-JP, ko-KR, es-ES, pt-BR, fr-FR, de-DE, ru-RU, id-ID, vi-VN, th-TH, ar-SA
  const AVAILABLE_LOCALES = ['en-US', 'zh-CN', 'ja-JP', 'ko-KR', 'es-ES', 'pt-BR', 'fr-FR', 'de-DE', 'ru-RU', 'id-ID', 'vi-VN', 'th-TH', 'ar-SA'];

  const LOCALE_ALIASES = {
    zh: 'zh-CN',
    en: 'en-US',
    fr: 'fr-FR',
    ja: 'ja-JP',
    ko: 'ko-KR',
    vi: 'vi-VN',
    id: 'id-ID',
    de: 'de-DE',
    es: 'es-ES',
    pt: 'pt-BR',
    ru: 'ru-RU',
    ar: 'ar-SA',
    th: 'th-TH',
  };

  function normalizeLocale(locale) {
    if (!locale) return 'zh-CN';
    const normalized = String(locale).trim().toLowerCase();
    if (AVAILABLE_LOCALES.includes(normalized)) return normalized;
    if (LOCALE_ALIASES[normalized]) return LOCALE_ALIASES[normalized];
    for (const avail of AVAILABLE_LOCALES) {
      if (avail.toLowerCase().startsWith(normalized)) return avail;
    }
    return 'zh-CN';
  }

  async function loadLocale(locale) {
    const normalized = normalizeLocale(locale);
    if (window.QS_LOCALES[normalized]) return window.QS_LOCALES[normalized];
    try {
      const url = `./locales/${normalized}.json`;
      const resp = await fetch(url);
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      const data = await resp.json();
      window.QS_LOCALES[normalized] = data;
      return data;
    } catch (_) {
      if (normalized !== 'zh-CN') {
        console.warn(`Failed to load locale ${normalized}, falling back to zh-CN`);
        return loadLocale('zh-CN');
      }
      return { quickShare: {} };
    }
  }

  async function initI18N(initialLocale) {
    const defaultData = await loadLocale('zh-CN');
    const localeData = await loadLocale(initialLocale);
    const merged = {};
    const allKeys = new Set([...Object.keys(defaultData.quickShare || {}), ...Object.keys(localeData.quickShare || {})]);
    for (const key of allKeys) {
      if (localeData.quickShare && key in localeData.quickShare) {
        merged[key] = localeData.quickShare[key];
      } else if (defaultData.quickShare && key in defaultData.quickShare) {
        merged[key] = defaultData.quickShare[key];
      } else {
        merged[key] = key;
      }
    }
    window.QS_I18N = {
      locale: normalizeLocale(initialLocale),
      data: merged,
      fallback: defaultData.quickShare || {},
      t(key) {
        return (this.data && this.data[key]) || (this.fallback && this.fallback[key]) || key;
      },
      setLocale(newLocale) {
        const normalized = normalizeLocale(newLocale);
        if (normalized === this.locale) return Promise.resolve();
        return loadLocale(normalized).then(data => {
          const merged = {};
          const allKeys = new Set([...Object.keys(this.fallback), ...Object.keys(data.quickShare || {})]);
          for (const key of allKeys) {
            if (data.quickShare && key in data.quickShare) {
              merged[key] = data.quickShare[key];
            } else if (this.fallback && key in this.fallback) {
              merged[key] = this.fallback[key];
            } else {
              merged[key] = key;
            }
          }
          this.locale = normalized;
          this.data = merged;
        });
      },
      getAvailableLocales() {
        return AVAILABLE_LOCALES.slice();
      },
    };
    return window.QS_I18N;
  }

  window.QSLocales = {
    init: initI18N,
    load: loadLocale,
    normalize: normalizeLocale,
    getAvailableLocales: () => AVAILABLE_LOCALES.slice(),
  };
})();
