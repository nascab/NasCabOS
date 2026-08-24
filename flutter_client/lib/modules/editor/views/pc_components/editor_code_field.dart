import 'dart:async';
import 'dart:math';

import 'package:code_text_field/code_text_field.dart';
import 'package:flutter/material.dart';
import 'package:linked_scroll_controller/linked_scroll_controller.dart';

class EditorCodeField extends StatefulWidget {
  const EditorCodeField({
    super.key,
    required this.controller,
    this.minLines,
    this.maxLines,
    this.expands = false,
    this.wrap = false,
    this.cursorColor,
    this.textStyle,
    this.enabled,
    this.readOnly = false,
    this.isDense = false,
    this.textSelectionTheme,
    this.onChanged,
    this.focusNode,
    this.onTap,
    this.lineNumbers = true,
    this.horizontalScroll = true,
    this.padding = EdgeInsets.zero,
    this.textAlignVertical = TextAlignVertical.top,
    this.selectionControls,
    this.keyboardType,
    this.smartQuotesType,
    this.lineNumberStyle = const LineNumberStyle(),
    this.lineNumberBuilder,
    this.background,
    this.decoration,
  });

  final CodeController controller;
  final int? minLines;
  final int? maxLines;
  final bool expands;
  final bool wrap;
  final Color? cursorColor;
  final TextStyle? textStyle;
  final bool? enabled;
  final bool readOnly;
  final bool isDense;
  final TextSelectionThemeData? textSelectionTheme;
  final void Function(String)? onChanged;
  final FocusNode? focusNode;
  final void Function()? onTap;
  final bool lineNumbers;
  final bool horizontalScroll;
  final EdgeInsets padding;
  final TextAlignVertical textAlignVertical;
  final TextSelectionControls? selectionControls;
  final TextInputType? keyboardType;
  final SmartQuotesType? smartQuotesType;
  final LineNumberStyle lineNumberStyle;
  final TextSpan Function(int, TextStyle?)? lineNumberBuilder;
  final Color? background;
  final Decoration? decoration;

  @override
  State<EditorCodeField> createState() => _EditorCodeFieldState();
}

class _EditorCodeFieldState extends State<EditorCodeField> {
  LinkedScrollControllerGroup? _controllers;
  ScrollController? _numberScroll;
  ScrollController? _codeScroll;
  LineNumberController? _numberController;
  FocusNode? _focusNode;
  StreamSubscription<bool>? _keyboardVisibilitySubscription;

  String longestLine = '';

  @override
  void initState() {
    super.initState();
    _controllers = LinkedScrollControllerGroup();
    _numberScroll = _controllers?.addAndGet();
    _codeScroll = _controllers?.addAndGet();
    _numberController = LineNumberController(widget.lineNumberBuilder);
    widget.controller.addListener(_onTextChanged);
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode!.onKey = _onKey;
    _focusNode!.attach(context, onKey: _onKey);
    _onTextChanged();
  }

  KeyEventResult _onKey(FocusNode node, RawKeyEvent event) {
    if (widget.readOnly) return KeyEventResult.ignored;
    return widget.controller.onKey(event);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _numberScroll?.dispose();
    _codeScroll?.dispose();
    _numberController?.dispose();
    _keyboardVisibilitySubscription?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    final str = widget.controller.text.split('\n');
    final buf = <String>[];
    for (var k = 0; k < str.length; k++) {
      buf.add((k + 1).toString());
    }
    _numberController?.text = buf.join('\n');

    longestLine = '';
    for (final line in widget.controller.text.split('\n')) {
      if (line.length > longestLine.length) longestLine = line;
    }
    setState(() {});
  }

  Widget _wrapInScrollView(
    Widget codeField,
    TextStyle textStyle,
    double minWidth,
  ) {
    final leftPad = widget.lineNumberStyle.margin / 2;
    final intrinsic = IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: 0,
              minWidth: max(minWidth - leftPad, 0),
            ),
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(longestLine, style: textStyle),
            ),
          ),
          widget.expands ? Expanded(child: codeField) : codeField,
        ],
      ),
    );

    return SingleChildScrollView(
      padding: EdgeInsets.only(left: leftPad),
      scrollDirection: Axis.horizontal,
      physics: widget.horizontalScroll
          ? null
          : const NeverScrollableScrollPhysics(),
      child: intrinsic,
    );
  }

  @override
  Widget build(BuildContext context) {
    const rootKey = 'root';
    final defaultBg = Colors.grey.shade900;
    final defaultText = Colors.grey.shade200;

    final styles = CodeTheme.of(context)?.styles;
    Color? backgroundCol =
        widget.background ?? styles?[rootKey]?.backgroundColor ?? defaultBg;

    if (widget.decoration != null) {
      backgroundCol = null;
    }

    TextStyle textStyle = widget.textStyle ?? const TextStyle();
    textStyle = textStyle.copyWith(
      color: textStyle.color ?? styles?[rootKey]?.color ?? defaultText,
      fontSize: textStyle.fontSize ?? 16.0,
    );

    TextStyle numberTextStyle =
        widget.lineNumberStyle.textStyle ?? const TextStyle();
    final numberColor = (styles?[rootKey]?.color ?? defaultText).withOpacity(
      0.7,
    );
    numberTextStyle = numberTextStyle.copyWith(
      color: numberTextStyle.color ?? numberColor,
      fontSize: textStyle.fontSize,
      fontFamily: textStyle.fontFamily,
      height: textStyle.height,
    );

    final cursorColor =
        widget.cursorColor ?? styles?[rootKey]?.color ?? defaultText;

    TextField? lineNumberCol;
    Container? numberCol;

    if (widget.lineNumbers) {
      lineNumberCol = TextField(
        keyboardType: widget.keyboardType,
        smartQuotesType: widget.smartQuotesType,
        scrollPadding: widget.padding,
        style: numberTextStyle,
        controller: _numberController,
        enabled: false,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        expands: widget.expands,
        scrollController: _numberScroll,
        selectionControls: widget.selectionControls,
        textAlign: widget.lineNumberStyle.textAlign,
        textAlignVertical: widget.textAlignVertical,
        decoration: InputDecoration(
          isCollapsed: true,
          disabledBorder: InputBorder.none,
          isDense: widget.isDense,
          contentPadding: EdgeInsets.only(
            top: widget.padding.top,
            bottom: widget.padding.bottom,
          ),
        ),
      );

      numberCol = Container(
        width: widget.lineNumberStyle.width,
        color: widget.lineNumberStyle.background,
        child: lineNumberCol,
      );
    }

    final codeField = TextField(
      keyboardType: widget.keyboardType,
      smartQuotesType: widget.smartQuotesType,
      focusNode: _focusNode,
      onTap: widget.onTap,
      scrollPadding: widget.padding,
      style: textStyle,
      controller: widget.controller,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      expands: widget.expands,
      scrollController: _codeScroll,
      cursorColor: cursorColor,
      autocorrect: false,
      enableSuggestions: false,
      enabled: widget.enabled,
      onChanged: widget.onChanged,
      readOnly: widget.readOnly,
      selectionControls: widget.selectionControls,
      textAlignVertical: widget.textAlignVertical,
      decoration: InputDecoration(
        isCollapsed: true,
        contentPadding: widget.padding,
        disabledBorder: InputBorder.none,
        border: InputBorder.none,
        focusedBorder: InputBorder.none,
        isDense: widget.isDense,
      ),
    );

    final codeCol = Theme(
      data: Theme.of(
        context,
      ).copyWith(textSelectionTheme: widget.textSelectionTheme),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return widget.wrap
              ? codeField
              : _wrapInScrollView(codeField, textStyle, constraints.maxWidth);
        },
      ),
    );

    return Container(
      decoration: widget.decoration,
      color: backgroundCol,
      padding: !widget.lineNumbers ? const EdgeInsets.only(left: 8) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.lineNumbers && numberCol != null) numberCol,
          Expanded(child: codeCol),
        ],
      ),
    );
  }
}
