import 'package:flutter/material.dart';

class CustomLetterFilter extends StatefulWidget {
  final List<String> letters;
  final String? value;
  final String? initialValue;
  final ValueChanged<String?>? onChanged;
  final double width;
  final double itemHeight;
  final double borderRadius;
  final bool centerWhenBoundedHeight;

  const CustomLetterFilter({
    super.key,
    this.letters = const [
      '#',
      'A',
      'B',
      'C',
      'D',
      'E',
      'F',
      'G',
      'H',
      'I',
      'J',
      'K',
      'L',
      'M',
      'N',
      'O',
      'P',
      'Q',
      'R',
      'S',
      'T',
      'U',
      'V',
      'W',
      'X',
      'Y',
      'Z',
    ],
    this.value,
    this.initialValue,
    this.onChanged,
    this.width = 25,
    this.itemHeight = 18,
    this.borderRadius = 10,
    this.centerWhenBoundedHeight = false,
  });

  @override
  State<CustomLetterFilter> createState() => _CustomLetterFilterState();
}

class _CustomLetterFilterState extends State<CustomLetterFilter> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = _normalize(widget.value ?? widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant CustomLetterFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) return;
    _selected = _normalize(widget.value);
  }

  List<String> get _displayLetters {
    final out = <String>[];
    final seen = <String>{};
    for (final raw in widget.letters) {
      final v = _normalize(raw);
      if (v == null || v.isEmpty) continue;
      if (seen.contains(v)) continue;
      seen.add(v);
      out.add(v);
    }
    return out;
  }

  String? _normalize(String? s) {
    final v = (s ?? '').trim();
    if (v.isEmpty) return null;
    if (v == '#') return '#';
    if (v.length == 1 && RegExp(r'^[a-zA-Z]$').hasMatch(v)) {
      return v.toUpperCase();
    }
    return v.toUpperCase();
  }

  void _toggle(String letter) {
    final normalized = _normalize(letter);
    if (normalized == null) return;
    final current = _selected;
    final next = current == normalized ? null : normalized;
    setState(() => _selected = next);
    widget.onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final letters = _displayLetters;
    final selected = _selected;

    return SizedBox(
      width: widget.width,
      // decoration: BoxDecoration(
      //   color: theme.colorScheme.surface.withValues(alpha: 0.7),
      //   border: Border.all(color: theme.dividerColor),
      //   borderRadius: BorderRadius.circular(widget.borderRadius),
      // ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 6),
              for (final letter in letters)
                _LetterCell(
                  letter: letter,
                  height: widget.itemHeight,
                  selected: selected == letter,
                  onTap: () => _toggle(letter),
                ),
              const SizedBox(height: 6),
            ],
          );

          if (!constraints.hasBoundedHeight) return content;

          return ClipRect(
            child: ScrollConfiguration(
              behavior:
                  ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight),
                  child: widget.centerWhenBoundedHeight
                      ? Align(alignment: Alignment.center, child: content)
                      : content,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LetterCell extends StatefulWidget {
  final String letter;
  final double height;
  final bool selected;
  final VoidCallback onTap;

  const _LetterCell({
    required this.letter,
    required this.height,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_LetterCell> createState() => _LetterCellState();
}

class _LetterCellState extends State<_LetterCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = widget.selected
        ? theme.colorScheme.primary
        : (_hovered
              ? theme.colorScheme.onSurface.withValues(alpha: 0.06)
              : Colors.transparent);
    final fg = theme.colorScheme.onSurface.withValues(
      alpha: _hovered ? 0.9 : 0.75,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SizedBox(
        height: widget.height,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: widget.onTap,
            child: Center(
              child: Text(
                widget.letter,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
