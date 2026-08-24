// 多语言翻译文件导出
// Export all language translations
// Language order: en-US, zh-CN, ja-JP, ko-KR, es-ES, pt-BR, fr-FR, de-DE, ru-RU, id-ID, vi-VN, th-TH, ar-SA

import enUS from './en-US.js';
import zhCN from './zh-CN.js';
import jaJP from './ja-JP.js';
import koKR from './ko-KR.js';
import esES from './es-ES.js';
import ptBR from './pt-BR.js';
import frFR from './fr-FR.js';
import deDE from './de-DE.js';
import ruRU from './ru-RU.js';
import idID from './id-ID.js';
import viVN from './vi-VN.js';
import thTH from './th-TH.js';
import arSA from './ar-SA.js';

// 所有支持的翻译字典
export const I18N_DICT = {
  'en-US': enUS,
  'zh-CN': zhCN,
  'ja-JP': jaJP,
  'ko-KR': koKR,
  'es-ES': esES,
  'pt-BR': ptBR,
  'fr-FR': frFR,
  'de-DE': deDE,
  'ru-RU': ruRU,
  'id-ID': idID,
  'vi-VN': viVN,
  'th-TH': thTH,
  'ar-SA': arSA,
};

// 默认导出
export default I18N_DICT;
