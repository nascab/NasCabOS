part of '../user_management_view.dart';

class _UserManagementTwofaTab extends StatelessWidget {
  final int uid;
  final Map<String, dynamic> user;
  final UserManagementController ctrl;
  const _UserManagementTwofaTab({
    required this.uid,
    required this.user,
    required this.ctrl,
  });

  @override
  Widget build(BuildContext context) {
    return GetBuilder<UserManagementController>(
      id: 'twofa_$uid',
      builder: (ctrl) {
        if (!ctrl.userTwofaStatus.containsKey(uid)) {
          ctrl.getTwofaStatus(uid);
        }

        final loading = ctrl.userTwofaLoading[uid] == true;
        final status = ctrl.userTwofaStatus[uid] ?? <String, dynamic>{};

        if (status.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final enabled = status['enabled'] == true;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TwofaEnabledRow(
                uid: uid,
                enabled: enabled,
                loading: loading,
                user: user,
                ctrl: ctrl,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TwofaEnabledRow extends StatelessWidget {
  final int uid;
  final bool enabled;
  final bool loading;
  final Map<String, dynamic> user;
  final UserManagementController ctrl;
  const _TwofaEnabledRow({
    required this.uid,
    required this.enabled,
    required this.loading,
    required this.user,
    required this.ctrl,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  'user_mgmt_2fa_enabled_switch'.tr,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              IconButton(
                tooltip: 'user_mgmt_2fa_help'.tr,
                onPressed: () {
                  DialogUtil.showInfoDialog(
                    title: 'tip'.tr,
                    content: 'user_mgmt_2fa_help'.tr,
                    buttonText: 'ok'.tr,
                  );
                },
                icon: Icon(
                  Icons.help_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        CustomSwitch(
          value: enabled,
          onChanged: loading ? null : (v) => _onToggle(context, v),
        ),
      ],
    );
  }

  Future<void> _onToggle(BuildContext context, bool v) async {
    if (v == enabled) {
      return;
    }
    if (!v) {
      final ok = await DialogUtil.showConfirmDialog(
        title: 'need_confirm'.tr,
        content: 'user_mgmt_2fa_disable_confirm'.tr,
        confirmText: 'ok'.tr,
        cancelText: 'cancel'.tr,
      );
      if (ok == true) {
        await ctrl.resetTwofa(uid);
      }
      return;
    }

    final setupData = await ctrl.setupTwofa(
      uid,
      accountName: user['username']?.toString(),
    );
    if (setupData == null) {
      return;
    }

    if (!context.mounted) {
      return;
    }

    final ok = await _showTwofaBindDialog(
      context: context,
      uid: uid,
      ctrl: ctrl,
      setupData: setupData,
    );
    if (ok == true) {
      await ctrl.refreshTwofaStatus(uid);
    }
  }
}

Future<bool?> _showTwofaBindDialog({
  required BuildContext context,
  required int uid,
  required UserManagementController ctrl,
  required Map<String, dynamic> setupData,
}) async {
  Uint8List? dialogQrBytes;
  final dialogQrDataUrl = setupData['qrDataUrl']?.toString();
  if (dialogQrDataUrl != null && dialogQrDataUrl.contains(',')) {
    try {
      final b64 = dialogQrDataUrl.split(',').last;
      dialogQrBytes = base64Decode(b64.trim());
    } catch (_) {
      dialogQrBytes = null;
    }
  }

  final codeCtrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      final bytes = dialogQrBytes;
      return AlertDialog(
        title: Text('user_mgmt_2fa_bind_title'.tr),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('user_mgmt_2fa_bind_tip'.tr),
              if (bytes != null) ...[
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Image.memory(bytes, width: 220, height: 220),
                  ),
                ),
              ],
              if (setupData['secret'] != null) ...[
                const SizedBox(height: 12),
                SelectableText(
                  '${'user_mgmt_2fa_secret'.tr}: ${setupData['secret']}',
                ),
              ],
              const SizedBox(height: 12),
              CustomTextField(
                controller: codeCtrl,
                labelText: 'user_mgmt_2fa_code_label'.tr,
                hintText: 'user_mgmt_2fa_code_hint'.tr,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () async {
              final code = codeCtrl.text.trim();
              if (code.isEmpty) {
                DialogUtil.showErrorDialog(
                  message: 'auth_2fa_code_required'.tr,
                );
                return;
              }

              final success = await ctrl.enableTwofa(uid, code: code);
              if (success) {
                if (!dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop(true);
              }
            },
            child: Text('user_mgmt_2fa_bind_action'.tr),
          ),
        ],
      );
    },
  );
  codeCtrl.dispose();
  return ok;
}
