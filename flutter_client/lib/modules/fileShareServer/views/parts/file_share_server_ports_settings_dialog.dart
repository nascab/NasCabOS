part of '../file_share_server_view.dart';

class _PortsSettingsView extends StatefulWidget {
  final FileShareServerController ctrl;
  const _PortsSettingsView({required this.ctrl});

  @override
  State<_PortsSettingsView> createState() => _PortsSettingsViewState();
}

class _PortsSettingsViewState extends State<_PortsSettingsView> {
  final Map<String, TextEditingController> _httpControllers = {};
  final Map<String, TextEditingController> _httpsControllers = {};
  final Map<String, bool> _savingByType = {};
  final Map<String, String?> _httpErrorByType = {};
  final Map<String, String?> _httpsErrorByType = {};

  @override
  void initState() {
    super.initState();
    for (final t in FileShareServerController.supportedTypes) {
      _httpControllers[t] = TextEditingController();
      _httpsControllers[t] = TextEditingController();
      _savingByType[t] = false;
      _httpErrorByType[t] = null;
      _httpsErrorByType[t] = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFromCtrl());
  }

  @override
  void dispose() {
    for (final c in _httpControllers.values) {
      c.dispose();
    }
    for (final c in _httpsControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncFromCtrl() {
    for (final t in FileShareServerController.supportedTypes) {
      final ports = widget.ctrl.portsByType[t] ?? {};
      final httpPort = ports['http_port']?.toString() ?? '';
      final httpsPort = ports['https_port']?.toString() ?? '';
      _httpControllers[t]?.text = httpPort;
      _httpsControllers[t]?.text = t == 'WebDav' ? httpsPort : '';
    }
    setState(() {});
  }

  void _ensureTypeSynced(String type) {
    final ports = widget.ctrl.portsByType[type] ?? {};
    final httpPort = ports['http_port']?.toString() ?? '';
    final httpsPort = ports['https_port']?.toString() ?? '';

    final httpCtrl = _httpControllers[type];
    final httpsCtrl = _httpsControllers[type];

    if (httpCtrl == null || httpsCtrl == null) return;
    final desiredHttps = type == 'WebDav' ? httpsPort : '';
    if (httpCtrl.text == httpPort && httpsCtrl.text == desiredHttps) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (httpCtrl.text != httpPort) httpCtrl.text = httpPort;
      if (httpsCtrl.text != desiredHttps) httpsCtrl.text = desiredHttps;
    });
  }

  int? _parsePort(String text) {
    final v = text.trim();
    if (v.isEmpty) return null;
    final n = int.tryParse(v);
    if (n == null) return null;
    if (n < 1 || n > 65535) return null;
    return n;
  }

  void _clearTypeErrors(String type) {
    _httpErrorByType[type] = null;
    _httpsErrorByType[type] = null;
  }

  Future<void> _saveType(String type) async {
    if (_savingByType[type] == true) return;
    final httpText = _httpControllers[type]?.text ?? '';
    final httpsText = _httpsControllers[type]?.text ?? '';

    final httpPort = httpText.trim().isEmpty ? null : _parsePort(httpText);
    final httpsPort = type == 'WebDav'
        ? (httpsText.trim().isEmpty ? null : _parsePort(httpsText))
        : null;

    if ((httpText.trim().isNotEmpty && httpPort == null) ||
        (type == 'WebDav' &&
            httpsText.trim().isNotEmpty &&
            httpsPort == null)) {
      setState(() {
        _clearTypeErrors(type);
        if (httpText.trim().isNotEmpty && httpPort == null) {
          _httpErrorByType[type] = 'file_share_server_port_invalid'.tr;
        }
        if (type == 'WebDav' &&
            httpsText.trim().isNotEmpty &&
            httpsPort == null) {
          _httpsErrorByType[type] = 'file_share_server_port_invalid'.tr;
        }
      });
      DialogUtil.showErrorDialog(
        title: 'file_share_server_ports_save_failed_title'.tr,
        message: 'file_share_server_port_invalid'.tr,
      );
      return;
    }
    if (type == 'WebDav' &&
        httpPort != null &&
        httpsPort != null &&
        httpPort == httpsPort) {
      setState(() {
        _clearTypeErrors(type);
        _httpErrorByType[type] = 'file_share_server_port_invalid'.tr;
        _httpsErrorByType[type] = 'file_share_server_port_invalid'.tr;
      });
      DialogUtil.showErrorDialog(
        title: 'file_share_server_ports_save_failed_title'.tr,
        message: 'file_share_server_port_invalid'.tr,
      );
      return;
    }

    setState(() {
      _savingByType[type] = true;
      _clearTypeErrors(type);
    });

    try {
      final res = await widget.ctrl.setPorts(
        serverType: type,
        httpPort: httpPort,
        httpsPort: httpsPort,
      );
      if (res.success) return;

      // 解析后端返回的结构化错误（code/details），以便提供字段级提示和建议方案
      final raw = res.rawResponse;
      final details = raw is Map ? raw['details'] : null;
      final suggested = details is Map ? details['suggestedRange'] : null;
      final minPort = suggested is Map ? suggested['min']?.toString() : null;
      final maxPort = suggested is Map ? suggested['max']?.toString() : null;

      final message = res.message ?? 'operation_failed'.tr;
      final fields = details is Map ? details['fields'] : null;
      final fieldsList = fields is List
          ? fields.map((e) => e.toString()).toList()
          : const <String>[];

      setState(() {
        if (fieldsList.isEmpty || fieldsList.contains('http_port')) {
          _httpErrorByType[type] = message;
        }
        if (type == 'WebDav' &&
            (fieldsList.isEmpty || fieldsList.contains('https_port'))) {
          _httpsErrorByType[type] = message;
        }
      });

      final reasonText =
          '${'file_share_server_ports_save_failed_reason_label'.tr}$message';
      final solutionText = (minPort != null && maxPort != null)
          ? '${'file_share_server_ports_save_failed_solution_label'.tr}${'file_share_server_ports_save_failed_solution_range'.trParams({'min': minPort, 'max': maxPort})}'
          : '${'file_share_server_ports_save_failed_solution_label'.tr}${'file_share_server_ports_save_failed_solution_default'.tr}';

      DialogUtil.showErrorDialog(
        title: 'file_share_server_ports_save_failed_title'.tr,
        message: '$reasonText\n\n$solutionText',
      );
    } finally {
      if (mounted) {
        setState(() => _savingByType[type] = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    return Obx(() {
      widget.ctrl.portsByType.length;
      for (final t in FileShareServerController.supportedTypes) {
        _ensureTypeSynced(t);
      }

      return Container(
        color: customColors?.mainContentBgColor,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  children: FileShareServerController.supportedTypes
                      .map(
                        (t) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: CustomGlassCard(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          t == 'WebDav'
                                              ? 'file_share_server_webdav'.tr
                                              : t == 'FTP'
                                              ? 'file_share_server_ftp'.tr
                                              : 'file_share_server_sftp'.tr,
                                          style: theme.textTheme.titleSmall,
                                        ),
                                      ),
                                      CustomButton(
                                        text: 'save'.tr,
                                        onPressed: () => _saveType(t),
                                        isDisabled: _savingByType[t] == true,
                                        icon: _savingByType[t] == true
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(Icons.save_outlined),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (t == 'WebDav')
                                    _WebDavPortsEditor(
                                      httpController: _httpControllers[t]!,
                                      httpsController: _httpsControllers[t]!,
                                      httpErrorText: _httpErrorByType[t],
                                      httpsErrorText: _httpsErrorByType[t],
                                      onHttpChanged: (_) {
                                        if (_httpErrorByType[t] == null) return;
                                        setState(
                                          () => _httpErrorByType[t] = null,
                                        );
                                      },
                                      onHttpsChanged: (_) {
                                        if (_httpsErrorByType[t] == null)
                                          return;
                                        setState(
                                          () => _httpsErrorByType[t] = null,
                                        );
                                      },
                                    )
                                  else
                                    _SinglePortEditor(
                                      controller: _httpControllers[t]!,
                                      errorText: _httpErrorByType[t],
                                      onChanged: (_) {
                                        if (_httpErrorByType[t] == null) return;
                                        setState(
                                          () => _httpErrorByType[t] = null,
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _WebDavPortsEditor extends StatelessWidget {
  final TextEditingController httpController;
  final TextEditingController httpsController;
  final String? httpErrorText;
  final String? httpsErrorText;
  final ValueChanged<String>? onHttpChanged;
  final ValueChanged<String>? onHttpsChanged;
  const _WebDavPortsEditor({
    required this.httpController,
    required this.httpsController,
    this.httpErrorText,
    this.httpsErrorText,
    this.onHttpChanged,
    this.onHttpsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final httpHasError =
        httpErrorText != null && httpErrorText!.trim().isNotEmpty;
    final httpsHasError =
        httpsErrorText != null && httpsErrorText!.trim().isNotEmpty;
    return Column(
      children: [
        CustomTextField(
          controller: httpController,
          labelText: 'file_share_server_port_http'.tr,
          keyboardType: TextInputType.number,
          errorText: httpErrorText,
          suffixIcon: httpHasError
              ? Icon(Icons.error_outline, color: theme.colorScheme.error)
              : null,
          onChanged: onHttpChanged,
        ),
        const SizedBox(height: 12),
        CustomTextField(
          controller: httpsController,
          labelText: 'file_share_server_port_https'.tr,
          keyboardType: TextInputType.number,
          errorText: httpsErrorText,
          suffixIcon: httpsHasError
              ? Icon(Icons.error_outline, color: theme.colorScheme.error)
              : null,
          onChanged: onHttpsChanged,
        ),
      ],
    );
  }
}

class _SinglePortEditor extends StatelessWidget {
  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  const _SinglePortEditor({
    required this.controller,
    this.errorText,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasError = errorText != null && errorText!.trim().isNotEmpty;
    return CustomTextField(
      controller: controller,
      labelText: 'file_share_server_port'.tr,
      keyboardType: TextInputType.number,
      errorText: errorText,
      suffixIcon: hasError
          ? Icon(Icons.error_outline, color: theme.colorScheme.error)
          : null,
      onChanged: onChanged,
    );
  }
}
