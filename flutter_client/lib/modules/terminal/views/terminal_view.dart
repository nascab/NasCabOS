import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:xterm/ui.dart' hide TerminalController;
import 'package:xterm/xterm.dart' show Terminal, TerminalTheme, TerminalStyle;

import '../../../core/api/api_controller.dart';
import '../controllers/terminal_controller.dart';
import '../../home/views/pc_components/pc_app_window.dart';
import '../../../utils/device_utils.dart';

class TerminalPage extends StatelessWidget {
  const TerminalPage({super.key});

  Future<void> _openSettings(
    BuildContext context,
    TerminalController controller,
  ) async {
    final snapshot = controller.uiConfig.value;
    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TerminalSettingsSheet(controller: controller),
    );
    if (res == true) return;
    controller.setUiConfig(snapshot);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final instanceId = PcWindowScope.of(context)?.windowId ?? 'terminal';
    final isPcWindow = PcWindowScope.of(context) != null;
    final isMobile = DeviceUtils.isMobile;
    final showMobileChrome = isMobile && !isPcWindow;
    final chromeColor = theme.colorScheme.surface;
    final chromeBrightness = ThemeData.estimateBrightnessForColor(chromeColor);
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: chromeBrightness,
      statusBarIconBrightness: chromeBrightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarColor: chromeColor,
      systemNavigationBarIconBrightness: chromeBrightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
    );

    final scaffold = Scaffold(
      backgroundColor: chromeColor,
      appBar: showMobileChrome
          ? AppBar(
              leading: const BackButton(),
              title: Text('terminal_title'.tr),
            )
          : null,
      body: SafeArea(
        top: false,
        bottom: showMobileChrome,
        child: Padding(
          padding: EdgeInsets.only(
            top: isPcWindow
                ? 35
                : showMobileChrome
                ? 0
                : 15,
          ),
          child: GetBuilder<TerminalController>(
            init: TerminalController(instanceId: instanceId),
            builder: (controller) {
              return Column(
                children: [
                  Obx(() {
                    final text = controller.statusText.value.trim();
                    if (text.isEmpty) return const SizedBox.shrink();
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Text(
                        text,
                        style: TextStyle(color: theme.colorScheme.onSurface),
                      ),
                    );
                  }),
                  Expanded(
                    child: Obx(() {
                      return _TerminalViewWrapper(
                        terminal: controller.terminal,
                        theme: controller.terminalTheme,
                        textStyle: controller.terminalTextStyle,
                        cursorStyle: controller.uiConfig.value.cursorStyle,
                      );
                    }),
                  ),
                  _TerminalBottomBar(
                    controller: controller,
                    isWin32:
                        (ApiController.instance.serverPlatform ?? '')
                            .toLowerCase() ==
                        'win32',
                    onInterrupt: controller.interruptRunningCommand,
                    onReconnect: controller.reconnectNow,
                    onSettings: () => _openSettings(context, controller),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    if (!showMobileChrome) return scaffold;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: scaffold,
    );
  }
}

TerminalCursorType _cursorTypeFromStyle(String raw) {
  final v = raw.trim().toLowerCase();
  if (v == 'underline') return TerminalCursorType.underline;
  if (v == 'bar' || v == 'line' || v == 'verticalbar') {
    return TerminalCursorType.verticalBar;
  }
  return TerminalCursorType.block;
}

/// Windows 下若立即 autofocus 会触发 "view ID is null" 的 PlatformException，
/// 延迟一帧再挂载带 autofocus 的 TerminalView 可避免该问题。
class _TerminalViewWrapper extends StatefulWidget {
  final Terminal terminal;
  final TerminalTheme theme;
  final TerminalStyle textStyle;
  final String cursorStyle;

  const _TerminalViewWrapper({
    required this.terminal,
    required this.theme,
    required this.textStyle,
    required this.cursorStyle,
  });

  @override
  State<_TerminalViewWrapper> createState() => _TerminalViewWrapperState();
}

class _TerminalViewWrapperState extends State<_TerminalViewWrapper> {
  bool _deferredReady = false;

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform == TargetPlatform.windows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _deferredReady = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;
    final useAutofocus = !isWindows || _deferredReady;
    final hardwareKeyboardOnly = isWindows;
    if (isWindows && !_deferredReady) {
      return const SizedBox.expand();
    }
    return TerminalView(
      widget.terminal,
      autofocus: useAutofocus,
      backgroundOpacity: 1.0,
      theme: widget.theme,
      textStyle: widget.textStyle,
      cursorType: _cursorTypeFromStyle(widget.cursorStyle),
      // Windows 下 xterm 的 TextInput 通道容易在失焦/重建时触发
      // "Set editing state... but no client is set"，终端场景改走物理键盘更稳定。
      hardwareKeyboardOnly: hardwareKeyboardOnly,
    );
  }
}

class _TerminalBottomBar extends StatelessWidget {
  final TerminalController controller;
  final bool isWin32;
  final VoidCallback onInterrupt;
  final VoidCallback onReconnect;
  final VoidCallback onSettings;

  const _TerminalBottomBar({
    required this.controller,
    required this.isWin32,
    required this.onInterrupt,
    required this.onReconnect,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 35,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
        color: theme.colorScheme.surface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Row(
            children: [
              if (isWin32)
                Obx(() {
                  final current = controller.currentShell.value;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _shellChip(
                        context,
                        label: 'PowerShell',
                        isSelected: current == 'powershell',
                        onTap: () => controller.switchShell('powershell'),
                      ),
                      const SizedBox(width: 6),
                      _shellChip(
                        context,
                        label: 'CMD',
                        isSelected: current == 'cmd',
                        onTap: () => controller.switchShell('cmd'),
                      ),
                    ],
                  );
                }),
              const Spacer(),
              Wrap(
                spacing: 4,
                runSpacing: 0,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Obx(() {
                    final canInterrupt = controller.connected.value;
                    return _barButton(
                      context,
                      icon: Icons.cancel_outlined,
                      tooltip: 'Ctrl+C',
                      onTap: onInterrupt,
                      enabled: canInterrupt,
                    );
                  }),
                  _barButton(
                    context,
                    icon: Icons.refresh,
                    tooltip: 'terminal_reconnect'.tr,
                    onTap: onReconnect,
                  ),
                  _barButton(
                    context,
                    icon: Icons.settings_outlined,
                    tooltip: 'terminal_settings'.tr,
                    onTap: onSettings,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _shellChip(
    BuildContext context, {
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: isSelected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: isSelected ? Colors.white : theme.colorScheme.onSurface,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _barButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 36,
          height: 30,
          child: Icon(
            icon,
            size: 18,
            color: enabled
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurface.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}

class _TerminalSettingsSheet extends StatefulWidget {
  final TerminalController controller;
  const _TerminalSettingsSheet({required this.controller});

  @override
  State<_TerminalSettingsSheet> createState() => _TerminalSettingsSheetState();
}

class _TerminalSettingsSheetState extends State<_TerminalSettingsSheet> {
  late TerminalUiConfig _cfg;

  late final TextEditingController _foregroundController;
  late final TextEditingController _backgroundController;
  late final TextEditingController _cursorController;

  @override
  void initState() {
    super.initState();
    _cfg = widget.controller.uiConfig.value;
    _foregroundController = TextEditingController(text: _cfg.foreground);
    _backgroundController = TextEditingController(text: _cfg.background);
    _cursorController = TextEditingController(text: _cfg.cursor);
  }

  @override
  void dispose() {
    _foregroundController.dispose();
    _backgroundController.dispose();
    _cursorController.dispose();
    super.dispose();
  }

  void _apply(TerminalUiConfig next) {
    setState(() => _cfg = next);
    widget.controller.setUiConfig(next);
  }

  void _resetDefaults() {
    final next = TerminalUiConfig.defaults();
    _foregroundController.text = next.foreground;
    _backgroundController.text = next.background;
    _cursorController.text = next.cursor;
    _apply(next);
  }

  String _colorToHex(Color c) {
    final a = c.alpha.toRadixString(16).padLeft(2, '0');
    final r = c.red.toRadixString(16).padLeft(2, '0');
    final g = c.green.toRadixString(16).padLeft(2, '0');
    final b = c.blue.toRadixString(16).padLeft(2, '0');
    if (c.alpha == 0xff) return '#$r$g$b'.toUpperCase();
    return '#$a$r$g$b'.toUpperCase();
  }

  List<Color> _presetColors(ThemeData theme) {
    return <Color>[
      theme.colorScheme.primary,
      theme.colorScheme.secondary,
      theme.colorScheme.tertiary,
      Colors.white,
      Colors.black,
      const Color(0xffe6e6e6),
      const Color(0xff0b0b0b),
      Colors.grey,
      Colors.blueGrey,
      Colors.red,
      Colors.orange,
      Colors.amber,
      Colors.yellow,
      Colors.lime,
      Colors.green,
      Colors.teal,
      Colors.cyan,
      Colors.lightBlue,
      Colors.blue,
      Colors.indigo,
      Colors.purple,
      Colors.pink,
      Colors.brown,
    ];
  }

  Future<void> _pickColor({
    required TextEditingController controller,
    required Color fallback,
    required ValueChanged<String> onChanged,
  }) async {
    final theme = Theme.of(context);
    final initialColor = TerminalUiConfig.parseColor(
      controller.text,
      fallback: fallback,
    );
    final picked = await showDialog<Color>(
      context: context,
      builder: (dialogContext) {
        final input = TextEditingController(text: controller.text);
        Color preview = TerminalUiConfig.parseColor(
          input.text,
          fallback: initialColor,
        );

        return StatefulBuilder(
          builder: (context, setState) {
            void updatePreview() {
              setState(() {
                preview = TerminalUiConfig.parseColor(
                  input.text,
                  fallback: initialColor,
                );
              });
            }

            final colors = _presetColors(theme);

            return AlertDialog(
              title: Text('terminal_pick_color'.tr),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: preview,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: theme.dividerColor),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: input,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              isDense: true,
                              hintText: 'terminal_color_hint'.tr,
                            ),
                            onChanged: (_) => updatePreview(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in colors)
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => Navigator.of(dialogContext).pop(c),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: c,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: theme.dividerColor),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text('cancel'.tr),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(preview),
                  child: Text('ok'.tr),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked == null) return;
    final hex = _colorToHex(picked);
    controller.text = hex;
    onChanged(hex);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Material(
          color: theme.colorScheme.surface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'terminal_settings_title'.tr,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: _resetDefaults,
                      child: Text('terminal_restore_defaults'.tr),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text('cancel'.tr),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () async {
                        widget.controller.setUiConfig(_cfg);
                        await widget.controller.saveUiConfig();
                        if (context.mounted) {
                          Navigator.of(context).pop(true);
                        }
                      },
                      child: Text('save'.tr),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _colorRow(
                        context,
                        label: 'terminal_font_color'.tr,
                        controller: _foregroundController,
                        fallback: const Color(0xffe6e6e6),
                        onPick: () => _pickColor(
                          controller: _foregroundController,
                          fallback: const Color(0xffe6e6e6),
                          onChanged: (v) =>
                              _apply(_cfg.copyWith(foreground: v)),
                        ),
                        onChanged: (v) => _apply(_cfg.copyWith(foreground: v)),
                      ),
                      const SizedBox(height: 12),
                      _colorRow(
                        context,
                        label: 'terminal_bg_color'.tr,
                        controller: _backgroundController,
                        fallback: const Color(0xff0b0b0b),
                        onPick: () => _pickColor(
                          controller: _backgroundController,
                          fallback: const Color(0xff0b0b0b),
                          onChanged: (v) =>
                              _apply(_cfg.copyWith(background: v)),
                        ),
                        onChanged: (v) => _apply(_cfg.copyWith(background: v)),
                      ),
                      const SizedBox(height: 12),
                      _colorRow(
                        context,
                        label: 'terminal_cursor_color'.tr,
                        controller: _cursorController,
                        fallback: const Color(0xffe6e6e6),
                        onPick: () => _pickColor(
                          controller: _cursorController,
                          fallback: const Color(0xffe6e6e6),
                          onChanged: (v) => _apply(_cfg.copyWith(cursor: v)),
                        ),
                        onChanged: (v) => _apply(_cfg.copyWith(cursor: v)),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'terminal_font_size'.trParams({
                                'px': '${_cfg.fontSize}',
                              }),
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _cfg.fontSize.toDouble(),
                        min: 8,
                        max: 24,
                        divisions: 16,
                        label: '${_cfg.fontSize}px',
                        onChanged: (v) =>
                            _apply(_cfg.copyWith(fontSize: v.round())),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'terminal_line_height'.trParams({
                                'value': _cfg.lineHeight.toStringAsFixed(2),
                              }),
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _cfg.lineHeight.clamp(0.8, 2.0),
                        min: 0.8,
                        max: 2.0,
                        divisions: 24,
                        label: _cfg.lineHeight.toStringAsFixed(2),
                        onChanged: (v) => _apply(_cfg.copyWith(lineHeight: v)),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'terminal_cursor_style'.tr,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _cfg.cursorStyle,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'block',
                            child: Text('terminal_cursor_block'.tr),
                          ),
                          DropdownMenuItem(
                            value: 'underline',
                            child: Text('terminal_cursor_underline'.tr),
                          ),
                          DropdownMenuItem(
                            value: 'bar',
                            child: Text('terminal_cursor_bar'.tr),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          _apply(_cfg.copyWith(cursorStyle: v));
                        },
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        activeColor: theme.colorScheme.primary,
                        contentPadding: EdgeInsets.zero,
                        title: Text('terminal_cursor_blink'.tr),
                        value: _cfg.cursorBlink,
                        onChanged: (v) => _apply(_cfg.copyWith(cursorBlink: v)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _colorRow(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    required Color fallback,
    required VoidCallback onPick,
    required ValueChanged<String> onChanged,
  }) {
    final theme = Theme.of(context);
    final preview = TerminalUiConfig.parseColor(
      controller.text,
      fallback: fallback,
    );
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: theme.textTheme.titleSmall),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              isDense: true,
              hintText: 'terminal_color_hint'.tr,
            ),
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'terminal_click_to_pick_color'.tr,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onPick,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: preview,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.dividerColor),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
