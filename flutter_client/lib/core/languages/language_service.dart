import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Web 端按需加载：使用 deferred 拆包，切换语言时再加载对应语言文件
import 'en_us.dart' deferred as en_us;
import 'zh_cn.dart' deferred as zh_cn;
import 'fr_fr.dart' deferred as fr_fr;
import 'de_de.dart' deferred as de_de;
import 'pt_br.dart' deferred as pt_br;
import 'ja_jp.dart' deferred as ja_jp;
import 'ru_ru.dart' deferred as ru_ru;
import 'th_th.dart' deferred as th_th;
import 'ko_kr.dart' deferred as ko_kr;
import 'es_es.dart' deferred as es_es;
import 'ar_ar.dart' deferred as ar_ar;
import 'vi_vn.dart' deferred as vi_vn;
import 'id_id.dart' deferred as id_id;

/// 语言选项数据类
class LanguageOption {
  final String value;
  final String label;

  const LanguageOption({required this.value, required this.label});
}

class LanguageService extends GetxService with Translations {
  static LanguageService get to => Get.find();

  static const Map<String, String> _gpsAddFallbackEn = {
    'photo_menu_ai_gps_supplement': 'GPS Supplement',
    'photo_ai_gps_add_notice':
        'Please use this feature after all photo indexing has finished.',
    'photo_ai_gps_add_start_scan': 'Search Photos Needing GPS',
    'photo_ai_gps_add_scanning':
        'Searching for photos that can be supplemented with GPS...',
    'photo_ai_gps_add_empty':
        'No photos are waiting for GPS supplement right now.',
    'photo_ai_gps_add_map_title': 'GPS Position',
    'photo_ai_gps_add_map_hint':
        'Tap the map to adjust the final location before writing GPS.',
    'photo_ai_gps_add_selected_point': 'Selected location: @lat, @lng',
    'photo_ai_gps_add_apply': 'Supplement GPS',
    'photo_ai_gps_add_skip': 'Skip These Photos',
    'photo_ai_gps_add_reference_title': 'Reference Photos',
    'photo_ai_gps_add_reference_hint':
        'These nearby photos already contain GPS and are used as location references.',
    'photo_ai_gps_add_reference_switch_tip':
        'Tap a reference photo to switch to its GPS, or fine-tune it on the map.',
    'photo_ai_gps_add_reference_selected': 'Selected reference',
    'photo_ai_gps_add_reference_empty': 'No reference photos found.',
    'photo_ai_gps_add_pending_title': 'Photos To Supplement',
    'photo_ai_gps_add_pending_hint':
        'These photos were shot by the same device within the 3-hour window and do not have GPS.',
    'photo_ai_gps_add_pending_open_tip':
        'Tap any pending photo to open it in the photo viewer.',
    'photo_ai_gps_add_pending_empty': 'No pending photos in this batch.',
    'photo_ai_gps_add_selected_count': 'Selected @count',
    'photo_ai_gps_add_select_photos_first':
        'Select at least one photo to supplement first.',
    'photo_ai_gps_add_camera': 'Device',
    'photo_ai_gps_add_reference_count': 'Reference Photos',
    'photo_ai_gps_add_pending_count': 'Pending Photos',
    'photo_ai_gps_add_time_window': 'Time Window',
    'photo_ai_gps_add_selected': 'Selected GPS',
    'photo_ai_gps_add_selected_reference': 'Current reference: @name',
    'photo_ai_gps_add_success': 'GPS written to @count photos',
  };

  static const Map<String, String> _gpsAddFallbackZh = {
    'photo_menu_ai_gps_supplement': 'GPS补充',
    'photo_ai_gps_add_notice': '请在所有照片索引完成后再使用此功能。',
    'photo_ai_gps_add_start_scan': '搜索待补充GPS照片',
    'photo_ai_gps_add_scanning': '正在搜索可补充 GPS 的照片...',
    'photo_ai_gps_add_empty': '当前没有待补充 GPS 的照片。',
    'photo_ai_gps_add_map_title': 'GPS位置',
    'photo_ai_gps_add_map_hint': '点击地图可调整最终写入的位置。',
    'photo_ai_gps_add_selected_point': '当前选择位置：@lat, @lng',
    'photo_ai_gps_add_apply': '补充GPS',
    'photo_ai_gps_add_skip': '跳过这些照片',
    'photo_ai_gps_add_reference_title': '参考照片',
    'photo_ai_gps_add_reference_hint': '这些附近照片已包含 GPS 信息，可作为位置参考。',
    'photo_ai_gps_add_reference_switch_tip': '点击参考照片即可切换到该位置，再在地图上微调。',
    'photo_ai_gps_add_reference_selected': '当前参考',
    'photo_ai_gps_add_reference_empty': '没有参考照片。',
    'photo_ai_gps_add_pending_title': '待补充照片',
    'photo_ai_gps_add_pending_hint':
        '这些照片由同一设备在前后 3 小时内拍摄，且当前没有 GPS 信息。',
    'photo_ai_gps_add_pending_open_tip': '点击任意待补充照片可直接打开照片浏览器查看。',
    'photo_ai_gps_add_pending_empty': '这一批次没有待补充照片。',
    'photo_ai_gps_add_selected_count': '已选 @count 张',
    'photo_ai_gps_add_select_photos_first': '请先勾选至少一张需要补充的照片。',
    'photo_ai_gps_add_camera': '拍摄设备',
    'photo_ai_gps_add_reference_count': '参考照片数',
    'photo_ai_gps_add_pending_count': '待补充照片数',
    'photo_ai_gps_add_time_window': '时间窗口',
    'photo_ai_gps_add_selected': '当前GPS',
    'photo_ai_gps_add_selected_reference': '当前参考：@name',
    'photo_ai_gps_add_success': '已为 @count 张照片写入 GPS',
    'photo_ai_gps_add_completed': '已全部处理完成，没有更多可补充 GPS 的照片。',
  };

  static const String _languageKey = 'selected_language';
  final RxString _currentLocale = 'zh_CN'.obs;

  final List<Future<void> Function()> _onLanguageChangedCallbacks = [];

  void addOnLanguageChangedCallback(Future<void> Function() callback) {
    _onLanguageChangedCallbacks.add(callback);
  }

  void removeOnLanguageChangedCallback(Future<void> Function() callback) {
    _onLanguageChangedCallbacks.remove(callback);
  }

  /// 已加载的语言包缓存（用于 keys  getter 与按需加载判断）
  final Map<String, Map<String, String>> _loadedKeys = {};
  final Set<String> _loadedLocales = {};

  String get currentLocale => _currentLocale.value;

  // 支持的语言列表（14 种语言）
  static const Map<String, String> supportedLocales = {
    'zh_CN': '简体中文',
    'en_US': 'English',
    'fr_FR': 'Français',
    'de_DE': 'Deutsch',
    'pt_BR': 'Português',
    'ja_JP': '日本語',
    'ru_RU': 'Русский',
    'th_TH': 'ไทย',
    'ko_KR': '한국어',
    'es_ES': 'Español',
    'ar_AR': 'العربية',
    'vi_VN': 'Tiếng Việt',
    'id_ID': 'Bahasa Indonesia',
  };

  @override
  Future<void> onInit() async {
    super.onInit();
    await init();
  }

  /// 按需加载指定语言包（仅 Web 使用 deferred；非 Web 在 init 一次性加载）
  Future<void> _loadLocale(String localeCode) async {
    if (_loadedLocales.contains(localeCode)) return;

    switch (localeCode) {
      case 'zh_CN':
        await zh_cn.loadLibrary();
        final keys = _withGpsAddFallback(zh_cn.ZhCn().keys, localeCode);
        _loadedKeys.addAll(keys);
        Get.addTranslations(keys);
        _loadedLocales.add(localeCode);
        break;
      case 'en_US':
        await en_us.loadLibrary();
        final keys = _withGpsAddFallback(en_us.EnUs().keys, localeCode);
        _loadedKeys.addAll(keys);
        Get.addTranslations(keys);
        _loadedLocales.add(localeCode);
        break;
      case 'fr_FR':
        await fr_fr.loadLibrary();
        final keys = _withGpsAddFallback(fr_fr.FrFr().keys, localeCode);
        _loadedKeys.addAll(keys);
        Get.addTranslations(keys);
        _loadedLocales.add(localeCode);
        break;
      case 'de_DE':
        await de_de.loadLibrary();
        final keys = _withGpsAddFallback(de_de.DeDe().keys, localeCode);
        _loadedKeys.addAll(keys);
        Get.addTranslations(keys);
        _loadedLocales.add(localeCode);
        break;
      case 'pt_BR':
        await pt_br.loadLibrary();
        final keys = _withGpsAddFallback(pt_br.PtBr().keys, localeCode);
        _loadedKeys.addAll(keys);
        Get.addTranslations(keys);
        _loadedLocales.add(localeCode);
        break;
      case 'ja_JP':
        await ja_jp.loadLibrary();
        final keys = _withGpsAddFallback(ja_jp.JaJp().keys, localeCode);
        _loadedKeys.addAll(keys);
        Get.addTranslations(keys);
        _loadedLocales.add(localeCode);
        break;
      case 'ru_RU':
        await ru_ru.loadLibrary();
        final keys = _withGpsAddFallback(ru_ru.RuRu().keys, localeCode);
        _loadedKeys.addAll(keys);
        Get.addTranslations(keys);
        _loadedLocales.add(localeCode);
        break;
      case 'th_TH':
        await th_th.loadLibrary();
        final keys = _withGpsAddFallback(th_th.ThTh().keys, localeCode);
        _loadedKeys.addAll(keys);
        Get.addTranslations(keys);
        _loadedLocales.add(localeCode);
        break;
      case 'ko_KR':
        await ko_kr.loadLibrary();
        final keys = _withGpsAddFallback(ko_kr.KoKr().keys, localeCode);
        _loadedKeys.addAll(keys);
        Get.addTranslations(keys);
        _loadedLocales.add(localeCode);
        break;
      case 'es_ES':
        await es_es.loadLibrary();
        final keys = _withGpsAddFallback(es_es.EsEs().keys, localeCode);
        _loadedKeys.addAll(keys);
        Get.addTranslations(keys);
        _loadedLocales.add(localeCode);
        break;
      case 'ar_AR':
        await ar_ar.loadLibrary();
        final keys = _withGpsAddFallback(ar_ar.ArAr().keys, localeCode);
        _loadedKeys.addAll(keys);
        Get.addTranslations(keys);
        _loadedLocales.add(localeCode);
        break;
      case 'vi_VN':
        await vi_vn.loadLibrary();
        final keys = _withGpsAddFallback(vi_vn.ViVn().keys, localeCode);
        _loadedKeys.addAll(keys);
        Get.addTranslations(keys);
        _loadedLocales.add(localeCode);
        break;
      case 'id_ID':
        await id_id.loadLibrary();
        final keys = _withGpsAddFallback(id_id.IdId().keys, localeCode);
        _loadedKeys.addAll(keys);
        Get.addTranslations(keys);
        _loadedLocales.add(localeCode);
        break;
      default:
        break;
    }
  }

  Map<String, Map<String, String>> _withGpsAddFallback(
    Map<String, Map<String, String>> keys,
    String localeCode,
  ) {
    final merged = <String, Map<String, String>>{};
    keys.forEach((locale, value) {
      final map = Map<String, String>.from(value);
      final fallback = localeCode == 'zh_CN' ? _gpsAddFallbackZh : _gpsAddFallbackEn;
      map.addAll(fallback);
      merged[locale] = map;
    });
    return merged;
  }

  /// 检测系统语言并匹配到支持的语言
  String _detectSystemLanguage() {
    final systemLocale = Get.deviceLocale;

    // 如果无法获取系统语言，根据平台返回默认值
    if (systemLocale == null) {
      // Web 端无法获取时使用英语，其他平台使用中文
      print("无法获取系统语言，使用默认英语");
      return 'en_US';
    }

    final systemLanguageCode = systemLocale.languageCode.toLowerCase();
    final systemCountryCode = systemLocale.countryCode?.toUpperCase() ?? '';

    // 优先匹配完整的语言代码（语言_国家）
    final fullMatch = '${systemLanguageCode}_$systemCountryCode';
    if (supportedLocales.containsKey(fullMatch)) {
      return fullMatch;
    }

    // 其次匹配语言代码
    for (final locale in supportedLocales.keys) {
      final langCode = locale.split('_').first.toLowerCase();
      if (langCode == systemLanguageCode) {
        return locale;
      }
    }

    // 特殊处理：某些地区的语言变体
    switch (systemLanguageCode) {
      case 'zh':
        // 中文地区匹配
        if (['TW', 'HK', 'MO'].contains(systemCountryCode)) {
          return 'zh_CN'; // 暂时统一使用简体中文
        }
        return 'zh_CN';
      case 'pt':
        // 葡萄牙语地区匹配
        if (systemCountryCode == 'PT') {
          return 'pt_BR'; // 暂时统一使用巴西葡萄牙语
        }
        return 'pt_BR';
      case 'es':
        return 'es_ES';
      case 'fr':
        return 'fr_FR';
      case 'de':
        return 'de_DE';
      case 'ja':
        return 'ja_JP';
      case 'ko':
        return 'ko_KR';
      case 'ru':
        return 'ru_RU';
      case 'th':
        return 'th_TH';
      case 'vi':
        return 'vi_VN';
      case 'id':
        return 'id_ID';
      case 'ar':
        return 'ar_AR';
      default:
        // 其他语言默认使用英语
        return 'en_US';
    }
  }

  /// 初始化语言设置
  Future<LanguageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLanguage = prefs.getString(_languageKey);

    if (savedLanguage != null && supportedLocales.containsKey(savedLanguage)) {
      print('[LanguageService] 使用用户保存的语言：$savedLanguage');
      _currentLocale.value = savedLanguage;
    } else {
      // 没有用户选择记录时，跟随系统语言
      final detectedLang = _detectSystemLanguage();
      print('[LanguageService] 首次启动，检测到系统语言：$detectedLang');
      print('[LanguageService] Get.deviceLocale = ${Get.deviceLocale}');
      print('[LanguageService] kIsWeb = $kIsWeb');
      _currentLocale.value = detectedLang;
    }

    if (kIsWeb) {
      // Web：只加载当前语言，减少首包体积，切换时再按需加载
      await _loadLocale(_currentLocale.value);
    } else {
      // 非 Web：一次性加载全部 13 种语言，切换无延迟
      await zh_cn.loadLibrary();
      await en_us.loadLibrary();
      await fr_fr.loadLibrary();
      await de_de.loadLibrary();
      await pt_br.loadLibrary();
      await ja_jp.loadLibrary();
      await ru_ru.loadLibrary();
      await th_th.loadLibrary();
      await ko_kr.loadLibrary();
      await es_es.loadLibrary();
      await ar_ar.loadLibrary();
      await vi_vn.loadLibrary();
      await id_id.loadLibrary();

      final zhKeys = zh_cn.ZhCn().keys;
      final enKeys = en_us.EnUs().keys;
      final frKeys = fr_fr.FrFr().keys;
      final deKeys = de_de.DeDe().keys;
      final ptKeys = pt_br.PtBr().keys;
      final jaKeys = ja_jp.JaJp().keys;
      final ruKeys = ru_ru.RuRu().keys;
      final thKeys = th_th.ThTh().keys;
      final koKeys = ko_kr.KoKr().keys;
      final esKeys = es_es.EsEs().keys;
      final arKeys = ar_ar.ArAr().keys;
      final viKeys = vi_vn.ViVn().keys;
      final idKeys = id_id.IdId().keys;

      _loadedKeys.addAll(zhKeys);
      _loadedKeys.addAll(enKeys);
      _loadedKeys.addAll(frKeys);
      _loadedKeys.addAll(deKeys);
      _loadedKeys.addAll(ptKeys);
      _loadedKeys.addAll(jaKeys);
      _loadedKeys.addAll(ruKeys);
      _loadedKeys.addAll(thKeys);
      _loadedKeys.addAll(koKeys);
      _loadedKeys.addAll(esKeys);
      _loadedKeys.addAll(arKeys);
      _loadedKeys.addAll(viKeys);
      _loadedKeys.addAll(idKeys);

      Get.addTranslations(zhKeys);
      Get.addTranslations(enKeys);
      Get.addTranslations(frKeys);
      Get.addTranslations(deKeys);
      Get.addTranslations(ptKeys);
      Get.addTranslations(jaKeys);
      Get.addTranslations(ruKeys);
      Get.addTranslations(thKeys);
      Get.addTranslations(koKeys);
      Get.addTranslations(esKeys);
      Get.addTranslations(arKeys);
      Get.addTranslations(viKeys);
      Get.addTranslations(idKeys);

      _loadedLocales.addAll([
        'zh_CN',
        'en_US',
        'fr_FR',
        'de_DE',
        'pt_BR',
        'ja_JP',
        'ru_RU',
        'th_TH',
        'ko_KR',
        'es_ES',
        'ar_AR',
        'vi_VN',
        'id_ID',
      ]);
    }

    updateLocale();
    return this;
  }

  /// 切换语言
  Future<void> changeLanguage(String localeCode) async {
    if (!supportedLocales.containsKey(localeCode)) return;
    if (kIsWeb) await _loadLocale(localeCode);
    _currentLocale.value = localeCode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, localeCode);
    updateLocale();
    for (final callback in _onLanguageChangedCallbacks) {
      await callback();
    }
  }

  /// 更新 GetX 的语言设置
  void updateLocale() {
    final parts = _currentLocale.value.split('_');
    if (parts.length == 2) {
      Get.updateLocale(Locale(parts[0], parts[1]));
    } else {
      Get.updateLocale(Locale(parts[0]));
    }
  }

  /// 获取当前语言名称
  String get currentLanguageName {
    return supportedLocales[_currentLocale.value] ?? '未知语言';
  }

  /// 获取所有支持的语言
  Map<String, String> get availableLanguages => Map.from(supportedLocales);

  /// 获取完整的语言选项列表（按指定顺序）
  static List<LanguageOption> getFullLanguageOptions() {
    return [
      const LanguageOption(value: 'en_US', label: 'English'),
      const LanguageOption(value: 'zh_CN', label: '简体中文'),
      const LanguageOption(value: 'ja_JP', label: '日本語'),
      const LanguageOption(value: 'ko_KR', label: '한국어'),
      const LanguageOption(value: 'es_ES', label: 'Español'),
      const LanguageOption(value: 'pt_BR', label: 'Português (Brasil)'),
      const LanguageOption(value: 'fr_FR', label: 'Français'),
      const LanguageOption(value: 'de_DE', label: 'Deutsch'),
      const LanguageOption(value: 'ru_RU', label: 'Русский'),
      const LanguageOption(value: 'id_ID', label: 'Bahasa Indonesia'),
      const LanguageOption(value: 'vi_VN', label: 'Tiếng Việt'),
      const LanguageOption(value: 'th_TH', label: 'ไทย'),
      const LanguageOption(value: 'ar_AR', label: 'العربية'),
    ];
  }

  /// 重置为默认语言
  Future<void> resetToDefault() async {
    await changeLanguage('zh_CN');
  }

  /// 获取翻译文本
  String tr(String key, [Map<String, String>? params]) {
    return key.tr;
  }

  /// 获取翻译映射（返回已加载的语言包，Web 下随按需加载逐渐增多）
  @override
  Map<String, Map<String, String>> get keys => Map.from(_loadedKeys);
}
