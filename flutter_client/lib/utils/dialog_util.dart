import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:get/get.dart';

/// 对话框工具类，提供统一的对话框样式
class DialogUtil {
  static OverlayEntry? _loadingEntry;
  static bool _loadingEntryInserted = false;
  static bool _loadingInsertScheduled = false;
  static int _loadingRefCount = 0;
  static String _loadingMessage = '';
  static bool _loadingBarrierDismissible = false;

  static void _tryInsertLoadingEntry() {
    if (_loadingRefCount <= 0) return;
    if (_loadingEntryInserted) return;
    final context = Get.overlayContext ?? Get.context;
    if (context == null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _loadingEntry ??= OverlayEntry(
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _loadingBarrierDismissible
                      ? () => dismissLoading(force: true)
                      : null,
                  child: Container(color: Colors.black.withValues(alpha: 0.35)),
                ),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SpinKitThreeBounce(
                            color: theme.colorScheme.primary,
                            size: 26,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _loadingMessage,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    overlay.insert(_loadingEntry!);
    _loadingEntryInserted = true;
  }

  static void showLoading({
    String message = '',
    bool barrierDismissible = false,
  }) {
    _loadingRefCount += 1;
    _loadingMessage = message.isEmpty ? 'loading'.tr : message;
    _loadingBarrierDismissible = barrierDismissible;

    if (_loadingEntryInserted) {
      _loadingEntry?.markNeedsBuild();
      return;
    }

    if (_loadingInsertScheduled) return;

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase != SchedulerPhase.idle) {
      _loadingInsertScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadingInsertScheduled = false;
        if (_loadingRefCount <= 0) return;
        _tryInsertLoadingEntry();
        _loadingEntry?.markNeedsBuild();
      });
      return;
    }

    _tryInsertLoadingEntry();
    if (_loadingEntryInserted) {
      _loadingEntry?.markNeedsBuild();
      return;
    }

    _loadingInsertScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadingInsertScheduled = false;
      if (_loadingRefCount <= 0) return;
      _tryInsertLoadingEntry();
      _loadingEntry?.markNeedsBuild();
    });
  }

  static void dismissLoading({bool force = false}) {
    if (force) {
      _loadingRefCount = 0;
    } else if (_loadingRefCount > 0) {
      _loadingRefCount -= 1;
    }

    if (_loadingRefCount > 0) return;
    if (_loadingEntryInserted) {
      _loadingEntry?.remove();
    }
    _loadingEntry = null;
    _loadingEntryInserted = false;
    _loadingInsertScheduled = false;
  }

  /// 获取统一的AlertDialog样式配置
  static AlertDialog createAlertDialog({
    Widget? title,
    Widget? content,
    List<Widget>? actions,
    EdgeInsets? contentPadding,
    EdgeInsets? insetPadding,
    BoxConstraints? constraints,
  }) {
    return AlertDialog(
      title: title,
      content: content,
      actions: actions,
      contentPadding: contentPadding ?? const EdgeInsets.all(20),
      insetPadding: insetPadding ?? const EdgeInsets.all(20),
      constraints:
          constraints ?? const BoxConstraints(maxWidth: 400, minWidth: 280),
    );
  }

  /// 显示统一的加载对话框
  static Future<AlertDialog?> showLoadingDialog({
    String message = '',
    bool barrierDismissible = false,
  }) {
    if (message.isEmpty) {
      message = 'loading'.tr;
    }
    return showDialog<AlertDialog>(
      context: Get.overlayContext!,
      barrierDismissible: barrierDismissible,
      builder: (BuildContext context) {
        return createAlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Text(message),
            ],
          ),
        );
      },
    );
  }

  /// 显示统一的错误对话框
  static void showErrorDialog({required String message, String title = ''}) {
    if (title.isEmpty) {
      title = 'error'.tr;
    }
    showDialog(
      context: Get.overlayContext!,
      builder: (BuildContext context) {
        return createAlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Get.back();
              },
              child: Text('ok'.tr),
            ),
          ],
        );
      },
    );
  }

  /// 显示统一的信息提示对话框（单按钮）
  /// [scrollableContent] 为 true 时，内容超出高度可滚动
  static void showInfoDialog({
    required String title,
    required String content,
    String buttonText = '',
    VoidCallback? onPressed,
    bool scrollableContent = true,
    double? maxContentHeight,
  }) {
    if (buttonText.isEmpty) {
      buttonText = 'ok'.tr;
    }
    final contentWidget = scrollableContent
        ? ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxContentHeight ?? 400),
            child: SingleChildScrollView(child: SelectableText(content)),
          )
        : SelectableText(content);
    showDialog(
      context: Get.overlayContext!,
      builder: (BuildContext dialogContext) {
        return createAlertDialog(
          title: Text(title),
          content: contentWidget,
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                onPressed?.call();
              },
              child: Text(buttonText),
            ),
          ],
        );
      },
    );
  }

  /// 显示统一的确认对话框
  static Future<bool?> showConfirmDialog({
    required String title,
    required String content,
    VoidCallback? onConfirm,
    String confirmText = '',
    String cancelText = '',
    bool barrierDismissible = true,
    /// 为 true 时回车 / 小键盘回车等同点击确定
    bool confirmOnEnter = false,
  }) {
    if (confirmText.isEmpty) {
      confirmText = 'ok'.tr;
    }
    if (cancelText.isEmpty) {
      cancelText = 'cancel'.tr;
    }
    return showDialog<bool>(
      context: Get.overlayContext!,
      barrierDismissible: barrierDismissible,
      builder: (BuildContext context) {
        Widget dialog = createAlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            if (cancelText.isNotEmpty)
              TextButton(
                onPressed: () {
                  Get.back(result: false);
                },
                child: Text(cancelText),
              ),
            TextButton(
              onPressed: () {
                Get.back(result: true);
                onConfirm?.call();
              },
              child: Text(confirmText),
            ),
          ],
        );

        if (confirmOnEnter) {
          dialog = Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (ActivateIntent intent) {
                    Get.back(result: true);
                    onConfirm?.call();
                    return null;
                  },
                ),
              },
              child: Focus(
                autofocus: true,
                child: dialog,
              ),
            ),
          );
        }

        return dialog;
      },
    );
  }

  /// 显示带有三个按钮的确认对话框（取消、选项1、选项2）
  /// 返回值：
  /// - null: 对话框被取消
  /// - 0: 用户选择了选项1
  /// - 1: 用户选择了选项2
  static Future<int?> showConfirmThreeButtonsDialog({
    required String title,
    required String content,
    VoidCallback? onOption1,
    VoidCallback? onOption2,
    String cancelText = '',
    String option1Text = '',
    String option2Text = '',
    bool barrierDismissible = true,
    bool option2IsPrimary = false,
  }) {
    if (cancelText.isEmpty) {
      cancelText = 'cancel'.tr;
    }
    if (option1Text.isEmpty) {
      option1Text = 'ok'.tr;
    }
    if (option2Text.isEmpty) {
      option2Text = 'ok'.tr;
    }
    return showDialog<int>(
      context: Get.overlayContext!,
      barrierDismissible: barrierDismissible,
      builder: (BuildContext context) {
        return createAlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            // 取消按钮
            if (cancelText.isNotEmpty)
              TextButton(
                onPressed: () {
                  Get.back(result: null);
                },
                child: Text(cancelText),
              ),
            // 选项1按钮
            TextButton(
              onPressed: () {
                Get.back(result: 0);
                onOption1?.call();
              },
              child: Text(option1Text),
            ),
            // 选项2按钮（可以是主要按钮）
            ElevatedButton(
              style: option2IsPrimary
                  ? null
                  : ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
              onPressed: () {
                Get.back(result: 1);
                onOption2?.call();
              },
              child: Text(option2Text),
            ),
          ],
        );
      },
    );
  }

  /// 显示带输入框的密码输入对话框，返回用户输入的密码或 null
  static Future<String?> showPasswordInputDialogForResult({
    required String title,
    required String message,
    String confirmText = "",
    String cancelText = "",
    String hintText = "",
  }) {
    if (confirmText.isEmpty) {
      confirmText = 'ok'.tr;
    }
    if (cancelText.isEmpty) {
      cancelText = 'cancel'.tr;
    }
    if (hintText.isEmpty) {
      hintText = 'input_please'.tr;
    }
    var password = '';

    return showDialog<String>(
      context: Get.overlayContext!,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return createAlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message),
                  const SizedBox(height: 16),
                  TextFormField(
                    obscureText: true,
                    initialValue: '',
                    decoration: InputDecoration(
                      hintText: hintText,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onChanged: (value) {
                      password = value;
                      setState(() {});
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Get.back(result: null);
                  },
                  child: Text(cancelText),
                ),
                TextButton(
                  onPressed: password.trim().isEmpty
                      ? null
                      : () {
                          Get.back(result: password.trim());
                        },
                  child: Text(confirmText),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 显示带输入框的密码输入对话框
  static void showPasswordInputDialog({
    required String title,
    required String message,
    required Function(String) onConfirm,
    String confirmText = "",
    String cancelText = "",
    String hintText = "",
  }) {
    showPasswordInputDialogForResult(
      title: title,
      message: message,
      confirmText: confirmText,
      cancelText: cancelText,
      hintText: hintText,
    ).then((password) {
      if (password == null || password.trim().isEmpty) return;
      onConfirm(password);
    });
  }

  /// 显示带输入框的通用对话框，返回用户输入的文本或null
  static Future<String?> showInputDialog({
    required String title,
    required String content,
    String initialValue = '',
    String confirmText = '',
    String cancelText = '',
    String? Function(String?)? validator,
  }) {
    if (confirmText.isEmpty) {
      confirmText = 'ok'.tr;
    }
    if (cancelText.isEmpty) {
      cancelText = 'cancel'.tr;
    }
    var text = initialValue;
    String? errorText;

    return showDialog<String>(
      context: Get.overlayContext!,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return createAlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(content),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: initialValue,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      errorText: errorText,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    autofocus: true,
                    onChanged: (value) {
                      text = value;
                      setState(() {
                        errorText = validator?.call(value);
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Get.back(result: null);
                  },
                  child: Text(cancelText),
                ),
                TextButton(
                  onPressed: () {
                    final value = text.trim();
                    final validationError = validator?.call(value);
                    if (validationError == null) {
                      Get.back(result: value);
                    } else {
                      setState(() {
                        errorText = validationError;
                      });
                    }
                  },
                  child: Text(confirmText),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
