import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:web/web.dart' as web;
import 'upload_web_file_helper.dart';
import '../upload_controller.dart';
import '../../../files/controllers/pc_file_explorer_controller.dart';
import '../../views/upload/upload_drop_alert_view.dart';

class UploadWebFolderDropTarget extends StatefulWidget {
  final Widget child;
  final PcFileExplorerController? ctrl;
  final Future<void> Function(dynamic dataTransfer)? onDropDataTransfer;
  final VoidCallback? onDragEntered;
  final VoidCallback? onDragExited;

  const UploadWebFolderDropTarget({
    super.key,
    required this.child,
    this.ctrl,
    this.onDropDataTransfer,
    this.onDragEntered,
    this.onDragExited,
  });

  @override
  State<UploadWebFolderDropTarget> createState() =>
      _UploadWebFolderDropTargetState();
}

class _UploadWebFolderDropTargetState extends State<UploadWebFolderDropTarget> {
  bool _dragging = false;
  StreamSubscription? _dragOverSub;
  StreamSubscription? _dragLeaveSub;
  StreamSubscription? _dropSub;

  @override
  void initState() {
    super.initState();
    debugPrint('[UploadWebFolderDropTarget] initState');
    // 注册一个空的MethodChannel处理器来拦截desktop_drop插件的消息
    // 防止因插件自动注册导致的 MissingPluginException 错误
    const MethodChannel('desktop_drop').setMethodCallHandler((call) async {
      return null;
    });
    _registerDropListeners();
  }

  void _registerDropListeners() {
    // 使用 document 作为监听目标，并在捕获阶段监听，确保在 Flutter 根节点/Canvas 之前收到
    // 拖放事件，避免 Web 端无反应（Mac/桌面端用 desktop_drop 正常）
    final target = web.document;
    const useCapture = true;
    debugPrint(
      '[UploadWebFolderDropTarget] register listeners target=${target.runtimeType} useCapture=$useCapture',
    );

    // Drag Over（必须在 dragover 里 preventDefault 才能触发 drop）
    _dragOverSub = web.EventStreamProviders.dragOverEvent
        .forTarget(target, useCapture: useCapture)
        .listen((event) {
          debugPrint('[UploadWebFolderDropTarget] dragover');
          event.preventDefault();
          if (!_dragging) {
            setState(() {
              _dragging = true;
            });
            widget.onDragEntered?.call();
          }
        });

    // Drag Leave
    _dragLeaveSub = web.EventStreamProviders.dragLeaveEvent
        .forTarget(target, useCapture: useCapture)
        .listen((event) {
          debugPrint('[UploadWebFolderDropTarget] dragleave');
          event.preventDefault();
          // Check if we are really leaving the window
          if (event.relatedTarget == null) {
            setState(() {
              _dragging = false;
            });
            widget.onDragExited?.call();
          }
        });

    // Drop
    _dropSub = web.EventStreamProviders.dropEvent
        .forTarget(target, useCapture: useCapture)
        .listen((
      event,
    ) async {
      debugPrint('[UploadWebFolderDropTarget] drop');
      try {
        event.preventDefault();
        setState(() {
          _dragging = false;
        });
        widget.onDragExited?.call();

        final dragEvent = event as web.DragEvent;
        final transfer = dragEvent.dataTransfer;
        if (transfer == null) {
          debugPrint('[UploadWebFolderDropTarget] drop: dataTransfer=null');
          return;
        }

        final onDrop = widget.onDropDataTransfer;
        if (onDrop != null) {
          await onDrop(transfer);
          debugPrint(
            '[UploadWebFolderDropTarget] drop: used onDropDataTransfer',
          );
          return;
        }

        final ctrl = widget.ctrl;
        if (ctrl == null) {
          debugPrint('[UploadWebFolderDropTarget] drop: ctrl=null');
          return;
        }

        final target = ctrl.currentPath.value ?? '/';
        debugPrint('[UploadWebFolderDropTarget] drop: target=$target');

        // 在首次 await 之前启动目录解析，先同步抓取 entry 引用，避免浏览器后续清空 dataTransfer。
        final filesFuture = UploadWebFileHelper.getFilesFromDataTransfer(
          transfer,
        );
        final supported = await ctrl.ensureUploadSupported();
        debugPrint('[UploadWebFolderDropTarget] drop: supported=$supported');
        final files = await filesFuture;
        if (!supported) return;
        debugPrint('[UploadWebFolderDropTarget] drop: parsedFiles=${files.length}');
        if (files.isEmpty) {
          debugPrint(
            '[UploadWebFolderDropTarget] drop: files empty (likely browser did not expose dropped files)',
          );
          return;
        }

        final first = files.first;
        final firstPath = first['path'];
        final firstFile = first['file'];
        String firstName = '';
        if (firstFile is web.File) {
          firstName = firstFile.name;
        }
        debugPrint(
          '[UploadWebFolderDropTarget] drop: firstPath=$firstPath firstName=$firstName',
        );

        final tc = Get.put(UploadController(), permanent: true);
        tc.uploadDroppedWebFiles(files, target);
        debugPrint('[UploadWebFolderDropTarget] drop: uploadDroppedWebFiles called');
      } catch (e, st) {
        debugPrint('[UploadWebFolderDropTarget] drop: exception=$e');
        debugPrint('$st');
      }
    });
  }

  @override
  void dispose() {
    _dragOverSub?.cancel();
    _dragLeaveSub?.cancel();
    _dropSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [widget.child, if (_dragging) const UploadDropAlertView()],
    );
  }
}
