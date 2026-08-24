import 'dart:async';
import 'dart:convert';
import 'package:code_text_field/code_text_field.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:highlight/highlight.dart';
import 'package:highlight/languages/dart.dart' as lang_dart;
import 'package:highlight/languages/javascript.dart' as lang_js;
import 'package:highlight/languages/json.dart' as lang_json;
import 'package:highlight/languages/markdown.dart' as lang_md;
import 'package:highlight/languages/python.dart' as lang_py;
import 'package:highlight/languages/xml.dart' as lang_xml;
import 'package:highlight/languages/yaml.dart' as lang_yaml;
import 'package:highlight/languages/css.dart' as lang_css;
import 'package:highlight/languages/java.dart' as lang_java;
import 'package:highlight/languages/cpp.dart' as lang_cpp;
import 'package:highlight/languages/bash.dart' as lang_bash;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../service/editor_api_service.dart';
import '../service/editor_ws_service.dart';

class EditorSessionController extends GetxController {
  EditorSessionController({required this.windowId, required this.filePath});

  final String windowId;
  final String filePath;

  final canWrite = true.obs;
  final rev = 0.obs;
  final statusText = ''.obs;
  final hasPendingLocal = false.obs;

  final fontSize = 14.obs;

  late final CodeController codeController;

  final EditorApiService _api = EditorApiService();
  final EditorWsService _ws = EditorWsService();

  Timer? _debounceTimer;
  bool _applyingRemote = false;
  String _lastText = '';
  bool _didInitialCaretFix = false;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _reconnectAttempt = 0;
  bool _closed = false;
  int _wsSeq = 0;

  String get fileName => p.basename(filePath);
  String get fileExt =>
      p.extension(filePath).toLowerCase().replaceFirst('.', '');

  @override
  void onInit() {
    super.onInit();
    statusText.value = 'editor_status_connecting'.tr;
    codeController = CodeController(
      text: '',
      language: _resolveLanguage(fileExt),
      patternMap: const {},
      stringMap: const {},
    );
    codeController.addListener(_onLocalChanged);
    _connect();
    _forceOpenWithRetry();
  }

  @override
  void onClose() {
    _closed = true;
    _debounceTimer?.cancel();
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    codeController.removeListener(_onLocalChanged);
    codeController.dispose();
    _ws.disconnect();
    super.onClose();
  }

  Future<void> forceOpen() async {
    final res = await _api.open(path: filePath);
    applyConfig(res.config);
    canWrite.value = res.canWrite;
    _setTextFromRemote(res.text, res.rev);
    statusText.value = 'editor_status_synced'.tr;
  }

  Future<void> _forceOpenWithRetry() async {
    var attempt = 0;
    while (!_closed && attempt < 5) {
      try {
        await forceOpen();
        return;
      } catch (_) {
        attempt += 1;
        if (_closed) return;
        await Future.delayed(Duration(milliseconds: 300 + attempt * 250));
      }
    }
    if (_closed) return;
    statusText.value = 'editor_status_disconnected'.tr;
    _scheduleReconnect();
  }

  void applyConfig(EditorUserConfig config) {
    fontSize.value = config.fontSize;
  }

  EditorUserConfig get currentConfig =>
      EditorUserConfig(fontSize: fontSize.value);

  Future<void> saveConfig(EditorUserConfig config) async {
    final saved = await _api.setConfig(config);
    applyConfig(saved);
  }

  Future<void> resetConfig() async {
    final saved = await _api.resetConfig();
    applyConfig(saved);
  }

  Future<void> forceSave() async {
    if (!canWrite.value) return;
    statusText.value = 'editor_status_saving'.tr;
    await _api.save(path: filePath, text: codeController.text);
    statusText.value = 'editor_status_saved'.tr;
    hasPendingLocal.value = false;
  }

  void _connect() {
    final seq = ++_wsSeq;
    _ws.connect(
      filePath: filePath,
      onMessage: (msg) {
        if (_closed) return;
        if (seq != _wsSeq) return;
        _handleWsMessage(msg);
      },
      onError: (_) {
        if (_closed) return;
        if (seq != _wsSeq) return;
        _handleDisconnected();
      },
      onDone: () {
        if (_closed) return;
        if (seq != _wsSeq) return;
        _handleDisconnected();
      },
    );
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (_closed) return;
      if (seq != _wsSeq) return;
      _ws.send({'type': 'ping'});
    });
  }

  void _handleDisconnected() {
    if (_closed) return;
    statusText.value = 'editor_status_disconnected'.tr;
    _pingTimer?.cancel();
    _pingTimer = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _reconnectTimer?.cancel();
    final capped = _reconnectAttempt > 5 ? 5 : _reconnectAttempt;
    final delayMs = (300 * (1 << capped)).clamp(300, 8000);
    _reconnectAttempt += 1;
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_closed) return;
      statusText.value = 'editor_status_connecting'.tr;
      _connect();
    });
  }

  void _resetReconnect() {
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _handleWsMessage(Map<String, dynamic> msg) {
    final type = msg['type']?.toString() ?? '';
    if (type.isNotEmpty) {
      _resetReconnect();
    }
    if (type == 'sync') {
      final text = msg['text']?.toString() ?? '';
      final r = int.tryParse(msg['rev']?.toString() ?? '') ?? 0;
      final writable = msg['canWrite'] == true;
      canWrite.value = writable;
      _applyRemoteSnapshot(text: text, remoteRev: r, setSyncedStatus: true);
      return;
    }
    if (type == 'resync') {
      final text = msg['text']?.toString() ?? '';
      final r = int.tryParse(msg['rev']?.toString() ?? '') ?? 0;
      _applyRemoteSnapshot(text: text, remoteRev: r, setSyncedStatus: false);
      return;
    }
    if (type == 'pong') {
      if (statusText.value == 'editor_status_disconnected'.tr) {
        statusText.value = 'editor_status_connected'.tr;
      }
      return;
    }
    if (type == 'ack') {
      final r = int.tryParse(msg['rev']?.toString() ?? '') ?? rev.value;
      rev.value = r;
      final stillPending = codeController.text != _lastText;
      hasPendingLocal.value = stillPending;
      statusText.value = stillPending
          ? 'editor_status_syncing'.tr
          : 'editor_status_synced'.tr;
      return;
    }
    if (type == 'readonly') {
      canWrite.value = false;
      statusText.value = 'editor_status_readonly'.tr;
      return;
    }
    if (type == 'op') {
      final r = int.tryParse(msg['rev']?.toString() ?? '') ?? rev.value;
      final ops = msg['ops'];
      if (ops is List) {
        _applyRemoteOps(ops.cast<dynamic>());
        rev.value = r;
        statusText.value = hasPendingLocal.value
            ? 'editor_status_syncing'.tr
            : 'editor_status_connected'.tr;
      }
      return;
    }
  }

  void _applyRemoteSnapshot({
    required String text,
    required int remoteRev,
    required bool setSyncedStatus,
  }) {
    final local = codeController.text;
    final pending = hasPendingLocal.value;
    if (pending && local != text) {
      rev.value = remoteRev;
      final ops = _diffToOps(text, local);
      _lastText = local;
      if (ops.isNotEmpty && canWrite.value) {
        _ws.send({
          'type': 'op',
          'rev': remoteRev,
          'ops': ops,
          'clientId': _clientId(),
        });
      }
      hasPendingLocal.value = true;
      statusText.value = 'editor_status_syncing'.tr;
      return;
    }

    _setTextFromRemote(text, remoteRev);
    statusText.value = setSyncedStatus
        ? 'editor_status_synced'.tr
        : 'editor_status_resynced'.tr;
  }

  void _setTextFromRemote(String text, int remoteRev) {
    _applyingRemote = true;
    codeController.text = text;
    _lastText = text;
    rev.value = remoteRev;
    hasPendingLocal.value = false;
    if (!_didInitialCaretFix) {
      codeController.selection = const TextSelection.collapsed(offset: 0);
      _didInitialCaretFix = true;
    }
    _applyingRemote = false;
  }

  void _applyRemoteOps(List<dynamic> ops) {
    _applyingRemote = true;
    final oldText = codeController.text;
    final oldSel = codeController.selection;
    final applied = _applyOpsToText(oldText, ops);
    codeController.text = applied;
    final newSel = _adjustSelection(oldText, applied, oldSel, ops);
    codeController.selection = newSel;
    _lastText = applied;
    _applyingRemote = false;
  }

  TextSelection _adjustSelection(
    String oldText,
    String newText,
    TextSelection oldSel,
    List<dynamic> ops,
  ) {
    int delta = 0;
    int index = 0;
    for (final raw in ops) {
      if (raw is! Map) continue;
      if (raw['retain'] != null) {
        index += int.tryParse(raw['retain'].toString()) ?? 0;
      } else if (raw['delete'] != null) {
        final del = int.tryParse(raw['delete'].toString()) ?? 0;
        if (oldSel.baseOffset > index) {
          delta -= del.clamp(0, oldSel.baseOffset - index);
        }
      } else if (raw['insert'] != null) {
        final ins = raw['insert']?.toString() ?? '';
        if (oldSel.baseOffset >= index) {
          delta += ins.length;
        }
        index += ins.length;
      }
    }
    final base = (oldSel.baseOffset + delta).clamp(0, newText.length);
    final extent = (oldSel.extentOffset + delta).clamp(0, newText.length);
    return TextSelection(baseOffset: base, extentOffset: extent);
  }

  void _onLocalChanged() {
    if (_applyingRemote) return;
    if (!canWrite.value) return;
    final current = codeController.text;
    if (current == _lastText) return;
    hasPendingLocal.value = true;
    statusText.value = 'editor_status_syncing'.tr;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 120), () {
      final before = _lastText;
      final after = codeController.text;
      if (before == after) return;
      final ops = _diffToOps(before, after);
      if (ops.isEmpty) return;

      _lastText = after;
      _ws.send({
        'type': 'op',
        'rev': rev.value,
        'ops': ops,
        'clientId': _clientId(),
      });
    });
  }

  String _clientId() {
    final bytes = utf8.encode('$windowId|$filePath');
    return sha1.convert(bytes).toString();
  }

  List<Map<String, dynamic>> _diffToOps(String before, String after) {
    int prefix = 0;
    final minLen = before.length < after.length ? before.length : after.length;
    while (prefix < minLen &&
        before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
      prefix++;
    }

    int suffix = 0;
    while (suffix < (before.length - prefix) &&
        suffix < (after.length - prefix) &&
        before.codeUnitAt(before.length - 1 - suffix) ==
            after.codeUnitAt(after.length - 1 - suffix)) {
      suffix++;
    }

    final beforeMidEnd = before.length - suffix;
    final afterMidEnd = after.length - suffix;
    final deleted = beforeMidEnd - prefix;
    final inserted = after.substring(prefix, afterMidEnd);

    final ops = <Map<String, dynamic>>[];
    if (prefix > 0) ops.add({'retain': prefix});
    if (deleted > 0) ops.add({'delete': deleted});
    if (inserted.isNotEmpty) ops.add({'insert': inserted});
    return ops;
  }

  String _applyOpsToText(String text, List<dynamic> ops) {
    var s = text;
    int index = 0;
    for (final raw in ops) {
      if (raw is! Map) continue;
      if (raw['retain'] != null) {
        index += int.tryParse(raw['retain'].toString()) ?? 0;
        index = index.clamp(0, s.length);
      } else if (raw['delete'] != null) {
        final del = int.tryParse(raw['delete'].toString()) ?? 0;
        if (del <= 0) continue;
        final start = index.clamp(0, s.length);
        final end = (start + del).clamp(0, s.length);
        s = s.replaceRange(start, end, '');
      } else if (raw['insert'] != null) {
        final ins = raw['insert']?.toString() ?? '';
        final at = index.clamp(0, s.length);
        s = s.replaceRange(at, at, ins);
        index = at + ins.length;
      }
    }
    return s;
  }

  Mode? _resolveLanguage(String ext) {
    switch (ext) {
      case 'dart':
        return lang_dart.dart;
      case 'js':
      case 'jsx':
      case 'ts':
      case 'tsx':
        return lang_js.javascript;
      case 'json':
        return lang_json.json;
      case 'md':
      case 'markdown':
        return lang_md.markdown;
      case 'py':
        return lang_py.python;
      case 'xml':
      case 'html':
        return lang_xml.xml;
      case 'yaml':
      case 'yml':
        return lang_yaml.yaml;
      case 'css':
        return lang_css.css;
      case 'java':
        return lang_java.java;
      case 'c':
      case 'cc':
      case 'cpp':
      case 'h':
      case 'hpp':
        return lang_cpp.cpp;
      case 'sh':
        return lang_bash.bash;
      default:
        return null;
    }
  }
}
