import 'dart:async';
import 'dart:ui' show Codec, ImmutableBuffer;

import 'package:NasCabOS/modules/base/components/custom_extended_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

class NotesNetworkImageProvider
    extends ImageProvider<NotesNetworkImageProvider> {
  const NotesNetworkImageProvider(this.url);

  final String url;

  @override
  Future<NotesNetworkImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) {
    return SynchronousFuture<NotesNetworkImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    NotesNetworkImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1,
      debugLabel: url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<String>('URL', url),
      ],
    );
  }

  Future<Codec> _loadAsync(
    NotesNetworkImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    try {
      final bytes = await CustomExtendedImage.getOrCreateLoadFuture(url);
      final buffer = await ImmutableBuffer.fromUint8List(bytes);
      return decode(buffer);
    } on Exception {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotesNetworkImageProvider && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
