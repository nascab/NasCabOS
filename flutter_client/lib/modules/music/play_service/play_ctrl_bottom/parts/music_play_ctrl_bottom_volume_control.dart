import 'package:flutter/material.dart';

class MusicPlayCtrlBottomVolumeControl extends StatefulWidget {
  final double volume;
  final ValueChanged<double> onChanged;
  final VoidCallback onToggleMute;
  final bool showInlineSlider;

  final bool showLoopButton;
  final IconData? loopIcon;
  final String? loopTooltip;
  final VoidCallback? onToggleLoopMode;

  final bool showPlayListButton;
  final IconData? playListIcon;
  final String? playListTooltip;
  final VoidCallback? onAddToPlayList;

  final bool showNowPlayingButton;
  final IconData? nowPlayingIcon;
  final String? nowPlayingTooltip;
  final VoidCallback? onShowNowPlaying;

  final String? volumeTooltip;

  const MusicPlayCtrlBottomVolumeControl({
    super.key,
    required this.volume,
    required this.onChanged,
    required this.onToggleMute,
    this.showInlineSlider = true,
    this.showLoopButton = false,
    this.loopIcon,
    this.loopTooltip,
    this.onToggleLoopMode,
    this.showPlayListButton = false,
    this.playListIcon,
    this.playListTooltip,
    this.onAddToPlayList,
    this.showNowPlayingButton = false,
    this.nowPlayingIcon,
    this.nowPlayingTooltip,
    this.onShowNowPlaying,
    this.volumeTooltip,
  });

  @override
  State<MusicPlayCtrlBottomVolumeControl> createState() =>
      _MusicPlayCtrlBottomVolumeControlState();
}

class _MusicPlayCtrlBottomVolumeControlState
    extends State<MusicPlayCtrlBottomVolumeControl> {
  final GlobalKey _anchorKey = GlobalKey();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _volumeEntry;
  Offset _volumeOverlayOffset = Offset.zero;

  @override
  void dispose() {
    _hideVolumeOverlay();
    super.dispose();
  }

  void _hideVolumeOverlay() {
    _volumeEntry?.remove();
    _volumeEntry = null;
  }

  void _showVolumeOverlay(BuildContext context, double value) {
    if (_volumeEntry != null) {
      _hideVolumeOverlay();
      return;
    }

    final anchorCtx = _anchorKey.currentContext;
    final overlayState = Overlay.of(context, rootOverlay: true);
    final overlayBox = overlayState.context.findRenderObject() as RenderBox?;
    final anchorBox = anchorCtx?.findRenderObject() as RenderBox?;
    if (overlayBox == null || anchorBox == null) return;

    final targetTopLeft = anchorBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );

    const popupWidth = 58.0;
    const popupHeight = 216.0;
    const margin = 8.0;

    var desiredTopLeft = Offset(
      targetTopLeft.dx + (anchorBox.size.width / 2) - (popupWidth / 2),
      targetTopLeft.dy - popupHeight - 10,
    );

    desiredTopLeft = Offset(
      desiredTopLeft.dx.clamp(
        margin,
        overlayBox.size.width - popupWidth - margin,
      ),
      desiredTopLeft.dy.clamp(
        margin,
        overlayBox.size.height - popupHeight - margin,
      ),
    );

    _volumeOverlayOffset = desiredTopLeft - targetTopLeft;

    final theme = Theme.of(context);
    _volumeEntry = OverlayEntry(
      builder: (ctx) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _hideVolumeOverlay,
                behavior: HitTestBehavior.translucent,
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: _volumeOverlayOffset,
              child: Material(
                color: theme.colorScheme.surface,
                elevation: 10,
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints.tightFor(
                    width: popupWidth,
                    height: popupHeight,
                  ),
                  child: _VolumePopup(
                    initialValue: value,
                    onChanged: (v) => widget.onChanged(v.clamp(0.0, 1.0)),
                    onToggleMute: widget.onToggleMute,
                    theme: theme,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlayState.insert(_volumeEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = widget.volume.clamp(0.0, 1.0);
    final iconColor = theme.iconTheme.color?.withValues(alpha: 0.7);

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showLoopButton)
            _TinyIconButton(
              tooltip: widget.loopTooltip,
              icon: widget.loopIcon ?? Icons.repeat,
              enabled: widget.onToggleLoopMode != null,
              onTap: widget.onToggleLoopMode,
              iconColor: iconColor,
            ),
          if (widget.showPlayListButton)
            _TinyIconButton(
              tooltip: widget.playListTooltip,
              icon: widget.playListIcon ?? Icons.playlist_add,
              enabled: widget.onAddToPlayList != null,
              onTap: widget.onAddToPlayList,
              iconColor: iconColor,
            ),
          if (widget.showNowPlayingButton)
            _TinyIconButton(
              tooltip: widget.nowPlayingTooltip,
              icon: widget.nowPlayingIcon ?? Icons.queue_music_outlined,
              enabled: widget.onShowNowPlaying != null,
              onTap: widget.onShowNowPlaying,
              iconColor: iconColor,
            ),
          CompositedTransformTarget(
            link: _layerLink,
            child: Container(
              key: _anchorKey,
              child: _TinyIconButton(
                tooltip: widget.volumeTooltip,
                icon: v <= 0.01 ? Icons.volume_off : Icons.volume_up,
                onTap: widget.showInlineSlider
                    ? widget.onToggleMute
                    : () => _showVolumeOverlay(context, v),
                onLongPress:
                    widget.showInlineSlider ? null : widget.onToggleMute,
                iconColor: iconColor,
              ),
            ),
          ),
          if (widget.showInlineSlider) ...[
            const SizedBox(width: 6),
            SizedBox(
              width: 80,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 10),
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  activeTrackColor: theme.colorScheme.primary,
                  inactiveTrackColor:
                      theme.dividerColor.withValues(alpha: 0.5),
                  thumbColor: theme.colorScheme.primary,
                ),
                child: Slider(
                  value: v,
                  min: 0,
                  max: 1,
                  onChanged: widget.onChanged,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TinyIconButton extends StatelessWidget {
  final String? tooltip;
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;
  final Color? iconColor;

  const _TinyIconButton({
    required this.icon,
    required this.onTap,
    this.onLongPress,
    this.tooltip,
    this.enabled = true,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = GestureDetector(
      onTap: enabled ? onTap : null,
      onLongPress: enabled ? onLongPress : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 18,
          color: enabled
              ? iconColor
              : theme.disabledColor.withValues(alpha: 0.65),
        ),
      ),
    );

    final t = tooltip?.trim() ?? '';
    if (t.isEmpty) return child;
    return Tooltip(message: t, child: child);
  }
}

class _VolumePopup extends StatefulWidget {
  final double initialValue;
  final ValueChanged<double> onChanged;
  final VoidCallback onToggleMute;
  final ThemeData theme;

  const _VolumePopup({
    required this.initialValue,
    required this.onChanged,
    required this.onToggleMute,
    required this.theme,
  });

  @override
  State<_VolumePopup> createState() => _VolumePopupState();
}

class _VolumePopupState extends State<_VolumePopup> {
  late double _v;

  @override
  void initState() {
    super.initState();
    _v = widget.initialValue.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final label = '${(_v * 100).round()}%';
    return Material(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 148,
              width: 38,
              child: RotatedBox(
                quarterTurns: -1,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 10,
                    ),
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    activeTrackColor: theme.colorScheme.primary,
                    inactiveTrackColor: theme.dividerColor.withValues(
                      alpha: 0.5,
                    ),
                    thumbColor: theme.colorScheme.primary,
                  ),
                  child: SizedBox(
                    width: 148,
                    child: Slider(
                      value: _v,
                      min: 0,
                      max: 1,
                      onChanged: (v) {
                        setState(() {
                          _v = v.clamp(0.0, 1.0);
                        });
                        widget.onChanged(_v);
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 2),
            GestureDetector(
              onTap: widget.onToggleMute,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  _v <= 0.01 ? Icons.volume_off : Icons.volume_up,
                  size: 18,
                  color: theme.iconTheme.color?.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
