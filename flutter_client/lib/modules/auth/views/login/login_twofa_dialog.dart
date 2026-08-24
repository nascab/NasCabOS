import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/theme/dark_theme.dart';
import '../../../../utils/dimens_util.dart';
import '../../../../utils/dialog_util.dart';

class TwofaCodeDialog extends StatefulWidget {
  final void Function(String code) onVerify;
  final VoidCallback? onCancel;
  const TwofaCodeDialog({super.key, required this.onVerify, this.onCancel});

  @override
  State<TwofaCodeDialog> createState() => _TwofaCodeDialogState();
}

class _TwofaCodeDialogState extends State<TwofaCodeDialog> {
  final TextEditingController _codeController = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: darkTheme,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return DialogUtil.createAlertDialog(
            title: Text('auth_2fa_title'.tr),
            content: ConstrainedBox(
              constraints: DimensUtil.dialogMaxWidthConstraints,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'auth_2fa_code_label'.tr,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _codeController,
                    decoration: InputDecoration(
                      hintText: 'auth_2fa_code_hint'.tr,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      errorText: _errorText,
                    ),
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      setState(() {
                        _errorText = null;
                      });
                    },
                    onSubmitted: (_) => _tryVerify(),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      Get.dialog(
                        Theme(
                          data: darkTheme,
                          child: AlertDialog(
                            title: Text('auth_2fa_cannot_verify'.tr),
                            content: Text('auth_2fa_cannot_verify_hint'.tr),
                            actions: [
                              TextButton(
                                onPressed: () => Get.back(),
                                child: Text('ok'.tr),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    child: Text(
                      'auth_2fa_cannot_verify'.tr,
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  widget.onCancel?.call();
                  Get.back();
                },
                child: Text('cancel'.tr),
              ),
              TextButton(
                onPressed: _tryVerify,
                child: Text('auth_2fa_verify_button'.tr),
              ),
            ],
          );
        },
      ),
    );
  }

  void _tryVerify() {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _errorText = 'auth_2fa_code_required'.tr;
      });
      return;
    }
    widget.onVerify(code);
  }
}
