import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/modules/base/components/custom_no_data.dart';

import '../../base/components.dart';
import '../../base/components/custom_glass_card.dart';
import '../../files/views/folder_picker_dialog.dart';
import '../../home/views/pc_home_controller.dart';
import '../../service/service_main/controller/service_main_controller.dart';
import '../../service/service_main/view/service_main_view.dart';
import '../../service/service_main/view/service_mobile_view.dart';
import '../../../utils/dialog_util.dart';
import '../../../utils/device_utils.dart';
import '../../../utils/toast_util.dart';
import '../controllers/quick_share_config_controller.dart';

class QuickShareConfigView extends StatefulWidget {
  final String? initialCreatePath;
  final bool showTitle;

  const QuickShareConfigView({
    super.key,
    this.initialCreatePath,
    this.showTitle = true,
  });

  @override
  State<QuickShareConfigView> createState() => _QuickShareConfigViewState();
}

class _QuickShareConfigViewState extends State<QuickShareConfigView> {
  QuickShareConfigController? _latestCtrl;
  Worker? _homeWorker;
  String? _pendingCreatePath;
  int? _pendingCreateNonce;
  bool _openScheduled = false;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    final argPath = args is Map
        ? (args['quickShareCreatePath']?.toString() ?? '')
        : '';
    final init = (widget.initialCreatePath ?? argPath).trim();
    if (init.isNotEmpty) {
      _pendingCreatePath = init;
      _scheduleOpenPending();
    }

    if (Get.isRegistered<PcHomeController>()) {
      final home = PcHomeController.instance;
      _homeWorker = ever<int>(home.quickShareCreateNonce, (nonce) {
        final handled = home.quickShareCreateHandledNonce.value;
        if (nonce <= handled) return;
        _pendingCreateNonce = nonce;
        _pendingCreatePath = (home.quickShareCreatePath.value ?? '').trim();
        if (_pendingCreatePath!.isNotEmpty) {
          _scheduleOpenPending();
        }
      });

      final nonce = home.quickShareCreateNonce.value;
      final handled = home.quickShareCreateHandledNonce.value;
      final p = (home.quickShareCreatePath.value ?? '').trim();
      if (nonce > handled && p.isNotEmpty) {
        _pendingCreateNonce = nonce;
        _pendingCreatePath = p;
        _scheduleOpenPending();
      }
    }
  }

  @override
  void dispose() {
    _homeWorker?.dispose();
    super.dispose();
  }

  void _scheduleOpenPending() {
    if (_openScheduled) return;
    _openScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openScheduled = false;
      _openPendingIfPossible();
    });
  }

  void _openPendingIfPossible() {
    if (!mounted) return;
    final ctrl = _latestCtrl;
    if (ctrl == null) return;
    final p = (_pendingCreatePath ?? '').trim();
    if (p.isEmpty) return;
    _pendingCreatePath = null;
    final nonce = _pendingCreateNonce;
    _pendingCreateNonce = null;
    if (nonce != null && Get.isRegistered<PcHomeController>()) {
      final home = PcHomeController.instance;
      home.quickShareCreateHandledNonce.value = nonce;
      home.quickShareCreatePath.value = null;
    }
    _showCreateDialog(context, ctrl, preFilledPath: p);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    return GetBuilder<QuickShareConfigController>(
      init: QuickShareConfigController(),
      builder: (ctrl) {
        _latestCtrl = ctrl;
        if (_pendingCreatePath != null) {
          _scheduleOpenPending();
        }
        return Container(
          color: customColors?.mainContentBgColor,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: CustomGlassCard(
                  child: Row(
                    children: [
                      if (widget.showTitle)
                        Expanded(child: Text('quick_share_title'.tr))
                      else
                        const Spacer(),
                      CustomButton(
                        text: 'quick_share_clean_expired'.tr,
                        onPressed: ctrl.cleanExpired,
                        icon: const Icon(Icons.cleaning_services_outlined),
                      ),
                      const SizedBox(width: 8),
                      CustomButton(
                        text: 'quick_share_create'.tr,
                        onPressed: () => _showCreateDialog(context, ctrl),
                        icon: const Icon(Icons.add_outlined),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Obx(() {
                  final list = ctrl.items;
                  return list.isEmpty
                      ? CustomNoData(text: 'no_data'.tr)
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: list.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 14),
                          itemBuilder: (itemCtx, i) {
                            final item = list[i];
                            return _ShareItemCard(
                              item: item,
                              ctrl: ctrl,
                              onTapLocalLink: (url) => _showQrCodeDialog(
                                itemCtx,
                                initialUrl: url,
                                isRemote: false,
                              ),
                              onTapRemoteLink: (url) => _showQrCodeDialog(
                                itemCtx,
                                initialUrl: url,
                                isRemote: true,
                              ),
                              onTapRemoteGuide: _goToRemoteAccess,
                            );
                          },
                        );
                }),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCreateDialog(
    BuildContext context,
    QuickShareConfigController ctrl, {
    String? preFilledPath,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) {
        return _QuickShareCreateDialog(
          ctrl: ctrl,
          preFilledPath: preFilledPath,
        );
      },
    );
  }

  Future<void> _showQrCodeDialog(
    BuildContext context, {
    required String initialUrl,
    bool isRemote = false,
  }) async {
    final urlCtrl = TextEditingController(text: initialUrl);
    final ctrl = _latestCtrl;
    String qrText = initialUrl;

    await showDialog<void>(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return DialogUtil.createAlertDialog(
              title: Text('quick_share_qr_title'.tr),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomTextField(
                      controller: urlCtrl,
                      labelText: 'quick_share_link'.tr,
                      maxLines: 2,
                      readOnly: isRemote,
                      suffixIcon: isRemote
                          ? null
                          : Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: TextButton(
                                onPressed: () {
                                  final v = urlCtrl.text.trim();
                                  if (v.isEmpty) return;
                                  setState(() => qrText = v);
                                },
                                child: Text('quick_share_qr_generate'.tr),
                              ),
                            ),
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: QrImageView(
                          data: qrText,
                          size: 200,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Get.back<void>();
                    ctrl?.copyText(qrText);
                  },
                  child: Text('quick_share_copy_link'.tr),
                ),
                TextButton(
                  onPressed: () => Get.back<void>(),
                  child: Text('ok'.tr),
                ),
              ],
            );
          },
        );
      },
    );
    urlCtrl.dispose();
  }

  void _goToRemoteAccess() {
    if (DeviceUtils.isMobile) {
      if (!Get.isRegistered<ServiceMainController>()) {
        Get.put<ServiceMainController>(
          ServiceMainController(),
          permanent: true,
        );
      }
      final ctrl = Get.find<ServiceMainController>();
      ctrl.selectPage('account.remote_access');
      Get.to(() => const ServiceMobileView());
      return;
    }
    if (Get.isRegistered<PcHomeController>()) {
      final home = PcHomeController.instance;
      home.openApp(
        windowId: 'nascab_service',
        viewBuilder: (_) =>
            const ServiceMainView(initialPageKey: 'account.remote_access'),
        title: 'app_nascab_service'.tr,
        icon: home.buildAppIcon('nascab_service'),
      );
      return;
    }
    Get.to(
      () => const ServiceMainView(initialPageKey: 'account.remote_access'),
    );
  }
}

class _QuickShareCreateDialog extends StatefulWidget {
  final QuickShareConfigController ctrl;
  final String? preFilledPath;
  const _QuickShareCreateDialog({required this.ctrl, this.preFilledPath});

  @override
  State<_QuickShareCreateDialog> createState() =>
      _QuickShareCreateDialogState();
}

class _QuickShareCreateDialogState extends State<_QuickShareCreateDialog> {
  late final TextEditingController _pathCtrl;
  late final TextEditingController _pwdCtrl;
  late final TextEditingController _remarkCtrl;
  late final TextEditingController _durationCtrl;
  bool _noLimit = false;
  String _unit = 'day';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final initPath = (widget.preFilledPath ?? '').trim();
    _pathCtrl = TextEditingController(text: initPath);
    _pwdCtrl = TextEditingController();
    _remarkCtrl = TextEditingController();
    _durationCtrl = TextEditingController(text: '7');
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    _pwdCtrl.dispose();
    _remarkCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPath() async {
    final list = await showFolderPickerBottomSheet(
      context,
      multiSelect: false,
      allowFileSelect: true,
    );
    if (!mounted) return;
    if (list == null || list.isEmpty) return;
    setState(() {
      _pathCtrl.text = list.first;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final path = _pathCtrl.text.trim();
    if (path.isEmpty) {
      ToastUtil.show('quick_share_path_required'.tr);
      return;
    }
    final pwd = _pwdCtrl.text.trim();
    if (pwd.isEmpty) {
      ToastUtil.show('quick_share_password_required'.tr);
      return;
    }
    final durationValue = int.tryParse(_durationCtrl.text.trim());
    setState(() => _submitting = true);
    try {
      final ok = await widget.ctrl.createShare(
        path: path,
        pwd: pwd,
        remark: _remarkCtrl.text.trim().isEmpty
            ? null
            : _remarkCtrl.text.trim(),
        durationValue: _noLimit ? null : durationValue,
        durationUnit: _unit,
        noLimit: _noLimit,
      );
      if (ok && mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxDialogBodyHeight = MediaQuery.of(context).size.height * 0.55;
    return WillPopScope(
      onWillPop: () async => !_submitting,
      child: DialogUtil.createAlertDialog(
        title: Text('quick_share_create'.tr),
        content: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxDialogBodyHeight),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomTextField(
                    controller: _pathCtrl,
                    labelText: 'path'.tr,
                    hintText: 'quick_share_path_hint'.tr,
                    readOnly: true,
                    onTap: _submitting ? null : _pickPath,
                    suffixIcon: const Icon(Icons.folder_outlined),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pwdCtrl,
                    decoration: InputDecoration(
                      labelText: 'quick_share_password'.tr,
                      hintText: 'quick_share_password_hint'.tr,
                    ),
                    obscureText: true,
                    enabled: !_submitting,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _remarkCtrl,
                    decoration: InputDecoration(
                      labelText: 'quick_share_remark'.tr,
                      hintText: 'quick_share_remark_hint'.tr,
                    ),
                    enabled: !_submitting,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _durationCtrl,
                          decoration: InputDecoration(
                            labelText: 'quick_share_duration'.tr,
                            hintText: 'quick_share_duration_hint'.tr,
                          ),
                          enabled: !_submitting && !_noLimit,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 10),
                      DropdownButton<String>(
                        value: _unit,
                        items: [
                          DropdownMenuItem(
                            value: 'day',
                            child: Text('quick_share_unit_day'.tr),
                          ),
                          DropdownMenuItem(
                            value: 'hour',
                            child: Text('quick_share_unit_hour'.tr),
                          ),
                        ],
                        onChanged: (_submitting || _noLimit)
                            ? null
                            : (v) {
                                if (v == null) return;
                                setState(() => _unit = v);
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                        value: _noLimit,
                        onChanged: _submitting
                            ? null
                            : (v) => setState(() => _noLimit = v == true),
                      ),
                      Expanded(child: Text('quick_share_no_limit'.tr)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('ok'.tr),
          ),
        ],
      ),
    );
  }
}

class _ShareItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final QuickShareConfigController ctrl;
  final ValueChanged<String> onTapLocalLink;
  final ValueChanged<String> onTapRemoteLink;
  final VoidCallback onTapRemoteGuide;
  const _ShareItemCard({
    required this.item,
    required this.ctrl,
    required this.onTapLocalLink,
    required this.onTapRemoteLink,
    required this.onTapRemoteGuide,
  });

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is int) {
      final ms = v > 9999999999 ? v : v * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    final s = v.toString();
    return DateTime.tryParse(s);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = int.tryParse(item['id']?.toString() ?? '') ?? 0;
    final path = item['path']?.toString() ?? '';
    final token = item['token']?.toString() ?? '';
    final pwd = item['pwd']?.toString() ?? '';
    final hasPwd = (item['hasPwd'] == true) || pwd.trim().isNotEmpty;
    final end = _parseDate(item['end_time']);
    final localUrl = ctrl.buildLocalShareUrl(token);
    final remoteUrl = ctrl.buildRemoteShareUrl(token);
    final metaIconColor = theme.colorScheme.onSurfaceVariant;

    return CustomGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder_outlined, size: 18, color: metaIconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    path,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'delete'.tr,
                  onPressed: id <= 0
                      ? null
                      : () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => DialogUtil.createAlertDialog(
                              title: Text('delete'.tr),
                              content: Text('quick_share_delete_confirm'.tr),
                              actions: [
                                TextButton(
                                  onPressed: () => Get.back(result: false),
                                  child: Text('cancel'.tr),
                                ),
                                TextButton(
                                  onPressed: () => Get.back(result: true),
                                  child: Text('ok'.tr),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) await ctrl.deleteShare(id);
                        },
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.link_outlined, size: 16, color: metaIconColor),
                const SizedBox(width: 6),
                Flexible(
                  fit: FlexFit.loose,
                  child: InkWell(
                    onTap: () => onTapLocalLink(localUrl),
                    child: Text(
                      '${'quick_share_local_link'.tr}: $localUrl',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => ctrl.copyText(localUrl),
                  child: Text('quick_share_copy_link'.tr),
                ),
              ],
            ),
            if (remoteUrl.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.public_outlined, size: 16, color: metaIconColor),
                  const SizedBox(width: 6),
                  Flexible(
                    fit: FlexFit.loose,
                    child: InkWell(
                      onTap: () => onTapRemoteLink(remoteUrl),
                      child: Text(
                        '${'quick_share_remote_link'.tr}: $remoteUrl',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => ctrl.copyText(remoteUrl),
                    child: Text('quick_share_copy_link'.tr),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.public_outlined, size: 16, color: metaIconColor),
                  const SizedBox(width: 6),
                  Flexible(
                    fit: FlexFit.loose,
                    child: InkWell(
                      onTap: onTapRemoteGuide,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${'quick_share_remote_link'.tr}: '),
                            TextSpan(
                              text: 'quick_share_remote_link_guide'.tr,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: onTapRemoteGuide,
                    child: Text('go_to'.tr),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.lock_outline, size: 16, color: metaIconColor),
                const SizedBox(width: 6),
                Flexible(
                  fit: FlexFit.loose,
                  child: (!hasPwd || id <= 0)
                      ? Text(
                          hasPwd
                              ? '${'quick_share_password'.tr}: ••••'
                              : 'quick_share_no_password'.tr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : Obx(() {
                          ctrl.revealPwdIds.length;
                          final show = ctrl.revealPwdIds.contains(id);
                          final display = show
                              ? (pwd.isNotEmpty ? pwd : '••••')
                              : '••••';
                          return Text(
                            '${'quick_share_password'.tr}: $display',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          );
                        }),
                ),
                if (hasPwd && id > 0) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => ctrl.togglePwdReveal(id),
                    child: Obx(() {
                      ctrl.revealPwdIds.length;
                      final show = ctrl.revealPwdIds.contains(id);
                      return Text(
                        show ? 'quick_share_hide'.tr : 'quick_share_show'.tr,
                      );
                    }),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.schedule_outlined, size: 16, color: metaIconColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    end == null
                        ? 'quick_share_end_time_none'.tr
                        : '${'quick_share_end_time'.tr}: ${end.toLocal().toString().substring(0, 16)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
