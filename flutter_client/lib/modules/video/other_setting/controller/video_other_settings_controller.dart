import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/toast_util.dart';
import '../service/video_tmdb_settings_api_service.dart';

class TranscodeHwDecoderOption {
  final String key;
  final String label;
  final String kind;
  final List<String> codecs;

  const TranscodeHwDecoderOption({
    required this.key,
    required this.label,
    required this.kind,
    required this.codecs,
  });

  factory TranscodeHwDecoderOption.fromJson(Map<String, dynamic> json) {
    final codecsRaw = json['codecs'];
    final codecs = codecsRaw is List
        ? codecsRaw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
        : <String>[];
    return TranscodeHwDecoderOption(
      key: (json['key']?.toString() ?? '').trim(),
      label: (json['label']?.toString() ?? '').trim(),
      kind: (json['kind']?.toString() ?? '').trim(),
      codecs: codecs,
    );
  }
}

class VideoOtherSettingsController extends GetxController {
  /// TMDB 支持的语言（与国际化 13 种一致：空为跟随系统）
  static const Set<String> allowedTmdbLanguages = {
    '',
    'en-US',
    'zh-CN',
    'es-ES',
    'fr-FR',
    'de-DE',
    'ja-JP',
    'pt-BR',
    'ru-RU',
    'ar-SA',
    'ko-KR',
    'th-TH',
    'vi-VN',
    'id-ID',
  };

  final RxBool loading = false.obs;

  final TextEditingController tmdbTokenController = TextEditingController();
  final TextEditingController proxyUrlController = TextEditingController();

  final RxBool proxyEnabled = false.obs;
  final RxString tmdbLanguage = ''.obs;
  final RxString transcodeTempDir = ''.obs;
  final RxString preferredHwDecoder = ''.obs;
  final RxString effectiveHwDecoderLabel = ''.obs;
  final RxList<TranscodeHwDecoderOption> availableHwDecoders =
      <TranscodeHwDecoderOption>[].obs;
  final RxBool subtitlePreExtractEnabled = true.obs;

  final _api = VideoTmdbSettingsApiService.instance;

  @override
  void onInit() {
    super.onInit();
    fetchSettings(showLoading: false);
    fetchTranscodeSettings(showLoading: false);
    fetchSubtitleSettings(showLoading: false);
  }

  @override
  void onClose() {
    tmdbTokenController.dispose();
    proxyUrlController.dispose();
    super.onClose();
  }

  Future<void> fetchSettings({bool showLoading = false}) async {
    if (loading.value) return;
    loading.value = true;
    try {
      final res = await _api.getTmdbConfig(showLoading: showLoading);
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      final data = res.data ?? <String, dynamic>{};
      final rawToken = (data['accessToken']?.toString() ?? '').trim();
      // 已加密的 token（enc. 开头）不显示、不回填
      tmdbTokenController.text = rawToken.startsWith('enc.') ? '' : rawToken;
      proxyEnabled.value =
          data['proxyEnable'] == 1 || data['proxyEnable'] == '1';
      proxyUrlController.text = (data['proxyUrl']?.toString() ?? '').trim();
      final lang = (data['language']?.toString() ?? '').trim();
      tmdbLanguage.value = allowedTmdbLanguages.contains(lang) ? lang : '';
    } finally {
      loading.value = false;
    }
  }

  Future<void> fetchTranscodeSettings({bool showLoading = false}) async {
    try {
      final res = await _api.getTranscodeConfig(showLoading: showLoading);
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      final data = res.data ?? <String, dynamic>{};
      transcodeTempDir.value = (data['tempDir']?.toString() ?? '').trim();
      final optionsRaw = data['availableHwDecoders'];
      final options = optionsRaw is List
          ? optionsRaw
                .whereType<Map>()
                .map((item) => TranscodeHwDecoderOption.fromJson(
                      item.map((key, value) => MapEntry(key.toString(), value)),
                    ))
                .where((item) => item.key.isNotEmpty)
                .toList()
          : <TranscodeHwDecoderOption>[];
      availableHwDecoders.assignAll(options);
      final preferred = (data['preferredHwDecoder']?.toString() ?? '').trim();
      preferredHwDecoder.value =
          options.any((item) => item.key == preferred) ? preferred : '';
      effectiveHwDecoderLabel.value =
          ((data['effectiveHwDecoder'] as Map?)?['label']?.toString() ?? '')
              .trim();
    } catch (_) {}
  }

  Future<void> saveSettings() async {
    final accessToken = tmdbTokenController.text.trim();
    final enableProxy = proxyEnabled.value;
    final proxyUrl = proxyUrlController.text.trim();
    final language = tmdbLanguage.value.trim();

    if (enableProxy && proxyUrl.isEmpty) {
      ToastUtil.show('video_tmdb_proxy_required'.tr);
      return;
    }

    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      final res = await _api.setTmdbConfig(
        accessToken: accessToken,
        proxyEnable: enableProxy,
        proxyUrl: proxyUrl,
        language: language,
        showLoading: false,
      );
      if (!res.success) {
        DialogUtil.dismissLoading();
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      DialogUtil.dismissLoading();
      ToastUtil.show('operation_success'.tr);
      await fetchSettings(showLoading: false);
    } finally {
      DialogUtil.dismissLoading();
    }
  }

  void setTranscodeTempDirDraft(String dir) {
    transcodeTempDir.value = dir.trim();
  }

  void resetTranscodeTempDirDraft() {
    transcodeTempDir.value = '';
  }

  Future<void> fetchSubtitleSettings({bool showLoading = false}) async {
    try {
      final res = await _api.getSubtitleConfig(showLoading: showLoading);
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      final data = res.data ?? <String, dynamic>{};
      subtitlePreExtractEnabled.value =
          data['preExtractEnable'] == 1 || data['preExtractEnable'] == '1' || data['preExtractEnable'] == true;
    } catch (_) {}
  }

  Future<void> saveSubtitleSettings() async {
    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      final res = await _api.setSubtitleConfig(
        preExtractEnable: subtitlePreExtractEnabled.value,
        showLoading: false,
      );
      if (!res.success) {
        DialogUtil.dismissLoading();
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      DialogUtil.dismissLoading();
      ToastUtil.show('operation_success'.tr);
      await fetchSubtitleSettings(showLoading: false);
    } finally {
      DialogUtil.dismissLoading();
    }
  }

  Future<void> saveTranscodeSettings() async {
    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      final res = await _api.setTranscodeConfig(
        tempDir: transcodeTempDir.value.trim(),
        preferredHwDecoder: preferredHwDecoder.value.trim(),
        showLoading: false,
      );
      if (!res.success) {
        DialogUtil.dismissLoading();
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      DialogUtil.dismissLoading();
      ToastUtil.show('operation_success'.tr);
      await fetchTranscodeSettings(showLoading: false);
    } finally {
      DialogUtil.dismissLoading();
    }
  }

  void setPreferredHwDecoder(String value) {
    preferredHwDecoder.value = value.trim();
  }

  TranscodeHwDecoderOption? findHwDecoderOption(String key) {
    final value = key.trim();
    for (final item in availableHwDecoders) {
      if (item.key == value) return item;
    }
    return null;
  }

  String buildHwDecoderSummary(TranscodeHwDecoderOption option) {
    final parts = <String>[];
    if (option.kind.isNotEmpty) {
      parts.add(option.kind == 'discrete'
          ? 'video_transcode_hwaccel_kind_discrete'.tr
          : option.kind == 'integrated'
              ? 'video_transcode_hwaccel_kind_integrated'.tr
              : option.kind);
    }
    if (option.codecs.isNotEmpty) {
      parts.add(option.codecs
          .map((codec) => codec.toUpperCase())
          .toSet()
          .join(' / '));
    }
    return parts.join(' · ');
  }
}
