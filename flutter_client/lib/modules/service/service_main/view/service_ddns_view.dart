import 'package:NasCabOS/modules/base/components.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controller/service_main_controller.dart';
import '../../../base/components/custom_glass_card.dart';
import '../../../base/components/custom_switch.dart';
import '../../../../core/api/api_controller.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/server_version_util.dart';
import '../../../../utils/toast_util.dart';

class ServiceDdnsView extends StatefulWidget {
  final ServiceMainController controller;
  final bool showTitle;

  const ServiceDdnsView({
    super.key,
    required this.controller,
    this.showTitle = true,
  });

  @override
  State<ServiceDdnsView> createState() => _ServiceDdnsViewState();
}

class _ServiceDdnsViewState extends State<ServiceDdnsView> {
  final TextEditingController _domainCtrl = TextEditingController();
  bool _autoTypeSaved = false;
  bool _lowVersionDialogShown = false;

  @override
  void initState() {
    super.initState();
    Future(() async {
      if (_isServerVersionTooLow()) {
        _showLowServerVersionDialogOnce();
        return;
      }
      final ctrl = widget.controller;
      await ctrl.refreshDdnsStatus(showLoading: false, force: true);
      if (!mounted) return;
      if (_autoTypeSaved) return;
      final existingType = ctrl.ddnsType.value?.trim() ?? '';
      if (existingType.isNotEmpty) return;
      _autoTypeSaved = true;
      await ctrl.ensureDdnsTypeDefault(refresh: true);
    });
  }

  @override
  void dispose() {
    _domainCtrl.dispose();
    super.dispose();
  }

  bool _isServerVersionTooLow() {
    return !ServerVersionUtil.isAtLeast(ApiController.instance.serverVersion, 3);
  }

  void _showLowServerVersionDialogOnce() {
    if (_lowVersionDialogShown) return;
    _lowVersionDialogShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      DialogUtil.showInfoDialog(
        title: 'tip'.tr,
        content: 'server_version_too_low'.tr,
      );
    });
  }

  String _formatLocalDateTime(String raw) {
    final s0 = raw.trim();
    if (s0.isEmpty) return '';
    DateTime? dt = DateTime.tryParse(s0);
    if (dt == null && s0.contains(' ') && !s0.contains('T')) {
      dt = DateTime.tryParse(s0.replaceFirst(' ', 'T'));
    }
    if (dt == null) {
      final n = int.tryParse(s0);
      if (n != null) {
        final ms = n > 1000000000000 ? n : n * 1000;
        dt = DateTime.fromMillisecondsSinceEpoch(ms);
      }
    }
    if (dt == null) return s0;
    final loc = Get.locale?.toLanguageTag();
    return DateFormat.yMd(loc).add_Hms().format(dt.toLocal());
  }

  String _formatError(String raw) {
    final code = raw.trim();
    if (code.isEmpty) return '';
    final tr = code.tr;
    if (tr != code) return tr;
    return code;
  }

  Widget _buildRequestStateCard({
    required ThemeData theme,
    required bool loading,
  }) {
    if (loading) {
      return CustomGlassCard(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: CustomLoadingIndicator(
            message: 'loading'.tr,
            padding: EdgeInsets.zero,
          ),
        ),
      );
    }

    return CustomGlassCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.wifi_off_rounded,
            size: 32,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            'network_failure'.tr,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          CustomButton(
            text: 'retry'.tr,
            onPressed: () => widget.controller.refreshDdnsStatus(
              showLoading: true,
              force: true,
            ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_isServerVersionTooLow()) {
      _showLowServerVersionDialogOnce();
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showTitle)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'service_menu_remote_access_ddns'.tr,
                  style: theme.textTheme.titleLarge,
                ),
              ),
            CustomGlassCard(
              padding: const EdgeInsets.all(16),
              child: Text(
                '您的服务端版本太低，请升级到最新版本再使用此功能',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Obx(() {
      final ctrl = widget.controller;
      final loading = ctrl.ddnsLoading.value;
      final statusReady = ctrl.ddnsStatusReady.value;
      final statusLoadFailed = ctrl.ddnsStatusLoadFailed.value;
      final loggedIn = ctrl.nascabLoggedIn.value;
      final enabled = ctrl.ddnsEnabled.value;
      final ddnsType = ctrl.ddnsType.value?.trim() ?? '';
      final ddnsTypeDraft = ctrl.ddnsTypeDraft.value?.trim() ?? '';
      final domain = ctrl.ddnsDomain.value.trim();
      final fullDomain = ctrl.ddnsFullDomain.value.trim();
      final publicIp = ctrl.ddnsPublicIp.value.trim();
      final lastIp = ctrl.ddnsLastIp.value.trim();
      final lastTime = ctrl.ddnsLastTime.value.trim();
      final lastTimeFmt = _formatLocalDateTime(lastTime);
      final lastError = ctrl.ddnsLastError.value.trim();
      final deviceId = ctrl.ddnsDeviceId.value.trim();
      final needBind =
          deviceId.isEmpty || lastError == 'P2P.ERR_DEVICE_NOT_BIND';
      final typeSelected = ddnsTypeDraft.isNotEmpty
          ? ddnsTypeDraft
          : (ddnsType.isNotEmpty ? ddnsType : 'ipv4');
      final showRequestState = !statusReady;
      final showLoadingState = loading || !statusLoadFailed;

      if (_domainCtrl.text.trim() != domain && !loading) {
        _domainCtrl.text = domain;
      }

      return LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 420;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.showTitle)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'service_menu_remote_access_ddns'.tr,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                if (!loggedIn) ...[
                  CustomGlassCard(
                    padding: const EdgeInsets.all(14),
                    child: isNarrow
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.info_outline),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'service_nascab_not_logged_in'.tr,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton.tonal(
                                  onPressed: () =>
                                      ctrl.selectPage('account.nascab'),
                                  child: Text(
                                    'service_menu_account_nascab'.tr,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.info_outline),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'service_nascab_not_logged_in'.tr,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              TextButton(
                                onPressed: () =>
                                    ctrl.selectPage('account.nascab'),
                                child: Text('service_menu_account_nascab'.tr),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 12),
                ],
                CustomGlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'service_ddns_intro'.tr,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'service_ddns_toggle'.tr,
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'service_ddns_toggle_hint'.tr,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          CustomSwitch(
                            value: enabled,
                            onChanged:
                                !loggedIn ||
                                    needBind ||
                                    domain.isEmpty
                                ? null
                                : (v) async {
                                    final ok = await ctrl.setDdnsEnabled(v);
                                    if (!ok) {
                                      ToastUtil.show('operation_failed'.tr);
                                    }
                                  },
                          ),
                          IconButton(
                            tooltip: 'refresh'.tr,
                            onPressed: loading
                                ? null
                                : () => ctrl.refreshDdnsStatus(
                                    showLoading: true,
                                  ),
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (showRequestState)
                  SizedBox(
                    width: double.infinity,
                    child: _buildRequestStateCard(
                      theme: theme,
                      loading: showLoadingState,
                    ),
                  ),
                if (!showRequestState && loggedIn && needBind)
                  SizedBox(
                    width: double.infinity,
                    child: CustomGlassCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.link_off_rounded,
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.9,
                                ),
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'service_p2p_device_not_bind_message'.tr,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurface,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          CustomButton(
                            text: 'service_p2p_bind_device_button'.tr,
                            onPressed: loading
                                ? null
                                : () async {
                                    final result = await ctrl.bindP2pDevice();
                                    if (result['success'] == true) {
                                      ToastUtil.show('operation_success'.tr);
                                      await ctrl.refreshDdnsStatus(
                                        showLoading: false,
                                      );
                                    } else {
                                      final ec = result['errorCode']
                                              ?.toString()
                                              .trim() ??
                                          '';
                                      if (ec.isNotEmpty) {
                                        final tr = ec.tr;
                                        ToastUtil.show(tr != ec ? tr : ec);
                                      } else {
                                        ToastUtil.show('operation_failed'.tr);
                                      }
                                      await ctrl.refreshDdnsStatus(
                                        showLoading: false,
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.link_rounded, size: 18),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (!showRequestState && loggedIn && !needBind)
                  SizedBox(
                    width: double.infinity,
                    child: CustomGlassCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'service_ddns_domain_setting'.tr,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _domainCtrl,
                            enabled: !loading,
                            decoration: InputDecoration(
                              labelText: 'service_ddns_domain_prefix'.tr,
                              hintText: 'service_ddns_domain_prefix_hint'.tr,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          CustomButton(
                            text: 'save'.tr,
                            onPressed: loading
                                ? null
                                : () async {
                                    final nextPrefix = _domainCtrl.text.trim();
                                    final ok = await ctrl.setDdnsDomainPrefix(
                                      ddnsDomainPrefix: nextPrefix,
                                    );
                                    if (!ok) return;
                                    ToastUtil.show('operation_success'.tr);
                                  },
                            icon: const Icon(Icons.save_outlined, size: 18),
                          ),
                          if (fullDomain.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              fullDomain,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                if (!showRequestState && loggedIn && !needBind)
                  const SizedBox(height: 12),
                if (!showRequestState && loggedIn && !needBind)
                  SizedBox(
                    width: double.infinity,
                    child: CustomGlassCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'service_ddns_type'.tr,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 10),
                          RadioListTile<String>(
                            value: 'ipv4',
                            groupValue: typeSelected,
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            onChanged: loading
                                ? null
                                : (v) {
                                    if (v == null) return;
                                    ctrl.ddnsTypeDraft.value = v;
                                  },
                            title: Text('service_ddns_type_ipv4'.tr),
                          ),
                          RadioListTile<String>(
                            value: 'ipv6',
                            groupValue: typeSelected,
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            onChanged: loading
                                ? null
                                : (v) {
                                    if (v == null) return;
                                    ctrl.ddnsTypeDraft.value = v;
                                  },
                            title: Text('service_ddns_type_ipv6'.tr),
                          ),
                          const SizedBox(height: 12),
                          CustomButton(
                            text: 'save'.tr,
                            onPressed: loading || typeSelected.isEmpty
                                ? null
                                : () async {
                                    final ok = await ctrl.setDdnsTypeValue(
                                      typeSelected,
                                    );
                                    if (!ok) {
                                      ToastUtil.show('operation_failed'.tr);
                                      return;
                                    }
                                    ToastUtil.show('operation_success'.tr);
                                  },
                            icon: const Icon(Icons.save_outlined, size: 18),
                          ),
                          if (ddnsType.isNotEmpty && ddnsTypeDraft.isEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              '${'service_ddns_type'.tr}: ${ddnsType == 'ipv6' ? 'service_ddns_type_ipv6'.tr : 'service_ddns_type_ipv4'.tr}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                if (!showRequestState && loggedIn) const SizedBox(height: 12),
                if (!showRequestState && loggedIn)
                  CustomGlassCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'service_ddns_status'.tr,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        _InfoRow(
                          label: 'service_ddns_current_domain'.tr,
                          value: fullDomain.isEmpty ? '—' : fullDomain,
                        ),
                        _InfoRow(
                          label: 'service_ddns_public_ip'.tr,
                          value: publicIp.isEmpty ? '—' : publicIp,
                        ),
                        _InfoRow(
                          label: 'service_ddns_last_ip'.tr,
                          value: lastIp.isEmpty ? '—' : lastIp,
                        ),
                        _InfoRow(
                          label: 'service_ddns_last_time'.tr,
                          value: lastTimeFmt.isEmpty ? '—' : lastTimeFmt,
                        ),
                        if (lastError.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '${'service_ddns_last_error'.tr}: ${_formatError(lastError)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      );
    });
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
