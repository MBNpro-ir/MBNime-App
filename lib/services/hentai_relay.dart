import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'hentai_network.dart';

/// Local loopback relay that serves a +18 MP4 stream to libmpv.
///
/// Why not just set mpv's `http-proxy`? Per the mpv manual, that option must
/// start with `http://` *and* "Proxies are not used for https URLs" — while
/// the video files are https. mpv also never reads the Windows system proxy.
/// So when the proxy route wins the [HentaiNetwork.probeRoute] race, playback
/// goes through this relay instead: mpv opens a plain localhost http URL
/// (mpv's `http-proxy` stays cleared) and the relay forwards upstream over
/// the system proxy, passing `Range` through so seeking works.
///
/// When the direct route wins, no relay is needed and mpv opens the original
/// URL. One instance lives per player screen and is closed on dispose.
class HentaiMediaRelay {
  HentaiMediaRelay({this._upstreamClient});

  final http.Client? _upstreamClient;
  HttpServer? _server;
  bool _listening = false;
  final Map<String, Uri> _targets = {};
  int _seq = 0;

  bool get isServing => _server != null;

  /// Registers [upstream] and returns its localhost URL for mpv.
  Future<Uri> serve(Uri upstream) async {
    _server ??= await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (!_listening) {
      _listening = true;
      _server!.listen(_handle);
    }
    final token = 's${_seq++}';
    _targets[token] = upstream;
    while (_targets.length > 8) {
      _targets.remove(_targets.keys.first);
    }
    return Uri.parse(
      'http://127.0.0.1:${_server!.port}/t/$token${_extensionOf(upstream.path)}',
    );
  }

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '.mp4';
    final ext = path.substring(dot);
    if (ext.length > 5 || !RegExp(r'^\.[A-Za-z0-9]+$').hasMatch(ext)) {
      return '.mp4';
    }
    return ext;
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final segments = request.uri.pathSegments;
      final rawToken = segments.length == 2 && segments[0] == 't'
          ? segments[1]
          : '';
      final dot = rawToken.indexOf('.');
      final token = dot < 0 ? rawToken : rawToken.substring(0, dot);
      final target = _targets[token];
      if (target == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }
      final client = _upstreamClient ?? await HentaiNetwork.proxyLeg();
      final outgoing = http.Request(request.method, target);
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null && range.isNotEmpty) {
        outgoing.headers[HttpHeaders.rangeHeader] = range;
      }
      outgoing.headers[HttpHeaders.userAgentHeader] =
          request.headers.value(HttpHeaders.userAgentHeader) ?? 'MBNime/1.0';
      outgoing.headers[HttpHeaders.acceptHeader] = '*/*';
      // Identity keeps Content-Length intact for mpv's seeking math.
      outgoing.headers[HttpHeaders.acceptEncodingHeader] = 'identity';
      late final http.StreamedResponse upstream;
      try {
        upstream = await client
            .send(outgoing)
            .timeout(const Duration(seconds: 15));
      } catch (_) {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
        return;
      }
      final response = request.response
        ..statusCode = upstream.statusCode
        ..headers.set(
          HttpHeaders.contentTypeHeader,
          upstream.headers['content-type'] ?? 'video/mp4',
        );
      for (final name in [
        HttpHeaders.contentLengthHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.acceptRangesHeader,
      ]) {
        final value = upstream.headers[name];
        if (value != null) response.headers.set(name, value);
      }
      if (request.method == 'HEAD') {
        await upstream.stream.drain().catchError((Object _) {});
        await response.close();
        return;
      }
      try {
        await response.addStream(
          upstream.stream.timeout(const Duration(seconds: 45)),
        );
        await response.close();
      } catch (_) {
        // mpv went away (seek/dispose): drop the upstream quietly.
        unawaited(upstream.stream.drain().catchError((Object _) {}));
        try {
          await response.close();
        } catch (_) {}
      }
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    _listening = false;
    _targets.clear();
    try {
      await server?.close(force: true);
    } catch (_) {}
  }
}
