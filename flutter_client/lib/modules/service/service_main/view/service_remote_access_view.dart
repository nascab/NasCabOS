import 'package:NasCabOS/modules/base/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controller/service_main_controller.dart';
import '../../../base/components/custom_glass_card.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/toast_util.dart';
import '../../../../core/config/nascab_endpoints.dart';

class ServiceRemoteAccessView extends StatefulWidget {
  final ServiceMainController controller;
  final bool showTitle;

  const ServiceRemoteAccessView({
    super.key,
    required this.controller,
    this.showTitle = true,
  });

  @override
  State<ServiceRemoteAccessView> createState() =>
      _ServiceRemoteAccessViewState();
}

class _ServiceRemoteAccessViewState extends State<ServiceRemoteAccessView> {
  @override
  void initState() {
    super.initState();
    widget.controller.startPairCodePolling();
  }

  @override
  void dispose() {
    widget.controller.stopPairCodePolling();
    super.dispose();
  }

  Future<String?> _showCustomPairCodeDialog(
    BuildContext context, {
    required String currentPairCode,
  }) async {
    final theme = Theme.of(context);
    final textCtrl = TextEditingController(text: currentPairCode);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return DialogUtil.createAlertDialog(
          title: Text('service_remote_access_custom_pair_code_title'.tr),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'service_remote_access_custom_pair_code_subtitle'.tr,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: textCtrl,
                autofocus: true,
                maxLength: 30,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9a-zA-Z]')),
                  LengthLimitingTextInputFormatter(30),
                ],
                decoration: InputDecoration(
                  hintText: 'service_remote_access_custom_pair_code_hint'.tr,
                  border: const OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('cancel'.tr),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(textCtrl.text.trim()),
              child: Text('confirm'.tr),
            ),
          ],
        );
      },
    );
    return result?.trim();
  }

  Map<String, String>? _findServerByDomain(
    List<Map<String, String>> servers,
    String domain,
  ) {
    final normalized = domain.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final item in servers) {
      final current = (item['domain'] ?? '').trim().toLowerCase();
      if (current == normalized) return item;
    }
    return null;
  }

  String _serverDisplayName(Map<String, String>? item) {
    if (item == null) return '';
    final languageCode = (Get.locale?.languageCode ?? '').toLowerCase();
    if (languageCode == 'zh') {
      final zh = (item['chinese_name'] ?? '').trim();
      if (zh.isNotEmpty) return zh;
    }
    final en = (item['english_name'] ?? '').trim();
    if (en.isNotEmpty) return en;
    final name = (item['name'] ?? '').trim();
    if (name.isNotEmpty) return name;
    return (item['domain'] ?? '').trim();
  }

  String _serverOptionLabel(Map<String, String>? item) {
    if (item == null) return '';
    final name = _serverDisplayName(item);
    final domain = (item['domain'] ?? '').trim();
    if (name.isEmpty) return domain;
    if (domain.isEmpty || domain == name) return name;
    return '$name · $domain';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final loading = widget.controller.remoteAccessLoading.value;
      final enabled = widget.controller.remoteAccessEnabled.value;
      final pairCode = widget.controller.pairCode.value.trim();
      final p2pErrorCode = widget.controller.p2pErrorCode.value.trim();
      final p2pConnectedDomain = widget.controller.p2pConnectedDomain.value
          .trim();
      final p2pFixNodeDomain = widget.controller.p2pFixNodeDomain.value.trim();
      final p2pServers = widget.controller.p2pServers.toList(growable: false);
      final loggedIn = widget.controller.nascabLoggedIn.value;
      const qrSize = 120.0;
      final currentConnectedServer = _findServerByDomain(
        p2pServers,
        p2pConnectedDomain,
      );
      final currentConnectedLabel = p2pConnectedDomain.isEmpty
          ? 'service_remote_access_node_connected_empty'.tr
          : _serverOptionLabel(currentConnectedServer).isNotEmpty
          ? _serverOptionLabel(currentConnectedServer)
          : p2pConnectedDomain;
      final nodeStatusKey = !enabled
          ? 'service_remote_access_node_status_disabled'
          : p2pErrorCode == 'P2P.ERR_DEVICE_NOT_BIND'
          ? 'service_remote_access_node_status_unbound'
          : p2pErrorCode.isNotEmpty
          ? 'service_remote_access_node_status_error'
          : p2pConnectedDomain.isNotEmpty
          ? 'service_remote_access_node_status_connected'
          : 'service_remote_access_node_status_connecting';
      final dropdownValue =
          p2pFixNodeDomain.isEmpty ||
              p2pServers.any(
                (item) =>
                    (item['domain'] ?? '').trim().toLowerCase() ==
                    p2pFixNodeDomain.toLowerCase(),
              )
          ? p2pFixNodeDomain
          : '';

      return LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 420;

          return Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.showTitle) ...[
                          Row(
                            children: [
                              Text(
                                'service_menu_remote_access'.tr,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: () async {
                                  final lang = Get.locale?.languageCode ?? 'zh';
                                  final uri = Uri.parse(
                                    '${NasCabEndpoints.websiteBaseUrl}/others/helpP2p.html?language=$lang',
                                  );
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(
                                      uri,
                                      mode: LaunchMode.externalApplication,
                                    );
                                  }
                                },
                                child: Text(
                                  'help'.tr,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: () =>
                                    widget.controller.openMyDevicesUrl(),
                                child: Text(
                                  'service_nascab_membership_my_devices'.tr,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (!loggedIn) ...[
                          CustomGlassCard(
                            padding: const EdgeInsets.all(14),
                            child: isNarrow
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(Icons.info_outline),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'service_nascab_not_logged_in'
                                                      .tr,
                                                  style: theme
                                                      .textTheme
                                                      .titleMedium
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  'service_nascab_not_logged_in_hint'
                                                      .tr,
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: theme
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: FilledButton.tonal(
                                          onPressed: () => widget.controller
                                              .selectPage('account.nascab'),
                                          child: Text(
                                            'service_menu_account_nascab'.tr,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.info_outline),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'service_nascab_not_logged_in'.tr,
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              'service_nascab_not_logged_in_hint'
                                                  .tr,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      TextButton(
                                        onPressed: () => widget.controller
                                            .selectPage('account.nascab'),
                                        child: Text(
                                          'service_menu_account_nascab'.tr,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        CustomGlassCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SwitchListTile(
                                activeColor: theme.colorScheme.primary,
                                contentPadding: EdgeInsets.zero,
                                title: Text('service_remote_access_toggle'.tr),
                                subtitle: Text(
                                  'service_remote_access_toggle_hint'.tr,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                value: enabled,
                                onChanged: loading
                                    ? null
                                    : (v) async {
                                        if (v && !loggedIn) {
                                          ToastUtil.show(
                                            'service_nascab_not_logged_in'.tr,
                                          );
                                          await widget.controller
                                              .refreshRemoteAccess();
                                          return;
                                        }
                                        final ok = await widget.controller
                                            .setRemoteAccessEnabled(v);
                                        if (!ok) {
                                          ToastUtil.show('operation_failed'.tr);
                                          await widget.controller
                                              .refreshRemoteAccess();
                                        }
                                      },
                              ),
                              if (enabled) ...[
                                const SizedBox(height: 10),
                                if (p2pErrorCode == 'P2P.ERR_DEVICE_NOT_BIND')
                                  CustomGlassCard(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Icon(
                                              Icons.link_off_rounded,
                                              color: theme.colorScheme.primary
                                                  .withValues(alpha: 0.9),
                                              size: 24,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                'service_p2p_device_not_bind_message'
                                                    .tr,
                                                style: theme
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      color: theme
                                                          .colorScheme
                                                          .onSurface,
                                                      height: 1.45,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        CustomButton(
                                          text: 'service_p2p_bind_device_button'
                                              .tr,
                                          onPressed: loading
                                              ? null
                                              : () async {
                                                  final result = await widget
                                                      .controller
                                                      .bindP2pDevice();
                                                  final ok =
                                                      result['success'] == true;
                                                  if (ok) {
                                                    ToastUtil.show(
                                                      'operation_success'.tr,
                                                    );
                                                  } else {
                                                    final errCode =
                                                        result['errorCode']
                                                            ?.toString()
                                                            .trim() ??
                                                        '';
                                                    if (errCode ==
                                                        'P2P.ERR_DEVICE_COUNT_LIMIT') {
                                                      final goDevices =
                                                          await DialogUtil.showConfirmDialog(
                                                            title:
                                                                'need_confirm'
                                                                    .tr,
                                                            content:
                                                                'P2P.ERR_DEVICE_COUNT_LIMIT'
                                                                    .tr,
                                                            confirmText:
                                                                'service_nascab_membership_my_devices'
                                                                    .tr,
                                                            cancelText:
                                                                'cancel'.tr,
                                                          );
                                                      if (goDevices == true) {
                                                        widget.controller
                                                            .openMyDevicesUrl();
                                                      }
                                                    } else {
                                                      ToastUtil.show(
                                                        'operation_failed'.tr,
                                                      );
                                                    }
                                                    await widget.controller
                                                        .refreshRemoteAccess();
                                                  }
                                                },
                                          icon: const Icon(
                                            Icons.link_rounded,
                                            size: 18,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else if (p2pErrorCode.isNotEmpty)
                                  CustomGlassCard(
                                    padding: const EdgeInsets.all(14),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.error_outline,
                                          color: theme.colorScheme.error,
                                          size: 22,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            p2pErrorCode.tr != p2pErrorCode
                                                ? p2pErrorCode.tr
                                                : p2pErrorCode,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  color:
                                                      theme.colorScheme.error,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else ...[
                                  if (isNarrow) ...[
                                    Text(
                                      'service_remote_access_pair_code_label'
                                          .tr,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      alignment: WrapAlignment.end,
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        TextButton(
                                          onPressed: loading
                                              ? null
                                              : () async {
                                                  final ok =
                                                      await DialogUtil.showConfirmDialog(
                                                        title:
                                                            'need_confirm'.tr,
                                                        content:
                                                            'service_remote_access_pair_code_reset_confirm'
                                                                .tr,
                                                        confirmText: 'reset'.tr,
                                                        cancelText: 'cancel'.tr,
                                                      );
                                                  if (ok != true) return;
                                                  final resetOk = await widget
                                                      .controller
                                                      .resetPairCode();
                                                  if (!resetOk) {
                                                    ToastUtil.show(
                                                      'operation_failed'.tr,
                                                    );
                                                    await widget.controller
                                                        .refreshRemoteAccess();
                                                    return;
                                                  }
                                                  ToastUtil.show(
                                                    'operation_success'.tr,
                                                  );
                                                },
                                          child: Text(
                                            'service_remote_access_pair_code_reset'
                                                .tr,
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: widget
                                              .controller
                                              .refreshRemoteAccess,
                                          child: Text('refresh'.tr),
                                        ),
                                      ],
                                    ),
                                  ] else ...[
                                    Row(
                                      children: [
                                        Text(
                                          'service_remote_access_pair_code_label'
                                              .tr,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const Spacer(),
                                        TextButton(
                                          onPressed: loading
                                              ? null
                                              : () async {
                                                  final ok =
                                                      await DialogUtil.showConfirmDialog(
                                                        title:
                                                            'need_confirm'.tr,
                                                        content:
                                                            'service_remote_access_pair_code_reset_confirm'
                                                                .tr,
                                                        confirmText: 'reset'.tr,
                                                        cancelText: 'cancel'.tr,
                                                      );
                                                  if (ok != true) return;
                                                  final resetOk = await widget
                                                      .controller
                                                      .resetPairCode();
                                                  if (!resetOk) {
                                                    ToastUtil.show(
                                                      'operation_failed'.tr,
                                                    );
                                                    await widget.controller
                                                        .refreshRemoteAccess();
                                                    return;
                                                  }
                                                  ToastUtil.show(
                                                    'operation_success'.tr,
                                                  );
                                                },
                                          child: Text(
                                            'service_remote_access_pair_code_reset'
                                                .tr,
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: widget
                                              .controller
                                              .refreshRemoteAccess,
                                          child: Text('refresh'.tr),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      SelectableText(
                                        pairCode.isEmpty
                                            ? 'service_remote_access_pair_code_empty'
                                                  .tr
                                            : pairCode,
                                        style: theme.textTheme.bodyLarge
                                            ?.copyWith(
                                              fontFamily: 'RobotoMono',
                                            ),
                                      ),
                                      IconButton(
                                        tooltip: 'copy'.tr,
                                        onPressed: pairCode.isNotEmpty
                                            ? () async {
                                                await Clipboard.setData(
                                                  ClipboardData(text: pairCode),
                                                );
                                                ToastUtil.show(
                                                  'service_remote_access_copied'
                                                      .tr,
                                                );
                                              }
                                            : null,
                                        icon: const Icon(Icons.copy_outlined),
                                      ),
                                      IconButton(
                                        tooltip:
                                            'service_remote_access_custom_pair_code_title'
                                                .tr,
                                        onPressed: loading || !loggedIn
                                            ? null
                                            : () async {
                                                final next =
                                                    await _showCustomPairCodeDialog(
                                                      context,
                                                      currentPairCode: pairCode,
                                                    );
                                                if (next == null ||
                                                    next.isEmpty) {
                                                  return;
                                                }
                                                if (!RegExp(
                                                  r'^[0-9a-zA-Z]{6,30}$',
                                                ).hasMatch(next)) {
                                                  ToastUtil.show(
                                                    'P2P_CUSTOM_PAIR_CODE_INVALID_FORMAT'
                                                        .tr,
                                                  );
                                                  return;
                                                }
                                                final ok = await widget
                                                    .controller
                                                    .customPairCode(next);
                                                if (ok) {
                                                  ToastUtil.show(
                                                    'operation_success'.tr,
                                                  );
                                                  return;
                                                }
                                                await widget.controller
                                                    .refreshRemoteAccess();
                                              },
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Align(
                                    alignment: isNarrow
                                        ? Alignment.center
                                        : Alignment.centerLeft,
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: theme.dividerColor.withValues(
                                            alpha: 0.4,
                                          ),
                                        ),
                                      ),
                                      child: pairCode.isNotEmpty
                                          ? QrImageView(
                                              data: pairCode,
                                              size: qrSize,
                                              backgroundColor: Colors.white,
                                              eyeStyle: const QrEyeStyle(
                                                eyeShape: QrEyeShape.square,
                                                color: Colors.black,
                                              ),
                                              dataModuleStyle:
                                                  const QrDataModuleStyle(
                                                    dataModuleShape:
                                                        QrDataModuleShape
                                                            .square,
                                                    color: Colors.black,
                                                  ),
                                            )
                                          : SizedBox(
                                              width: qrSize,
                                              height: qrSize,
                                              child: Center(
                                                child: Text(
                                                  'service_remote_access_pair_code_empty'
                                                      .tr,
                                                  textAlign: TextAlign.center,
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: theme
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                              ),
                                            ),
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (enabled) ...[
                          CustomGlassCard(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        Icons.hub_rounded,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'service_remote_access_node_title'
                                                .tr,
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'service_remote_access_node_subtitle'
                                                .tr,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                  height: 1.35,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'service_remote_access_node_current'.tr,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    SelectableText(
                                      currentConnectedLabel,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            nodeStatusKey ==
                                                'service_remote_access_node_status_connected'
                                            ? theme.colorScheme.primary
                                                  .withValues(alpha: 0.12)
                                            : theme
                                                  .colorScheme
                                                  .surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        nodeStatusKey.tr,
                                        style: theme.textTheme.labelLarge?.copyWith(
                                          color:
                                              nodeStatusKey ==
                                                  'service_remote_access_node_status_error'
                                              ? theme.colorScheme.error
                                              : theme.colorScheme.onSurface,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                DropdownButtonFormField<String>(
                                  value: dropdownValue,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText:
                                        'service_remote_access_node_label'.tr,
                                    helperText: p2pServers.isEmpty
                                        ? 'service_remote_access_node_server_list_empty'
                                              .tr
                                        : null,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  items: [
                                    DropdownMenuItem<String>(
                                      value: '',
                                      child: Text('auto'.tr),
                                    ),
                                    ...p2pServers.map((item) {
                                      final domain = (item['domain'] ?? '')
                                          .trim();
                                      return DropdownMenuItem<String>(
                                        value: domain,
                                        child: Text(
                                          _serverOptionLabel(item),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }),
                                  ],
                                  onChanged: loading
                                      ? null
                                      : (value) async {
                                          final next = (value ?? '').trim();
                                          if (next == p2pFixNodeDomain.trim()) {
                                            return;
                                          }
                                          final ok = await widget.controller
                                              .setP2pNodePreference(next);
                                          if (!ok) {
                                            ToastUtil.show(
                                              'service_remote_access_node_save_failed'
                                                  .tr,
                                            );
                                            await widget.controller
                                                .refreshRemoteAccess(
                                                  showLoading: false,
                                                );
                                            return;
                                          }
                                          ToastUtil.show(
                                            'service_remote_access_node_saved'
                                                .tr,
                                          );
                                        },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        CustomGlassCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'service_remote_access_guide_title'.tr,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'service_remote_access_guide_how_title'.tr,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'service_remote_access_guide_how_body'.tr,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'service_remote_access_guide_use_title'.tr,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'service_remote_access_guide_use_body'.tr,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (loading)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: theme.colorScheme.surface.withValues(alpha: 0.2),
                      child: const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );
    });
  }
}
