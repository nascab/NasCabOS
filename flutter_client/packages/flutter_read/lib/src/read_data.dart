import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fast_gbk/fast_gbk.dart';

enum _ReadTextEncoding {
  utf8,
  utf16le,
  utf16be,
  gbk,
}

_ReadTextEncoding? _parseEncoding(String? raw) {
  final v = (raw ?? '').trim().toLowerCase();
  switch (v) {
    case '':
    case 'auto':
      return null;
    case 'utf8':
    case 'utf-8':
      return _ReadTextEncoding.utf8;
    case 'utf16le':
    case 'utf-16le':
      return _ReadTextEncoding.utf16le;
    case 'utf16be':
    case 'utf-16be':
      return _ReadTextEncoding.utf16be;
    case 'gbk':
    case 'cp936':
    case 'ansi':
      return _ReadTextEncoding.gbk;
    default:
      return null;
  }
}

class _AutoEncodingDecoder extends StreamTransformerBase<List<int>, String> {
  final int _probeBytes;
  final _ReadTextEncoding? _forced;

  _AutoEncodingDecoder({
    int probeBytes = 4096,
    _ReadTextEncoding? forced,
  })  : _probeBytes = probeBytes,
        _forced = forced;

  @override
  Stream<String> bind(Stream<List<int>> stream) {
    late final StreamController<String> out;
    StreamSubscription<List<int>>? sub;

    final buffer = BytesBuilder(copy: false);
    _ReadTextEncoding? encoding = _forced;
    int skip = 0;

    Sink<List<int>>? chunked;
    StringConversionSink? stringSink;

    int? utf16Carry;
    final utf16Units = <int>[];

    bool isLikelyUtf8(Uint8List sample) {
      if (sample.isEmpty) return true;
      final len = sample.length;
      final maxTrim = len >= 4 ? 3 : len - 1;
      for (int trim = 0; trim <= maxTrim; trim++) {
        final end = len - trim;
        if (end <= 0) continue;
        try {
          utf8.decode(sample.sublist(0, end), allowMalformed: false);
          return true;
        } catch (_) {}
      }
      return false;
    }

    void decide(Uint8List sample) {
      if (encoding != null) return;
      if (sample.length >= 3 &&
          sample[0] == 0xEF &&
          sample[1] == 0xBB &&
          sample[2] == 0xBF) {
        encoding = _ReadTextEncoding.utf8;
        skip = 3;
        return;
      }
      if (sample.length >= 2 && sample[0] == 0xFF && sample[1] == 0xFE) {
        encoding = _ReadTextEncoding.utf16le;
        skip = 2;
        return;
      }
      if (sample.length >= 2 && sample[0] == 0xFE && sample[1] == 0xFF) {
        encoding = _ReadTextEncoding.utf16be;
        skip = 2;
        return;
      }
      if (isLikelyUtf8(sample)) {
        encoding = _ReadTextEncoding.utf8;
        skip = 0;
        return;
      }
      encoding = _ReadTextEncoding.gbk;
      skip = 0;
    }

    void initDecoderIfNeeded() {
      if (stringSink != null) return;
      if (encoding == null) return;
      stringSink = StringConversionSink.withCallback(out.add);
      if (encoding == _ReadTextEncoding.utf8) {
        chunked = const Utf8Decoder(allowMalformed: true)
            .startChunkedConversion(stringSink!);
        return;
      }
      if (encoding == _ReadTextEncoding.gbk) {
        chunked =
            const GbkCodec(allowMalformed: true).decoder.startChunkedConversion(
                  stringSink!,
                );
        return;
      }
    }

    void decodeChunk(List<int> bytes) {
      if (bytes.isEmpty) return;
      initDecoderIfNeeded();

      final enc = encoding;
      if (enc == null) return;
      if (enc == _ReadTextEncoding.utf16le ||
          enc == _ReadTextEncoding.utf16be) {
        final b = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
        int i = 0;
        if (utf16Carry != null) {
          if (b.isNotEmpty) {
            final first = b[0];
            final codeUnit = (enc == _ReadTextEncoding.utf16le)
                ? (first << 8) | (utf16Carry!)
                : (utf16Carry! << 8) | first;
            utf16Units.add(codeUnit);
            utf16Carry = null;
            i = 1;
          }
        }
        for (; i + 1 < b.length; i += 2) {
          final b0 = b[i];
          final b1 = b[i + 1];
          final codeUnit = (enc == _ReadTextEncoding.utf16le)
              ? (b1 << 8) | b0
              : (b0 << 8) | b1;
          utf16Units.add(codeUnit);
          if (utf16Units.length >= 2048) {
            out.add(String.fromCharCodes(utf16Units));
            utf16Units.clear();
          }
        }
        if (i < b.length) {
          utf16Carry = b[i];
        }
        return;
      }

      chunked?.add(bytes);
    }

    void flushUtf16() {
      if (utf16Units.isNotEmpty) {
        out.add(String.fromCharCodes(utf16Units));
        utf16Units.clear();
      }
      utf16Carry = null;
    }

    out = StreamController<String>(
      sync: true,
      onListen: () {
        sub = stream.listen(
          (chunk) {
            if (encoding == null) {
              buffer.add(chunk);
              if (buffer.length >= _probeBytes) {
                final all = buffer.toBytes();
                buffer.clear();
                decide(all);
                final rest = (skip > 0 && all.length > skip)
                    ? all.sublist(skip)
                    : (skip > 0 ? Uint8List(0) : all);
                if (rest.isNotEmpty) {
                  decodeChunk(rest);
                }
              }
              return;
            }
            decodeChunk(chunk);
          },
          onDone: () {
            if (encoding == null) {
              final all = buffer.toBytes();
              buffer.clear();
              decide(all);
              final rest = (skip > 0 && all.length > skip)
                  ? all.sublist(skip)
                  : (skip > 0 ? Uint8List(0) : all);
              if (rest.isNotEmpty) {
                decodeChunk(rest);
              }
            }
            if (encoding == _ReadTextEncoding.utf16le ||
                encoding == _ReadTextEncoding.utf16be) {
              flushUtf16();
            }
            chunked?.close();
            stringSink?.close();
            out.close();
          },
          onError: (e, st) {
            out.addError(e, st);
          },
          cancelOnError: true,
        );
      },
      onCancel: () async {
        await sub?.cancel();
      },
    );

    return out.stream;
  }
}

// Chapter
// 章节
class BookChapter {
  // List of pages
  // 页列表
  List<BookPage> pages = List.empty(growable: true);
}

// Page
// 页
class BookPage {
  // List of lines
  // 行列表
  List<BookLine> lines = List.empty(growable: true);

  // If lines are insufficient, fill in the rest
  // 行不够，往后补全
  bool isRepair = false;

  @override
  String toString() {
    return lines.toString();
  }
}

// Line
// 行
class BookLine {
  // Sentence
  // 句子
  final BookSentence sentence;

  // Start position in the sentence
  // 在句子中的开始位置
  final int startIndex;

  // End position in the sentence
  // 在句子中的结束位置
  int? endIndex;

  // If lines are insufficient, fill in the rest
  // 行不够，往后补全
  bool isRepair = false;

  // Is it a title
  // 是否是标题
  bool isTitle = false;

  BookLine(this.sentence, this.startIndex);

  @override
  String toString() {
    return sentence.words.sublist(startIndex, endIndex).toString();
  }
}

// Sentence
// 句
class BookSentence {
  final String? _text;
  List<BookWord>? _wordsCache;

  // Position in the chapter
  // 在章节中的位置
  final int index;

  // Original position in the chapter
  // 在章节中的原始位置
  final int originalIndex;

  BookSentence(List<BookWord> words, this.index, this.originalIndex)
      : _text = null,
        _wordsCache = words;

  BookSentence.fromText(String text, this.index, this.originalIndex)
      : _text = text,
        _wordsCache = null;

  List<BookWord> get words {
    final cached = _wordsCache;
    if (cached != null) return cached;
    final t = _text ?? '';
    final list = List<BookWord>.generate(t.length, (i) => BookWord(t[i], i),
        growable: false);
    _wordsCache = list;
    return list;
  }

  @override
  String toString() {
    if (_text != null) return _text!;
    return (_wordsCache ?? const <BookWord>[]).toString();
  }
}

// Word
// 字
class BookWord {
  // Character
  // 字符
  final String char;

  // Position in the sentence
  // 在句子中的位置
  final int index;

  // Absolute coordinate on the screen
  // 在屏幕的绝对坐标
  int x = 0;
  int y = 0;

  BookWord(this.char, this.index);

  @override
  String toString() {
    return char;
  }
}

class ChapterData {
  int chapterIndex;
  int sentenceIndex;
  int wordIndex;

  // Summary page
  // 简介页
  bool summary;

  // Colophon page, used for chapter comments, interaction pages
  // 尾页，可用于章评，互动页
  bool colophon;

  ChapterData({
    this.chapterIndex = 0,
    this.sentenceIndex = 0,
    this.wordIndex = 0,
    this.summary = false,
    this.colophon = false,
  });
}

abstract class BookSource {
  // Book or chapter title
  // 书籍名或章节名
  String getTitle();

  Future<Map<String, List<BookSentence>>> getData();

  Future<Map<String, List<BookSentence>>> _read(
    Stream<List<int>> source,
    String title,
    bool isSplit, {
    String? encoding,
  }) async {
    final Completer isFinish = Completer<void>();
    final Map<String, List<BookSentence>> result = {};
    List<BookSentence> sentences = List.empty(growable: true);
    result[title] = sentences;
    try {
      int position = 0;
      int originalPosition = 0;
      List<String> splitLongLine(String line) {
        const maxLen = 2000;
        if (line.length <= maxLen) return <String>[line];
        final out = <String>[];
        int start = 0;
        int lastBreak = -1;
        while (start < line.length) {
          final end = (start + maxLen).clamp(0, line.length);
          if (end >= line.length) {
            out.add(line.substring(start));
            break;
          }

          lastBreak = -1;
          final scanStart = (end - 220).clamp(start, end);
          for (int i = scanStart; i < end; i++) {
            final ch = line[i];
            if (ch == '。' ||
                ch == '！' ||
                ch == '？' ||
                ch == '；' ||
                ch == '，' ||
                ch == '.' ||
                ch == '!' ||
                ch == '?' ||
                ch == ';' ||
                ch == ',' ||
                ch == ' ' ||
                ch == '　') {
              lastBreak = i + 1;
            }
          }

          final cut =
              (lastBreak > start + 80 && lastBreak < end) ? lastBreak : end;
          out.add(line.substring(start, cut));
          start = cut;
        }
        return out;
      }

      source
          .transform(_AutoEncodingDecoder(forced: _parseEncoding(encoding)))
          .transform(const LineSplitter())
          .listen((String line) {
        if (line.isNotEmpty) {
          final parts = splitLongLine(line);
          for (final part in parts) {
            if (part.isEmpty) continue;
            BookSentence sentence =
                BookSentence.fromText(part, position, originalPosition);
            sentences.add(sentence);
            position++;
          }
        }
        originalPosition++;
      }, onDone: () {
        debugPrint("wwww,read finish,${sentences.length}");
        if (!isFinish.isCompleted) {
          isFinish.complete();
        }
      }, onError: (e) {
        debugPrint("wwww,read error1:$e");
        if (!isFinish.isCompleted) {
          isFinish.complete();
        }
      });
      await isFinish.future;
    } catch (e) {
      debugPrint("wwww,read error2:$e");
    }
    final hasAny = result.values.any((e) => e.isNotEmpty);
    if (!hasAny) return {};
    return result;
  }
}

class FileSource extends BookSource {
  final String source;
  final String title;
  final bool isSplit;
  final String? encoding;

  FileSource(this.source, this.title, {this.isSplit = false, this.encoding});

  @override
  Future<Map<String, List<BookSentence>>> getData() {
    File file = File(source);
    Stream<List<int>> stream;
    if (file.existsSync()) {
      stream = file.openRead();
    } else {
      stream = const Stream.empty();
    }
    return _read(stream, title, isSplit, encoding: encoding);
  }

  @override
  String getTitle() => title;
}

class ByteDataSource extends BookSource {
  final ByteData source;
  final String title;
  final bool isSplit;
  final String? encoding;

  ByteDataSource(this.source, this.title,
      {this.isSplit = false, this.encoding});

  @override
  Future<Map<String, List<BookSentence>>> getData() {
    Uint8List bytes = source.buffer.asUint8List();
    StreamController<List<int>> controller = StreamController<List<int>>();
    controller.add(bytes);
    controller.close();
    Stream<List<int>> stream = controller.stream;
    return _read(stream, title, isSplit, encoding: encoding);
  }

  @override
  String getTitle() => title;
}

class StringSource extends BookSource {
  final String source;
  final String title;
  final bool isSplit;
  final String? encoding;

  StringSource(this.source, this.title, {this.isSplit = false, this.encoding});

  @override
  Future<Map<String, List<BookSentence>>> getData() {
    StreamController<List<int>> controller = StreamController<List<int>>();
    List<int> bytes = utf8.encode(source);
    controller.add(bytes);
    controller.close();
    Stream<List<int>> stream = controller.stream;
    return _read(stream, title, isSplit, encoding: encoding);
  }

  @override
  String getTitle() => title;
}

class ChapterSource extends BookSource {
  final List<BookSentence> source;
  final String title;

  ChapterSource(this.source, this.title);

  @override
  Future<Map<String, List<BookSentence>>> getData() async {
    return {title: source};
  }

  @override
  String getTitle() => title;
}

// Page rendering data
// 页面绘制数据
class PaintData {
  final int chapterIndex;
  final String title;
  final BookPage? bookPage;
  final Widget? widget;
  final ValueNotifier<ui.Picture?> picture = ValueNotifier(null);

  PaintData(this.chapterIndex, this.title, {this.bookPage, this.widget});
}

class BookProgress {
  // Chapter index
  // 章节下标
  final String chapterTitle;

  // Chapter index
  // 章节下标
  final int chapterIndex;

  // Page index
  // 页下标
  final int pageIndex;

  // Total pages
  // 总页数
  final int pageTotal;

  // Sentence index in the chapter
  // 句在章节里的下标
  final int sentenceIndex;

  // Original sentence index in the chapter
  // 句在章节里的原始下标
  final int sentenceOriginalIndex;

  // Word index in the sentence
  // 字在句里的下标
  final int wordIndex;

  // Is it an interaction page
  // 是否是互动页
  final bool interaction;

  // Is it a summary page
  // 是否是简介页
  final bool snapshot;

  // Page data
  // 页面数据
  final BookPage? bookPage;

  BookProgress(
      this.chapterTitle,
      this.chapterIndex,
      this.pageIndex,
      this.pageTotal,
      this.sentenceIndex,
      this.sentenceOriginalIndex,
      this.wordIndex,
      this.bookPage,
      [this.interaction = false,
      this.snapshot = false]);

  static BookProgress zero = BookProgress("", 0, 0, 0, 0, 0, 0, null);

  @override
  String toString() {
    return "chapterTitle:$chapterTitle,chapterIndex:$chapterIndex,pageIndex:$pageIndex,pageTotal:$pageTotal,sentenceIndex:$sentenceIndex,sentenceOriginalIndex:$sentenceOriginalIndex,wordIndex:$wordIndex,interaction:$interaction,snapshot:$snapshot";
  }
}
