import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../core/api/api_controller.dart';
import '../../../core/languages/language_service.dart';
import '../../../utils/dialog_util.dart';
import '../../../utils/toast_util.dart';
import '../service/quick_share_api_service.dart';

class QuickShareConfigController extends GetxController {
  final _api = QuickShareApiService();

  final items = <Map<String, dynamic>>[].obs;
  final revealPwdIds = <int>{}.obs;
  final p2pPairCode = ''.obs;

  @override
  void onInit() {
    super.onInit();
    refreshList(showLoading: false);
  }

  /// 与 `quickshare/i18n.js` 的 `normalizeLocale` 对齐：BCP 47（`zh_CN` → `zh-CN`）。
  String _languageParam() {
    var code = LanguageService.to.currentLocale.trim();
    if (code.isEmpty) return 'zh-CN';
    if (code == 'ar_AR') code = 'ar-SA';
    return code.replaceAll('_', '-');
  }

  String _encryptP2pPairCode(String pairCode) {
    final code = pairCode.trim();
    if (code.isEmpty) return '';
    try {
      final keyBytes = sha256
          .convert(utf8.encode(ApiController.quickShareAesKey))
          .bytes;
      final key = encrypt.Key(Uint8List.fromList(keyBytes));
      final ivBytes = sha256.convert(utf8.encode(code)).bytes.sublist(0, 16);
      final iv = encrypt.IV(Uint8List.fromList(ivBytes));
      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );
      final encrypted = encrypter.encrypt(code, iv: iv);
      final combined = Uint8List.fromList(iv.bytes + encrypted.bytes);
      return base64Encode(combined);
    } catch (_) {
      return '';
    }
  }

  String buildLocalShareUrl(String token) {
    final base = ApiController.instance.quickShareLocalHttpOrigin();
    final safeToken = Uri.encodeQueryComponent(token);
    final safeLang = Uri.encodeQueryComponent(_languageParam());
    return '$base/quickshare/index.html?qt=$safeToken&language=$safeLang';
  }

  String buildRemoteShareUrl(String token) {
    final pairCode = p2pPairCode.value.trim();
    if (pairCode.isEmpty) return '';
    final enc = _encryptP2pPairCode(pairCode);
    if (enc.isEmpty) return '';
    final base = ApiController.signalApiBaseUrl;
    final safeToken = Uri.encodeQueryComponent(token);
    final safeLang = Uri.encodeQueryComponent(_languageParam());
    final safePc = Uri.encodeQueryComponent(enc);
    return '$base/quickshare/index.html?qt=$safeToken&language=$safeLang&pc=$safePc';
  }

  bool isPwdRevealed(int id) => revealPwdIds.contains(id);

  void togglePwdReveal(int id) {
    if (revealPwdIds.contains(id)) {
      revealPwdIds.remove(id);
      revealPwdIds.refresh();
      return;
    }
    revealPwdIds.add(id);
    revealPwdIds.refresh();
  }

  Future<void> refreshList({bool showLoading = true}) async {
    try {
      if (showLoading) DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _api.list();
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      final data = res.data ?? {};
      final raw = data['items'];
      final list = raw is List ? raw : const [];
      p2pPairCode.value = (data['pairCode']?.toString() ?? '').trim();
      items.value = list
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    } catch (_) {
      ToastUtil.show('operation_failed'.tr);
    } finally {
      if (showLoading) DialogUtil.dismissLoading(force: true);
    }
  }

  Future<void> copyText(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      ToastUtil.show('quick_share_copied'.tr);
    } catch (_) {
      ToastUtil.show('operation_failed'.tr);
    }
  }

  Future<bool> createShare({
    required String path,
    String? pwd,
    String? remark,
    int? durationValue,
    String? durationUnit,
    bool? noLimit,
  }) async {
    try {
      DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _api.create(
        path: path,
        pwd: pwd,
        remark: remark,
        durationValue: durationValue,
        durationUnit: durationUnit,
        noLimit: noLimit,
      );
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return false;
      }
      await refreshList(showLoading: false);
      ToastUtil.show('operation_success'.tr);
      return true;
    } catch (_) {
      ToastUtil.show('operation_failed'.tr);
      return false;
    } finally {
      DialogUtil.dismissLoading(force: true);
    }
  }

  Future<void> deleteShare(int id) async {
    try {
      DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _api.delete(id: id);
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      await refreshList(showLoading: false);
      ToastUtil.show('delete_success'.tr);
    } catch (_) {
      ToastUtil.show('operation_failed'.tr);
    } finally {
      DialogUtil.dismissLoading(force: true);
    }
  }

  Future<void> cleanExpired() async {
    try {
      DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _api.cleanExpired();
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      await refreshList(showLoading: false);
      ToastUtil.show('operation_success'.tr);
    } catch (_) {
      ToastUtil.show('operation_failed'.tr);
    } finally {
      DialogUtil.dismissLoading(force: true);
    }
  }
}
