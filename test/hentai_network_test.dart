import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mbnime/services/hentai_network.dart';
import 'package:mbnime/services/hentai_relay.dart';

class _FakeLeg extends http.BaseClient {
  _FakeLeg(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  final List<http.BaseRequest> seen = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    seen.add(request);
    return handler(request);
  }
}

http.StreamedResponse _text(
  String body, {
  int status = 200,
  Map<String, String>? headers,
}) => http.StreamedResponse(
  Stream.value(utf8.encode(body)),
  status,
  headers: headers ?? const {},
);

Future<String> _read(http.StreamedResponse response) =>
    response.stream.transform(utf8.decoder).join();

void main() {
  setUp(HentaiNetwork.resetForTests);

  group('WindowsSystemProxy.normalizeProxyServer', () {
    test('plain host:port passes through', () {
      expect(
        WindowsSystemProxy.normalizeProxyServer('127.0.0.1:10809'),
        '127.0.0.1:10809',
      );
    });

    test('https entry wins over http in per-scheme lists', () {
      expect(
        WindowsSystemProxy.normalizeProxyServer(
          'http=127.0.0.1:1080;https=127.0.0.1:10809',
        ),
        '127.0.0.1:10809',
      );
    });

    test('http entry used when no https entry exists', () {
      expect(
        WindowsSystemProxy.normalizeProxyServer('http=10.0.0.2:8080'),
        '10.0.0.2:8080',
      );
    });

    test('scheme prefixes are stripped', () {
      expect(
        WindowsSystemProxy.normalizeProxyServer('http://127.0.0.1:8080/'),
        '127.0.0.1:8080',
      );
    });

    test('missing port defaults to 1080 like Dart PROXY strings', () {
      expect(
        WindowsSystemProxy.normalizeProxyServer('proxy.local'),
        'proxy.local:1080',
      );
    });

    test('empty input gives null', () {
      expect(WindowsSystemProxy.normalizeProxyServer(null), isNull);
      expect(WindowsSystemProxy.normalizeProxyServer('  '), isNull);
      expect(WindowsSystemProxy.normalizeProxyServer('http=;https='), isNull);
    });
  });

  group('WindowsSystemProxy registry parsing', () {
    const enabledOutput =
        '\nHKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings\n'
        '    ProxyEnable    REG_DWORD    0x1\n';
    const disabledOutput =
        '\nHKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings\n'
        '    ProxyEnable    REG_DWORD    0x0\n';
    const serverOutput =
        '\nHKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings\n'
        '    ProxyServer    REG_SZ    127.0.0.1:10809\n';

    test('detects enabled vs disabled proxy', () {
      expect(
        WindowsSystemProxy.isProxyEnabledRegOutput(enabledOutput),
        isTrue,
      );
      expect(
        WindowsSystemProxy.isProxyEnabledRegOutput(disabledOutput),
        isFalse,
      );
      expect(WindowsSystemProxy.isProxyEnabledRegOutput('garbage'), isFalse);
    });

    test('extracts the ProxyServer value', () {
      expect(
        WindowsSystemProxy.regStringValue(serverOutput, 'ProxyServer'),
        '127.0.0.1:10809',
      );
      expect(
        WindowsSystemProxy.regStringValue(serverOutput, 'Missing'),
        isNull,
      );
    });
  });

  group('HentaiRaceClient', () {
    test('fastest leg wins and both legs get an identical request', () async {
      final direct = _FakeLeg(
        (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return _text('direct');
        },
      );
      final proxy = _FakeLeg((_) async => _text('proxy'));
      final client = HentaiRaceClient(direct: direct, proxy: proxy);

      final response = await client.get(
        Uri.parse('https://hentaiiran.com/wp-json/'),
      );
      expect(response.statusCode, 200);
      expect(response.body, 'proxy');
      expect(HentaiNetwork.preferProxy, isTrue);

      expect(direct.seen, hasLength(1));
      expect(proxy.seen, hasLength(1));
      expect(direct.seen.single.method, 'GET');
      expect(direct.seen.single.url, proxy.seen.single.url);
      client.close();
    });

    test('failed fast leg falls through to the slow leg', () async {
      final direct = _FakeLeg(
        (_) async => throw const SocketException('filtered'),
      );
      final proxy = _FakeLeg((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return _text('proxy');
      });
      final client = HentaiRaceClient(direct: direct, proxy: proxy);

      final response = await client.get(Uri.parse('https://example.invalid/'));
      expect(response.body, 'proxy');
      expect(HentaiNetwork.preferProxy, isTrue);
      client.close();
    });

    test('throws when both legs fail', () async {
      final client = HentaiRaceClient(
        direct: _FakeLeg(
          (_) async => throw const SocketException('nope'),
        ),
        proxy: _FakeLeg(
          (_) async => throw const SocketException('nope'),
        ),
      );
      await expectLater(
        client.get(Uri.parse('https://example.invalid/')),
        throwsA(isA<SocketException>()),
      );
      client.close();
    });

    test('a non-200 response still wins its route (proves connectivity)', () async {
      final direct = _FakeLeg((_) async => _text('bad', status: 400));
      final proxy = _FakeLeg((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return _text('slow');
      });
      final client = HentaiRaceClient(direct: direct, proxy: proxy);

      final response = await client.get(Uri.parse('https://example.invalid/'));
      expect(response.statusCode, 400);
      expect(HentaiNetwork.preferProxy, isFalse);
      client.close();
    });

    test('winner body stays intact (loser drain never touches it)', () async {
      final direct = _FakeLeg(
        (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return _text('direct-body');
        },
      );
      final proxy = _FakeLeg((_) async => _text('proxy-body'));
      final client = HentaiRaceClient(direct: direct, proxy: proxy);

      final streamed = await client.send(
        http.Request('GET', Uri.parse('https://example.invalid/')),
      );
      expect(await _read(streamed), 'proxy-body');
      client.close();
    });
  });

  group('route memory', () {
    test('failure on the preferred side flips stickiness', () {
      expect(HentaiNetwork.preferProxy, isFalse);
      HentaiNetwork.noteRoute(proxy: true);
      expect(HentaiNetwork.preferProxy, isTrue);
      HentaiNetwork.noteRouteFailure(proxy: true);
      expect(HentaiNetwork.preferProxy, isFalse);
      // Failure on the non-preferred side changes nothing.
      HentaiNetwork.noteRouteFailure(proxy: true);
      expect(HentaiNetwork.preferProxy, isFalse);
    });

    test('firstSuccess waits for the slow side when fast fails', () async {
      final slow = Future.delayed(
        const Duration(milliseconds: 10),
        () => 'slow-wins',
      );
      final fast = Future<String>.error(Exception('boom'));
      expect(await HentaiNetwork.firstSuccess(fast, slow), 'slow-wins');
    });

    test('firstSuccess throws when both fail', () async {
      await expectLater(
        HentaiNetwork.firstSuccess(
          Future<String>.error(Exception('a')),
          Future<String>.error(Exception('b')),
        ),
        throwsException,
      );
    });
  });

  group('HentaiMediaRelay', () {
    test('forwards Range and streams bytes with headers intact', () async {
      String? seenRange;
      final upstream = MockClient((request) async {
        seenRange = request.headers['range'];
        return http.Response.bytes(
          [1, 2, 3, 4],
          206,
          headers: {
            'content-type': 'video/mp4',
            'content-range': 'bytes 0-3/100',
            'accept-ranges': 'bytes',
          },
        );
      });
      final relay = HentaiMediaRelay(upstreamClient: upstream);
      addTearDown(relay.close);

      final local = await relay.serve(Uri.parse('https://cdn.invalid/v.mp4'));
      expect(local.host, '127.0.0.1');

      final direct = HttpClient();
      try {
        final request = await direct.getUrl(local);
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-3');
        final response = await request.close();
        expect(response.statusCode, 206);
        expect(response.headers.value('content-range'), 'bytes 0-3/100');
        final bytes = await response.fold<List<int>>(
          [],
          (all, chunk) => all..addAll(chunk),
        );
        expect(bytes, [1, 2, 3, 4]);
      } finally {
        direct.close(force: true);
      }
      expect(seenRange, 'bytes=0-3');
    });

    test('unknown token gives 404', () async {
      final relay = HentaiMediaRelay(
        upstreamClient: MockClient((_) async => http.Response('', 200)),
      );
      addTearDown(relay.close);

      final local = await relay.serve(Uri.parse('https://cdn.invalid/v.mp4'));
      final unknown = local.replace(path: '/t/nope.mp4');
      final direct = HttpClient();
      try {
        final request = await direct.getUrl(unknown);
        final response = await request.close();
        await response.drain();
        expect(response.statusCode, 404);
      } finally {
        direct.close(force: true);
      }
    });
  });
}
