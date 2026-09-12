import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/animeon_api.dart';

/// Persists the login session so the user stays signed in across restarts.
///
/// Signed-in state = a stored account email. The server cookie is restored
/// opportunistically. Only an explicit [logout] clears the stored session.
class SessionStore {
  SessionStore(this.api);

  static const _emailKey = 'animeon_secure_email';
  static const _cookieKey = 'animeon_secure_session';
  static const _legacyEmailKey = 'animeon_session_email';
  static const _secureStorage = FlutterSecureStorage();

  final AnimeOnApi api;
  String? email;

  bool get isLoggedIn => email != null && email!.isNotEmpty;

  /// Restores a previously saved session. Never throws: a storage failure
  /// (e.g. a corrupt file) simply means "not logged in".
  Future<void> restore() async {
    final restoredEmail = await _readKey(_emailKey);
    if (restoredEmail != null) {
      email = restoredEmail;
      final cookie = await _readKey(_cookieKey);
      if (cookie != null) {
        api.restoreCookie(cookie);
      }
    } else {
      email = null;
    }

    // Remove the local-only preview session from earlier builds.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_legacyEmailKey);
    } catch (_) {
      // Best effort only; a prefs failure must not affect the session.
    }
  }

  Future<void> login({required String email, required String password}) async {
    final normalizedEmail = email.trim().toLowerCase();
    final success = await api.login(email: normalizedEmail, password: password);
    if (!success || api.sessionCookie == null) {
      throw const AnimeOnApiException('ایمیل یا رمز عبور درست نیست.');
    }
    await _persist(normalizedEmail);
  }

  Future<void> register({
    required String name,
    required String email,
    required String mobile,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final success = await api.register(
      name: name,
      email: normalizedEmail,
      mobile: mobile,
      password: password,
    );
    if (!success || api.sessionCookie == null) {
      throw const AnimeOnApiException(
        'ثبت‌نام انجام نشد؛ ممکن است ایمیل قبلاً استفاده شده باشد.',
      );
    }
    await _persist(normalizedEmail);
  }

  /// Imports an opaque session code instead of embedding an account password
  /// in the application. The official server validates the included session
  /// before it is persisted locally.
  Future<void> loginWithCode(String code) async {
    final decoded = _decodeLoginCode(code);
    api.restoreCookie(decoded.cookie);
    if (!await api.validateCurrentSession()) {
      api.clearSession();
      throw const AnimeOnApiException('کد ورود نامعتبر یا منقضی شده است.');
    }
    await _persist(decoded.email);
  }

  String createLoginCode() {
    final currentEmail = email;
    final cookie = api.sessionCookie;
    if (currentEmail == null || cookie == null) {
      throw const AnimeOnApiException('ابتدا باید وارد حساب شوید.');
    }
    final payload = utf8.encode(
      jsonEncode({'v': 1, 'e': currentEmail, 's': cookie}),
    );
    return 'MBN1.${base64Url.encode(payload).replaceAll('=', '')}';
  }

  Future<void> _persist(String normalizedEmail) async {
    // Persist BEFORE exposing the session: if device storage fails we must
    // not let the user in for this run only to sign them out on restart.
    try {
      await _secureStorage.write(key: _emailKey, value: normalizedEmail);
      await _secureStorage.write(key: _cookieKey, value: api.sessionCookie);
      final roundTrip = await _secureStorage.read(key: _emailKey);
      if (roundTrip != normalizedEmail) {
        throw const AnimeOnApiException('ذخیره نشست ناموفق بود.');
      }
    } on AnimeOnApiException {
      rethrow;
    } catch (_) {
      throw const AnimeOnApiException('نشست ورود ذخیره نشد؛ دوباره تلاش کن.');
    }
    email = normalizedEmail;
  }

  static _LoginCode _decodeLoginCode(String raw) {
    try {
      final text = raw.trim();
      if (!text.startsWith('MBN1.')) throw const FormatException();
      final encoded = text.substring(5);
      final padded = encoded.padRight(
        encoded.length + ((4 - encoded.length % 4) % 4),
        '=',
      );
      final data = jsonDecode(utf8.decode(base64Url.decode(padded)));
      if (data is! Map<String, dynamic> || data['v'] != 1) {
        throw const FormatException();
      }
      final email = data['e']?.toString().trim().toLowerCase() ?? '';
      final cookie = data['s']?.toString().trim() ?? '';
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email) ||
          !RegExp(r'^ci_session=[^;\s]+$').hasMatch(cookie)) {
        throw const FormatException();
      }
      return _LoginCode(email, cookie);
    } catch (_) {
      throw const AnimeOnApiException('فرمت کد ورود درست نیست.');
    }
  }

  /// Signs out and wipes the stored session. Memory is always cleared, even
  /// if a storage delete fails.
  Future<void> logout() async {
    try {
      await _secureStorage.delete(key: _emailKey);
    } catch (_) {
      // Best effort; memory is cleared below regardless.
    }
    try {
      await _secureStorage.delete(key: _cookieKey);
    } catch (_) {
      // Best effort; memory is cleared below regardless.
    }
    api.clearSession();
    email = null;
  }

  Future<String?> _readKey(String key) async {
    try {
      final value = await _secureStorage.read(key: key);
      return (value == null || value.isEmpty) ? null : value;
    } catch (_) {
      return null;
    }
  }
}

class _LoginCode {
  const _LoginCode(this.email, this.cookie);
  final String email;
  final String cookie;
}
