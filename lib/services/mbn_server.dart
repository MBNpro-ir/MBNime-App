import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class MbnServerException implements Exception {
  const MbnServerException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
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
      baseUrl = baseUrl ?? defaultBaseUrl;

  static const defaultBaseUrl = 'https://login.a.mbnpro.ir';
  static const _tokenKey = 'mbn_secure_token';
  static const _emailKey = 'mbn_session_email';
  static const _secureStorage = FlutterSecureStorage();

  final http.Client _client;
  final String baseUrl;
  String? token;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse(baseUrl).replace(path: path, queryParameters: query);

  Future<Map<String, dynamic>> _decode(http.Response response) async {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } catch (_) {
      throw const MbnServerException('پاسخ سرور نامعتبر است.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MbnServerException(
        data['error']?.toString() ?? 'خطا (کد ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _client
          .post(
            _uri(path),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return await _decode(response);
    } on MbnServerException {
      rethrow;
    } catch (_) {
      throw const MbnServerException('اتصال به سرور برقرار نشد.');
    }
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    try {
      final response = await _client
          .get(
            _uri(path, query),
            headers: {
              if (token != null) 'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));
      return await _decode(response);
    } on MbnServerException {
      rethrow;
    } catch (_) {
      throw const MbnServerException('اتصال به سرور برقرار نشد.');
    }
  }

  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _client
          .put(
            _uri(path),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return await _decode(response);
    } on MbnServerException {
      rethrow;
    } catch (_) {
      throw const MbnServerException('اتصال به سرور برقرار نشد.');
    }
  }

  Future<void> persistToken(String email) async {
    try {
      if (token != null) {
        await _secureStorage.write(key: _tokenKey, value: token);
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
    token = null;
    try {
      await _secureStorage.delete(key: _tokenKey);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_emailKey);
    } catch (_) {}
  }
}
