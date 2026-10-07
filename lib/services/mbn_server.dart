import 'dart:async';
import '../core/app_platform.dart';
import '../core/platform_ui.dart' show isAndroidTv;
import 'package:flutter/foundation.dart';
import 'web_gateway.dart';
import 'cross_app_auth.dart';
import 'network_gate.dart';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class MbnServerException implements Exception {
  const MbnServerException(this.message, {this.statusCode, this.details});
  final String message;
  final int? statusCode;
  final Map<String, dynamic>? details;
  @override
  String toString() => message;
}

/// Transport for the MBN account server (https://login.a.mbnpro.ir).
/// Owns the JWT: login persists it, every other call sends it, logout wipes
/// it. Offline/network failures surface as [MbnServerException] without a
/// status code so callers can tell "no connection" apart from rejections.
class MbnServerClient {
  MbnServerClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl = baseUrl ?? (kIsWeb ? Uri.base.origin : defaultBaseUrl);

  static const defaultBaseUrl = 'https://login.a.mbnpro.ir';
  static const _tokenKey = 'mbn_secure_token';
  static const _emailKey = 'mbn_session_email';
  static const _secureStorage = FlutterSecureStorage();

  final http.Client _client;
  final NetworkRequestGate _requests = NetworkRequestGate();
  final String baseUrl;
  String? _token;
  int _generation = 0;
  String? get token => _token;
  set token(String? value) {
    if (_token != value) _generation++;
    _token = value;
    WebGateway.token = value;
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse(baseUrl).replace(path: path, queryParameters: query);

  Future<Map<String, dynamic>> _decode(http.Response response) async {
    Map<String, dynamic> data;
    try {
      data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const MbnServerException('پاسخ سرور نامعتبر است.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MbnServerException(
        data['error']?.toString() ?? 'خطا (کد ${response.statusCode}).',
        statusCode: response.statusCode,
        details: data,
      );
    }
    return data;
  }

  Map<String, String> _headers(String? credential, {bool json = false}) => {
    'X-MBN-Platform': kIsWeb
        ? 'web'
        : isAndroidTv
        ? 'android_tv'
        : Platform.operatingSystem,
    if (json) 'Content-Type': 'application/json',
    if (credential != null) 'Authorization': 'Bearer $credential',
  };

  Future<Map<String, dynamic>> _requestJson(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final credential = token;
    final generation = _generation;
    final uri = _uri(path, query);
    final headers = _headers(credential, json: body != null);
    final encoded = body == null ? null : jsonEncode(body);
    try {
      final response = await _requests.run<http.Response>(
        '$method $uri $generation',
        () async {
          if (_generation != generation) {
            throw http.ClientException('حساب تغییر کرده است.');
          }
          Future<http.Response> send() {
            if (_generation != generation) {
              throw http.ClientException('حساب تغییر کرده است.');
            }
            return sendBuffered(
              _client,
              method,
              uri,
              headers: headers,
              body: encoded,
              followRedirects: false,
            );
          }

          return method == 'GET' ? readWithRetry(send) : send();
        },
        dedupe: method == 'GET',
      );
      if (_generation != generation) {
        throw http.ClientException('حساب تغییر کرده است.');
      }
      return await _decode(response);
    } on MbnServerException {
      rethrow;
    } catch (_) {
      throw const MbnServerException(
        'اتصال به سرور برقرار نشد؛ دوباره تلاش کنید.',
      );
    }
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) => _requestJson('POST', path, body: body);
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
  }) => _requestJson('GET', path, query: query);
  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body,
  ) => _requestJson('PUT', path, body: body);

  Future<void> persistToken(String email) async {
    try {
      if (token != null) {
        await _secureStorage.write(key: _tokenKey, value: token);
        await CrossAppAuth.saveSharedToken(token: token!, email: email);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_emailKey, email);
    } catch (_) {}
  }

  Future<String?> readToken() async {
    try {
      return await _secureStorage.read(key: _tokenKey);
    } catch (_) {
      return null;
    }
  }

  Future<String?> readEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_emailKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearToken() async {
    final oldToken = token;
    if (oldToken != null) {
      sendBuffered(
        _client,
        'POST',
        _uri('/api/auth/logout'),
        headers: {'Authorization': 'Bearer $oldToken'},
        timeout: const Duration(seconds: 5),
        followRedirects: false,
      ).then((_) {}, onError: (Object _) {});
    }
    token = null;
    await CrossAppAuth.clearSharedToken(token: oldToken);
    try {
      await _secureStorage.delete(key: _tokenKey);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_emailKey);
    } catch (_) {}
  }
}
