import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'read_controller.dart';
import 'read_controller_impl.dart';
import 'read_data.dart';

Future<List<PaintData>> addBookBeforeData(ReadControllerImpl controller,
    String title, int chapterIndex, int sentenceIndex, int wordIndex) async {
  List<PaintData> list = List.empty(growable: true);
  while (sentenceIndex > 0 || wordIndex > 0) {
    BookPage page = _getPageContentBefore(
        controller,
        title,
        chapterIndex,
        sentenceIndex,
        wordIndex,
        controller.contentSize.width,
        controller.contentSize.height);
    if (page.lines.isEmpty) {
      break;
    }
    sentenceIndex = page.lines.first.sentence.index;
    wordIndex = page.lines.first.startIndex;
    list.add(PaintData(chapterIndex, title, bookPage: page));
  }
  return list;
}

Future<List<PaintData>> addBookAfterData(ReadControllerImpl controller,
    String title, int chapterIndex, int sentenceIndex, int? wordIndex) async {
  List<PaintData> list = List.empty(growable: true);
  List<BookSentence> sentences = controller.chapterSentences[chapterIndex]!;
  String drawTitle = "";
  if (sentenceIndex == 0 && wordIndex == 0) {
    drawTitle = title;
  }
  if (wordIndex == null) {
    sentenceIndex++;
  }
  BookPage? page;
  while (sentenceIndex < sentences.length && (page?.lines.isNotEmpty ?? true)) {
    page = _getPageContentAfter(
        controller,
        drawTitle,
        chapterIndex,
        sentenceIndex,
        wordIndex ?? 0,
        controller.contentSize.width,
        controller.contentSize.height);
    if (page.lines.isNotEmpty) {
      BookLine line = page.lines.last;
      if (!line.isTitle) {
        sentenceIndex = page.lines.last.sentence.index;
        wordIndex = page.lines.last.endIndex;
        if (wordIndex == null) {
          sentenceIndex++;
        }
      }
      list.add(PaintData(chapterIndex, title, bookPage: page));
      drawTitle = "";
    }
  }
  page = null;
  while (wordIndex != null && (page?.lines.isNotEmpty ?? true)) {
    page = _getPageContentAfter(controller, title, chapterIndex, sentenceIndex,
        wordIndex, controller.contentSize.width, controller.contentSize.height);
    if (page.lines.isNotEmpty) {
      sentenceIndex = page.lines.last.sentence.index;
      wordIndex = page.lines.last.endIndex;
      list.add(PaintData(chapterIndex, title, bookPage: page));
    }
  }
  return list;
}

Future<ui.Picture> drawTextOnCanvas(
    ReadControllerImpl controller, BookPage bookPage) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ReadStyle readStyle = controller.readStyle_;
  final Canvas canvas = Canvas(recorder);

  double x = readStyle.padding.left;
  double y = readStyle.padding.top;
  double wordSpacing = readStyle.wordSpacing;
  double firstLineWordSpacing = wordSpacing;
  for (final line in bookPage.lines) {
    final words = line.sentence.words.sublist(line.startIndex, line.endIndex);
    double wordWidth = 0.0;
    for (final word in words) {
      wordWidth += _wordWidth(word.char,
          line.isTitle ? readStyle.titleTextStyle : readStyle.textStyle);
    }
    double spacing = controller.contentSize.width -
        readStyle.padding.left -
        readStyle.padding.right -
        wordWidth;
    if (line.endIndex != null) {
      if ((line.isTitle && readStyle.titleTextAlign == TextAlign.justify) ||
          (!line.isTitle && readStyle.textAlign == TextAlign.justify)) {
        wordSpacing = words.length <= 1 ? 0 : (spacing / (words.length - 1));
      }
      if (line.startIndex == 0) {
        firstLineWordSpacing = wordSpacing;
      }
    } else {
      if ((line.isTitle && readStyle.titleTextAlign == TextAlign.justify) ||
          (!line.isTitle && readStyle.textAlign == TextAlign.justify)) {
        wordSpacing = firstLineWordSpacing;
      }
    }
    if ((line.isTitle && readStyle.titleTextAlign == TextAlign.center) ||
        (!line.isTitle && readStyle.textAlign == TextAlign.center)) {
      x = (controller.contentSize.width -
              wordWidth -
              wordSpacing * (words.length - 1)) /
          2;
    } else if ((line.isTitle && readStyle.titleTextAlign == TextAlign.end) ||
        (line.isTitle && readStyle.titleTextAlign == TextAlign.right) ||
        (!line.isTitle && readStyle.textAlign == TextAlign.end) ||
        (!line.isTitle && readStyle.textAlign == TextAlign.right)) {
      x = controller.contentSize.width -
          wordWidth -
          wordSpacing * (words.length - 1) -
          readStyle.padding.right;
    }
    for (final word in words) {
      TextPainter tp = _wordPainter(word.char,
          line.isTitle ? readStyle.titleTextStyle : readStyle.textStyle);
      tp.paint(canvas,
          Offset(x, y + (controller.zhWordSize.height - tp.height) / 2));
      // Update X coordinate for the next character
      // 更新X坐标，用于下一个字符
      x += tp.width + wordSpacing;
    }
    x = readStyle.padding.left;
    y += controller.zhWordSize.height + readStyle.lineSpacing;
    if (line.endIndex == null) {
      y += readStyle.sentenceSpacing;
    }
  }

  return recorder.endRecording();
}

/// Get page content after this point
/// 在这之后获取页内容
BookPage _getPageContentAfter(
    ReadControllerImpl controller,
    String title,
    int chapterIndex,
    int sentenceIndex,
    int wordIndex,
    double viewWidth,
    double viewHeight) {
  BookPage page = BookPage();
  List<BookSentence> sentences = controller.chapterSentences[chapterIndex]!;
  if (sentenceIndex >= sentences.length || sentenceIndex < 0) {
    return page;
  }
  double height = controller.readStyle_.padding.top;
  int currentIndex = sentenceIndex;
  int startIndex = wordIndex;
  double wordHeight =
      controller.zhWordSize.height + controller.readStyle_.lineSpacing;
  while (height +
              controller.zhWordSize.height +
              controller.readStyle_.padding.bottom <
          viewHeight &&
      currentIndex < sentences.length) {
    BookSentence sentence = sentences[currentIndex];
    List<BookLine> lines =
        _getLineContentAfter(controller, sentence, startIndex, false);
    if (lines.isNotEmpty) {
      for (BookLine line in lines) {
        page.lines.add(line);
        height += wordHeight;
        if (line.endIndex == null) {
          height += controller.readStyle_.sentenceSpacing;
        }
        if (height +
                controller.zhWordSize.height +
                controller.readStyle_.padding.bottom >=
            viewHeight) {
          return page;
        }
      }
      startIndex = 0;
    }
    currentIndex++;
  }
  return page;
}

/// Get page content before this point
/// 在这之前获取页内容
BookPage _getPageContentBefore(
    ReadControllerImpl controller,
    String title,
    int chapterIndex,
    int sentenceIndex,
    int wordIndex,
    double viewWidth,
    double viewHeight) {
  List<BookSentence> sentences = controller.chapterSentences[chapterIndex]!;
  BookPage page = BookPage();
  int currentIndex = sentenceIndex;
  int startIndex = wordIndex;
  // Move paragraph to the left if the previous page starts at the beginning of a paragraph
  // 说明上页开始是段落开始位置，段落左移
  if (wordIndex == 0) {
    currentIndex--;
  }
  if (currentIndex >= sentences.length || currentIndex < 0) {
    return page;
  }
  double height = controller.readStyle_.padding.top;
  double wordHeight =
      controller.zhWordSize.height + controller.readStyle_.lineSpacing;
  while (height +
              controller.zhWordSize.height +
              controller.readStyle_.padding.bottom <
          viewHeight &&
      currentIndex >= 0) {
    BookSentence sentence = sentences[currentIndex];
    if (sentence.words.isNotEmpty) {
      if (startIndex == 0) {
        startIndex = sentence.words.length;
      }
      List<BookLine> lines =
          _getLineContentBefore(controller, sentence, startIndex, false);
      for (int i = lines.length - 1; i >= 0; i--) {
        BookLine line = lines[i];
        BookLine? lastLine;
        if (i > 0) {
          lastLine = lines[i - 1];
        }
        page.lines.insert(0, line);
        if (line.isRepair || (currentIndex == sentenceIndex && wordIndex > 0)) {
          page.isRepair = true;
        }
        height += wordHeight;
        if (line.endIndex == null) {
          height += controller.readStyle_.sentenceSpacing;
        }
        double lastLineHeight = controller.zhWordSize.height;
        if (lastLine != null && lastLine.endIndex == null) {
          lastLineHeight += controller.readStyle_.sentenceSpacing;
        }
        if (height + lastLineHeight + controller.readStyle_.padding.bottom >=
            viewHeight) {
          return page;
        }
      }
    }
    currentIndex--;
    startIndex = 0;
  }

  BookLine bookLine = page.lines.last;
  if (bookLine.endIndex == null) {
    currentIndex = bookLine.sentence.index + 1;
    startIndex = 0;
  } else {
    currentIndex = bookLine.sentence.index;
    startIndex = bookLine.endIndex!;
  }
  while (height +
              controller.zhWordSize.height +
              controller.readStyle_.padding.bottom <
          viewHeight &&
      currentIndex < sentences.length) {
    BookSentence sentence = sentences[currentIndex];
    List<BookLine> lines =
        _getLineContentAfter(controller, sentence, startIndex, false);
    if (lines.isNotEmpty) {
      for (BookLine line in lines) {
        page.lines.add(line);
        page.isRepair = true;
        height += wordHeight;
        if (line.endIndex == null) {
          height += controller.readStyle_.sentenceSpacing;
        }
        if (height +
                controller.zhWordSize.height +
                controller.readStyle_.padding.bottom >=
            viewHeight) {
          return page;
        }
      }
      startIndex = 0;
    }
    currentIndex++;
  }
  return page;
}

/// Get line content after this point
/// 在这之后获取行内容
List<BookLine> _getLineContentAfter(ReadControllerImpl controller,
    BookSentence sentence, int index, bool isTitle) {
  List<BookLine> lines = List.empty(growable: true);
  int startIndex = max(index, 0);
  int sentenceLength = sentence.words.length;
  if (startIndex >= sentenceLength) {
    return lines;
  }
  List<BookWord> str = sentence.words.sublist(startIndex);
  BookLine? lastLine;
  while (str.isNotEmpty) {
    lastLine?.endIndex = startIndex;
    lastLine = BookLine(sentence, startIndex);
    lines.add(lastLine);
    List<int> strBreak = _breakText(controller, str, isTitle);
    // Not enough for one line
    // 不满一行
    if (strBreak[1] != 1) {
      break;
    }
    int num = strBreak[0].toInt();
    startIndex = startIndex + num;
    str = str.sublist(num);
  }
  return lines;
}

/// Get line content before this point
/// 在这之前获取行内容
List<BookLine> _getLineContentBefore(ReadControllerImpl controller,
    BookSentence sentence, int index, bool isTitle) {
  List<BookLine> lines = List.empty(growable: true);
  int sentenceLength = sentence.words.length;
  if (sentenceLength == 0 || index <= 0) {
    return lines;
  }
  int startIndex = 0;
  int endIndex = min(index, sentenceLength);
  List<BookWord> str = sentence.words.sublist(startIndex, endIndex);
  BookLine? lastLine;
  while (str.isNotEmpty) {
    lastLine?.endIndex = startIndex;
    lastLine = BookLine(sentence, startIndex);
    lines.add(lastLine);
    List<int> strBreak = _breakText(controller, str, isTitle);
    // Not enough for one line
    // 不满一行
    if (strBreak[1] != 1) {
      List<BookWord> fixStr = sentence.words.sublist(startIndex);
      List<int> fixStrBreak = _breakText(controller, fixStr, isTitle);
      if (fixStrBreak[1] != 1) {
        lastLine.endIndex = null;
      } else {
        lastLine.endIndex = startIndex + fixStrBreak[0].toInt();
        lastLine.isRepair = true;
      }
      return lines;
    }
    int num = strBreak[0].toInt();
    startIndex = startIndex + num;
    str = str.sublist(num);
  }
  return lines;
}

List<int> _breakText(
    ReadControllerImpl controller, List<BookWord> text, bool isTitle) {
  if (text.isEmpty) {
    return [0, 0];
  }
  double lineWidth = controller.contentSize.width -
      controller.readStyle_.padding.left -
      controller.readStyle_.padding.right;
  List<int> strBreak = List.filled(2, 0);
  double width = 0;
  for (int i = 0; i < text.length; i++) {
    final word = text[i].char;
    double paintWidth;
    if (_isHalf(word)) {
      paintWidth = _wordWidth(
              word,
              isTitle
                  ? controller.readStyle_.titleTextStyle
                  : controller.readStyle_.textStyle) +
          controller.readStyle_.wordSpacing;
    } else {
      paintWidth = isTitle
          ? controller.zhTitleWordSize.width
          : controller.zhWordSize.width;
    }
    double preWidth = width +
        paintWidth -
        controller.readStyle_.wordSpacing +
        double.minPositive;
    if (preWidth > lineWidth) {
      if (_isHalf(word)) {
        int wordIndex = i - 1;
        while (wordIndex >= 0) {
          final previousWord = text[wordIndex--].char;
          if (previousWord == " " ||
              _isPunctuation(previousWord) ||
              !_isHalf(previousWord)) {
            break;
          }
        }
        int backCount = i - wordIndex - 1;
        if (text[i - backCount].char == " ") {
          backCount--;
        }
        if (i > backCount) {
          strBreak[0] = i - backCount;
        } else {
          strBreak[0] = i;
        }
      } else {
        if (_isPunctuation(word)) {
          strBreak[0] = i - 1;
        } else {
          strBreak[0] = i;
        }
      }
      strBreak[1] = 1;
      return strBreak;
    }
    width += paintWidth;
  }
  strBreak[0] = text.length;
  strBreak[1] = 0;
  return strBreak;
}

// Check if it's a half-width character
// 是否半角字符
bool _isHalf(String character) {
  int code = character.codeUnitAt(0);
  return code >= 0x0020 && code <= 0x007E || code == 0x201C || code == 0x201D;
}

// Check if it's a punctuation mark
// 是否标点符号
bool _isPunctuation(String character) {
  if (character.isEmpty) return false;
  final int code = character.codeUnitAt(0);

  // Basic ASCII punctuation (English punctuation)
  // ASCII 基础标点（英文标点）
  final bool isBasicPunctuation =
      (code >= 0x21 && code <= 0x2F) || // !"#$%&'()*+,-./
          (code >= 0x3A && code <= 0x40) || // :;<=>?@
          (code >= 0x5B && code <= 0x60) || // [\]^_`
          (code >= 0x7B && code <= 0x7E); // {|}~

  // General Unicode punctuation (cross-language)
  // Unicode 通用标点（跨语言）
  final bool isGeneralPunctuation =
      (code >= 0x2000 && code <= 0x206F) || // Includes ‹›«»–—… etc.
          (code >= 0x3000 &&
              code <= 0x303F); // CJK symbols/punctuation (。、！？《》etc.)

  // Full-width punctuation (Chinese typography)
  // 全角标点（中文排版）
  final bool isFullWidthPunctuation =
      (code >= 0xFF01 && code <= 0xFF0F) || // Full-width !, ，．／ etc.
          (code >= 0xFF1A && code <= 0xFF20) || // Full-width :;<=>?@
          (code >= 0xFF3B && code <= 0xFF40) || // Full-width [\]^_`
          (code >= 0xFF5B && code <= 0xFF65); // Full-width {|}~・

  // Special Chinese punctuation (e.g., middle dot)
  // 特殊中文标点（如间隔号·）
  final bool isChineseSpecific = code ==
          0x00B7 || // Latin-1 Supplement: middle dot (·) used in names
      code == 0x2027 || // Hyphenation point (‧)
      code == 0x30FB; // Japanese middle dot (・) but may appear in Chinese texts

  return isBasicPunctuation ||
      isGeneralPunctuation ||
      isFullWidthPunctuation ||
      isChineseSpecific;
}

TextPainter _wordPainter(String word, TextStyle textStyle) {
  final TextSpan span = TextSpan(
    style: textStyle,
    text: word,
  );
  final TextPainter tp = TextPainter(
      text: span, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
  tp.layout();
  return tp;
}

Map<String, double> wordWidthMap = {};

double _wordWidth(String word, TextStyle textStyle) {
  String key =
      "$word@${textStyle.fontSize}@${textStyle.fontWeight}@${textStyle.fontFamily}";
  if (wordWidthMap.containsKey(key)) {
    return wordWidthMap[key]!;
  }
  TextPainter tp = _wordPainter(word, textStyle);
  wordWidthMap[key] = tp.width;
  return tp.width;
}
