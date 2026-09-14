import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../services/hentai_network.dart';

/// Picks the image provider for a URL.
///
/// On Windows, +18 artwork must be able to travel over the Windows system
/// proxy (plain `NetworkImage` only honors proxy *environment* variables),
/// so it goes through the +18 race/fetch machinery. Everything else —
/// including all normal-anime artwork on every platform — keeps the
/// framework's `NetworkImage`, which never sees the system proxy.
ImageProvider imageProviderForUrl(
  String url, {
  required bool viaUnstableRoute,
}) {
  if (viaUnstableRoute && Platform.isWindows) {
    return HentaiHttpImage(url);
  }
  return NetworkImage(url);
}

/// `NetworkImage` equivalent that downloads bytes through
/// [HentaiNetwork.fetchBytes] (sticky route + fallback) instead of the
/// framework's shared `HttpClient`. Decoding, caching and error semantics
/// mirror the framework implementation.
@immutable
class HentaiHttpImage extends ImageProvider<HentaiHttpImage> {
  const HentaiHttpImage(this.url, {this.scale = 1.0, this.headers});

  final String url;
  final double scale;
  final Map<String, String>? headers;

  @override
  Future<HentaiHttpImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<HentaiHttpImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    HentaiHttpImage key,
    ImageDecoderCallback decode,
  ) {
    // Ownership of this controller is handed off to [_loadAsync]; it is that
    // method's responsibility to close the controller's stream when the image
    // has been loaded or an error is thrown.
    final chunkEvents = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, chunkEvents, decode: decode),
      chunkEvents: chunkEvents.stream,
      scale: key.scale,
      debugLabel: key.url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<HentaiHttpImage>('Image key', key),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(
    HentaiHttpImage key,
    StreamController<ImageChunkEvent> chunkEvents, {
    required ImageDecoderCallback decode,
  }) async {
    try {
      assert(key == this);
      final uri = Uri.base.resolve(key.url);
      int received = 0;
      final response = await HentaiNetwork.fetchBytes(
        uri,
        headers: headers,
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode != HttpStatus.ok) {
        throw NetworkImageLoadException(
          statusCode: response.statusCode,
          uri: uri,
        );
      }
      final bytes = response.bodyBytes;
      received = bytes.lengthInBytes;
      if (bytes.isEmpty) {
        throw Exception('HentaiHttpImage is an empty file: $uri');
      }
      chunkEvents.add(
        ImageChunkEvent(
          cumulativeBytesLoaded: received,
          expectedTotalBytes: received,
        ),
      );
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return decode(buffer);
    } catch (e) {
      // Depending on where the exception was thrown, the image cache may not
      // have had a chance to track the key in the cache at all.
      // Schedule a microtask to give the cache a chance to add the key.
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
      rethrow;
    } finally {
      // ignore: unawaited_futures
      chunkEvents.close().catchError((Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'painting library',
            context: ErrorDescription(
              'while closing chunkEvents stream in HentaiHttpImage.load',
            ),
          ),
        );
      });
    }
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is HentaiHttpImage &&
        other.url == url &&
        other.scale == scale &&
        mapEquals(other.headers, headers);
  }

  @override
  int get hashCode => Object.hash(url, scale, headers);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'HentaiHttpImage')}("$url", scale: ${scale.toStringAsFixed(1)})';
}
