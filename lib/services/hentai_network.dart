import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Networking policy exclusive to the +18 section on Windows.
///
/// Background (verified against current docs):
///
/// * Dart's [HttpClient] only honors proxy *environment variables*
///   ([HttpClient.findProxyFromEnvironment]) and deliberately ignores the
///   Windows system proxy (the WinINET settings that tools like V2RayN write
///   in "system proxy" mode) — see dart-lang/sdk#50434, still open.
/// * mpv's `http-proxy` option must start with `http://` and — per the mpv
///   manual — "Proxies are not used for https URLs", so it cannot carry the
///   (https) video streams either. mpv never reads the WinINET proxy.
///
/// Hence, for +18 traffic on Windows this file:
///
/// 1. reads the WinINET manual proxy from the registry
///    (`HKCU\...\Internet Settings`, `ProxyEnable` + `ProxyServer`),
/// 2. races every request over DIRECT and the system proxy in parallel and
///    keeps whichever finishes first (happy-eyeballs style — important
///    because filtered hosts usually *hang* instead of refusing, which would
///    make a sequential fallback wait out the full timeout every time),
/// 3. remembers the winner (sticky route) and flips to the other side as
///    soon as the winner fails, so traffic keeps switching between the two.
///
/// Normal-anime traffic never touches this file and is pinned to DIRECT
/// (see `AnimeOnApi`), so the system proxy can never leak into it.
class WindowsSystemProxy {
  WindowsSystemProxy._();

  static const _key =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
  static const _ttl = Duration(seconds: 30);

  static String? _cached;
  static DateTime? _cachedAt;

  /// Last resolved value (`host:port`) without doing any I/O.
  /// Refreshed by [current] before every raced request.
  static String? get snapshot => _cached;

  /// The WinINET manual proxy as `host:port`, or null when unavailable,
  /// disabled, or not on Windows. Result is cached for [_ttl] so toggling a
  /// VPN is picked up within half a minute. Never throws.
  static Future<String?> current() async {
    if (!Platform.isWindows) return null;
    final now = DateTime.now();
    if (_cachedAt != null && now.difference(_cachedAt!) < _ttl) {
      return _cached;
    }
    String? proxy;
    try {
      proxy = await _read().timeout(const Duration(seconds: 4));
    } catch (_) {
      proxy = null;
    }
    _cached = proxy;
    _cachedAt = now;
    return proxy;
  }

  static Future<String?> _read() async {
    final enabled = await Process.run(
      'reg',
      ['query', _key, '/v', 'ProxyEnable'],
    ).timeout(const Duration(seconds: 4));
    if (enabled.exitCode != 0 ||
        !isProxyEnabledRegOutput(enabled.stdout.toString())) {
      return null;
    }
    final server = await Process.run(
      'reg',
      ['query', _key, '/v', 'ProxyServer'],
    ).timeout(const Duration(seconds: 4));
    if (server.exitCode != 0) return null;
    return normalizeProxyServer(
      regStringValue(server.stdout.toString(), 'ProxyServer'),
    );
  }

  /// Parses `reg query` output for a `REG_DWORD` value that is != 0.
  /// Pure (unit-testable) helper.
  static bool isProxyEnabledRegOutput(String output) {
    final match = RegExp(
      r'^\s*ProxyEnable\s+REG_DWORD\s+0x([0-9a-fA-F]+)\s*$',
      multiLine: true,
    ).firstMatch(output);
    if (match == null) return false;
    return (int.tryParse(match.group(1)!, radix: 16) ?? 0) != 0;
  }

  /// Extracts the data of a `REG_SZ`/`REG_EXPAND_SZ` value from `reg query`
  /// output. Pure (unit-testable) helper.
  static String? regStringValue(String output, String name) {
    final match = RegExp(
      '^\\s*${RegExp.escape(name)}\\s+REG_(?:SZ|EXPAND_SZ)\\s+(.+?)\\s*\$',
      multiLine: true,
    ).firstMatch(output);
    final value = match?.group(1)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  /// Normalizes a WinINET `ProxyServer` value to `host:port`.
  ///
  /// Accepts `127.0.0.1:10809`, `http=...;https=...` lists (https entry
  /// wins, then http, then a bare entry) and `http(s)://` prefixes. A
  /// missing port defaults to 1080, mirroring Dart's documented behavior
  /// for `PROXY host` strings. Pure (unit-testable) helper.
  static String? normalizeProxyServer(String? raw) {
    if (raw == null) return null;
    var value = raw.trim();
    if (value.isEmpty) return null;
    if (value.contains('=')) {
      String? https;
      String? httpEntry;
      String? bare;
      for (final part in value.split(';')) {
        final segment = part.trim();
        if (segment.isEmpty) continue;
        final eq = segment.indexOf('=');
        if (eq < 0) {
          bare ??= segment;
          continue;
        }
        final scheme = segment.substring(0, eq).trim().toLowerCase();
        final host = segment.substring(eq + 1).trim();
        if (scheme == 'https') {
          https ??= host;
        } else if (scheme == 'http') {
          httpEntry ??= host;
        }
      }
      value = https ?? httpEntry ?? bare ?? '';
      if (value.isEmpty) return null;
    }
    value = value.replaceFirst(
      RegExp(r'^https?://', caseSensitive: false),
      '',
    );
    final slash = value.indexOf('/');
    if (slash >= 0) value = value.substring(0, slash);
    value = value.trim();
    if (value.isEmpty) return null;
    if (!value.contains(':')) value = '$value:1080';
    return value;
  }
}

/// Process-wide route memory shared by the API race client, the image
/// fetcher and the playback prober. `true` = the proxy side won last.
class HentaiNetwork {
  HentaiNetwork._();

  static bool _preferProxy = false;
  static HentaiRaceClient? _shared;

  /// Last winning side. Read by single-fetch paths (images, covers).
  static bool get preferProxy => _preferProxy;

  static void noteRoute({required bool proxy}) => _preferProxy = proxy;

  /// A leg just failed: if it was the preferred one, flip immediately so
  /// the next single-fetch attempt uses the other side.
  static void noteRouteFailure({required bool proxy}) {
    if (proxy == _preferProxy) _preferProxy = !_preferProxy;
  }

  /// Manual flip (used for the one-shot playback retry on the other route).
  static void flipRoute() => _preferProxy = !_preferProxy;

  /// Test-only reset of the process-wide route memory.
  static void resetForTests() {
    _preferProxy = false;
    _shared = null;
  }

  static Future<HentaiRaceClient> _sharedClient() async {
    final client = _shared ??= HentaiRaceClient();
    await client.ensureLegs();
    return client;
  }

  /// The proxy-side leg (system proxy, env fallback) for dedicated uses
  /// such as the local media relay's upstream.
  static Future<http.Client> proxyLeg() async =>
      (await _sharedClient()).proxyLeg;

  /// Single GET with sticky order + fallback to the other side.
  /// Used for payloads where doubling traffic (posters, covers) is wasteful
  /// but route switching on failure is still required.
  static Future<http.Response> fetchBytes(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final race = await _sharedClient();
    final order = _preferProxy ? const [1, 0] : const [0, 1];
    Object? error;
    for (final leg in order) {
      try {
        final request = http.Request('GET', uri);
        if (headers != null) request.headers.addAll(headers);
        final streamed = await race
            .sendOnLeg(leg, request)
            .timeout(timeout);
        final response = await http.Response.fromStream(streamed);
        noteRoute(proxy: leg == 1);
        return response;
      } catch (e) {
        error = e;
        noteRouteFailure(proxy: leg == 1);
      }
    }
    throw error ?? StateError('HentaiNetwork.fetchBytes: no route');
  }

  /// Lightweight parallel probe of a stream URL (`Range: bytes=0-0` on both
  /// legs). Returns true when the proxy side wins. Any completed HTTP
  /// response counts as "route works" — only transport exceptions fail.
  static Future<bool> probeRoute(Uri uri) async {
    final race = await _sharedClient();
    Future<bool> attempt(int leg) async {
      final request = http.Request('GET', uri)
        ..headers['Range'] = 'bytes=0-0'
        ..headers['User-Agent'] = 'MBNime/1.0';
      final streamed = await race
          .sendOnLeg(leg, request)
          .timeout(const Duration(seconds: 6));
      await streamed.stream.drain().timeout(const Duration(seconds: 6));
      return leg == 1;
    }

    final wonProxy = await firstSuccess(attempt(0), attempt(1));
    noteRoute(proxy: wonProxy);
    return wonProxy;
  }

  /// First successfully completed future wins; if the faster side throws,
  /// the slower side still gets its chance. Throws when both fail.
  static Future<T> firstSuccess<T>(Future<T> a, Future<T> b) async {
    var aFailed = false;
    var bFailed = false;
    final guardedA = a.then<T>(
      (value) => value,
      onError: (Object e) {
        aFailed = true;
        throw e;
      },
    );
    final guardedB = b.then<T>(
      (value) => value,
      onError: (Object e) {
        bFailed = true;
        throw e;
      },
    );
    try {
      return await Future.any([guardedA, guardedB]);
    } catch (_) {
      if (aFailed && !bFailed) return b;
      if (bFailed && !aFailed) return a;
      rethrow;
    }
  }
}

/// `package:http` client racing every request over DIRECT and the Windows
/// system proxy in parallel. The first completed HTTP response wins — even
/// a 4xx/5xx status proves its route works (e.g. WP's 400 past-last-page is
/// meaningful); only transport exceptions fall through to the other leg.
/// The loser's body is drained in the background so its socket returns to
/// the pool. Inject legs in tests; production uses [HentaiRaceClient.new].
class HentaiRaceClient extends http.BaseClient {
  HentaiRaceClient({http.Client? direct, http.Client? proxy})
    : _direct = direct ?? _directLeg(),
      _proxyLeg = proxy;

  static http.Client _directLeg() {
    final inner = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    inner.findProxy = (_) => 'DIRECT';
    return IOClient(inner);
  }

  final http.Client _direct;
  http.Client? _proxyLeg;
  String? _proxyRaw;
  DateTime? _refreshedAt;
  static const _refreshInterval = Duration(seconds: 30);

  /// The proxy-side leg (system proxy with env fallback).
  http.Client get proxyLeg => _proxyLeg ?? _direct;

  /// Resolves/refreshes the system proxy (cached, never throws).
  Future<void> ensureLegs() async {
    final now = DateTime.now();
    if (_proxyLeg != null &&
        _refreshedAt != null &&
        now.difference(_refreshedAt!) < _refreshInterval) {
      return;
    }
    _proxyRaw = await WindowsSystemProxy.current();
    _proxyLeg ??= _buildProxyLeg();
    _refreshedAt = now;
  }

  http.Client _buildProxyLeg() {
    final inner = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    inner.findProxy = (uri) {
      final raw = _proxyRaw;
      if (raw != null && raw.isNotEmpty) return 'PROXY $raw';
      return HttpClient.findProxyFromEnvironment(uri);
    };
    return IOClient(inner);
  }

  /// Single-leg send (used by sticky paths). Ensures legs first.
  Future<http.StreamedResponse> sendOnLeg(
    int leg,
    http.BaseRequest request,
  ) async {
    await ensureLegs();
    return (leg == 1 ? _proxyLeg! : _direct).send(request);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await ensureLegs();
    final copies = await _twoCopies(request);
    var recorded = false;
    void note(bool proxy) {
      // Only the first success of this race updates the sticky route;
      // the loser's late completion must not overwrite the winner.
      if (!recorded) {
        recorded = true;
        HentaiNetwork.noteRoute(proxy: proxy);
      }
    }

    Future<http.StreamedResponse> attempt(int leg) async {
      try {
        final response = await (leg == 1 ? _proxyLeg! : _direct).send(
          copies[leg],
        );
        note(leg == 1);
        return response;
      } catch (e) {
        HentaiNetwork.noteRouteFailure(proxy: leg == 1);
        rethrow;
      }
    }

    final first = attempt(0);
    final second = attempt(1);
    final winner = await HentaiNetwork.firstSuccess(first, second);
    // Drain ONLY the loser in the background so its socket returns to the
    // pool. The winner's body belongs to the caller and must stay intact.
    for (final pending in [first, second]) {
      unawaited(
        pending
            .then((response) {
              if (!identical(response, winner)) {
                return response.stream.drain();
              }
            })
            .catchError((Object _) {}),
      );
    }
    return winner;
  }

  /// Two equivalent, independently-sendable copies of [original].
  /// (`package:http` requests are single-use: their body stream can only be
  /// finalized once, so a parallel race must never reuse the same object —
  /// the second send would throw a StateError.)
  static Future<List<http.Request>> _twoCopies(
    http.BaseRequest original,
  ) async {
    final method = original.method;
    final url = original.url;
    final headers = Map<String, String>.of(original.headers);
    final followRedirects = original.followRedirects;
    final maxRedirects = original.maxRedirects;
    final persistentConnection = original.persistentConnection;
    final List<int> body;
    if (original is http.Request) {
      body = original.bodyBytes;
    } else {
      body = await original.finalize().toBytes();
    }
    http.Request make() => http.Request(method, url)
      ..headers.addAll(headers)
      ..followRedirects = followRedirects
      ..maxRedirects = maxRedirects
      ..persistentConnection = persistentConnection
      ..bodyBytes = body;
    return [make(), make()];
  }

  @override
  void close() {
    _direct.close();
    _proxyLeg?.close();
    super.close();
  }
}
