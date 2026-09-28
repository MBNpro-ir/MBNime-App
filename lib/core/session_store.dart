import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/animeon_api.dart';
import '../services/mbn_server.dart';

/// Server-backed login session (https://login.a.mbnpro.ir).
///
/// Flow: the account server verifies the password (or 10-minute temp code)
/// and the subscription. A linked AnimeOn account can also restore its web
/// session; the MBN account and catalog do not require that optional link.
class SessionStore {
  SessionStore(this.api, {MbnServerClient? server})
    : server = server ?? MbnServerClient();

  static const _emailKey = 'mbn_session_email_display';
  static const _signedOutKey = 'mbn_signed_out';
  static const _apiKeyKey = 'mbn_animeon_api_key';
  static const _secureStorage = FlutterSecureStorage();

  final AnimeOnApi api;
  final MbnServerClient server;
  String? email;
  int? userId;
  String? forcedLogoutMessage;

  bool get isLoggedIn => email != null && email!.isNotEmpty;

  /// Restores a previously saved session. Never throws.
  ///
  /// A valid server token re-establishes the AnimeOn web session silently.
  /// A 401/403 means the account lapsed: the session is cleared. A plain
  /// network failure keeps the last known email so an offline launch still
  /// opens the library instead of bricking on the login screen.
  Future<void> restore() async {
    forcedLogoutMessage = null;
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      prefs = null;
    }
    final cachedKey = prefs?.getString(_apiKeyKey);
    if (cachedKey != null && cachedKey.trim().isNotEmpty) {
      api.apiKey = cachedKey.trim();
    }
    if ((prefs?.getBool(_signedOutKey) ?? false)) {
      email = null;
      api.clearSession();
      return;
    }
    final storedToken = await server.readToken();
    if (storedToken == null || storedToken.isEmpty) {
      email = null;
      api.clearSession();
      return;
    }
    server.token = storedToken;
    try {
      final status = await server.getJson('/api/auth/status');
      if (status['state'] != 'active') {
        forcedLogoutMessage =
            status['message']?.toString() ?? 'حساب شما در دسترس نیست.';
        await logout();
        return;
      }
      final me = await server.getJson('/api/me');
      final user = (me['user'] as Map?)?.cast<String, dynamic>() ?? {};
      userId = (user['id'] as num?)?.toInt();
      try {
        final config = await server.getJson('/api/config');
        final key = config['animeon_api_key']?.toString() ?? '';
        if (key.isNotEmpty) {
          api.apiKey = key;
          final instance = prefs ?? await SharedPreferences.getInstance();
          await instance.setString(_apiKeyKey, key);
        }
      } catch (_) {}
      if (user['has_animeon_link'] == true) {
        try {
          final session = await server.getJson('/api/auth/animeon-session');
          final animeEmail = session['email']?.toString() ?? '';
          final animePass = session['password']?.toString() ?? '';
          if (animeEmail.isNotEmpty &&
              animePass.isNotEmpty &&
              !await api.login(email: animeEmail, password: animePass)) {
            api.clearSession();
          }
        } catch (_) {
          api.clearSession();
        }
      } else {
        api.clearSession();
      }
      final accountEmail = user['email']?.toString() ?? '';
      final username = user['username']?.toString() ?? '';
      email = accountEmail.isNotEmpty
          ? accountEmail
          : username.isNotEmpty
          ? username
          : await server.readEmail();
      try {
        final instance = prefs ?? await SharedPreferences.getInstance();
        await instance.remove(_signedOutKey);
        if (email != null) {
          await instance.setString(_emailKey, email!);
        }
      } catch (_) {}
    } on MbnServerException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        forcedLogoutMessage = 'نشست شما پایان یافته است؛ دوباره وارد شوید.';
        await logout();
      } else {
        // Offline: keep the last known account visible.
        email = await server.readEmail();
        if (email == null || email!.isEmpty) {
          api.clearSession();
        }
      }
    } catch (_) {
      email = await server.readEmail();
      if (email == null || email!.isEmpty) {
        api.clearSession();
      }
    }
  }

  Future<String?> accountRestriction() async {
    final status = await server.getJson('/api/auth/status');
    return status['state'] == 'active'
        ? null
        : (status['message']?.toString() ?? 'حساب شما در دسترس نیست.');
  }

  Future<void> login({required String email, required String password}) async {
    final data = await server.postJson('/api/auth/login', {
      'identifier': email.trim().toLowerCase(),
      'password': password,
      'app': 'anime',
    });
    await loginWithHandoff(data, fallbackIdentifier: email);
  }

  Future<void> loginWithToken(String authToken) async {
    final prevToken = server.token;
    server.token = authToken;
    try {
      // 1. Attempt token exchange for dedicated anime session
      Map<String, dynamic>? exchangeData;
      try {
        exchangeData = await server.postJson('/api/auth/exchange', {
          'target_app': 'anime',
        });
      } catch (_) {}

      if (exchangeData != null && exchangeData['token'] != null) {
        final newToken = exchangeData['token'].toString();
        server.token = newToken;
        await loginWithHandoff(
          exchangeData,
          fallbackIdentifier: email ?? 'کاربر',
        );
        return;
      }

      // Fallback if server is older:
      final userResp = await server.getJson('/api/me');
      final user = (userResp['user'] as Map?)?.cast<String, dynamic>() ?? {};
      userId = (user['id'] as num?)?.toInt();
      final accountEmail = user['email']?.toString() ?? '';
      final username = user['username']?.toString() ?? '';
      email = accountEmail.isNotEmpty
          ? accountEmail
          : username.isNotEmpty
          ? username
          : 'کاربر';
      await server.persistToken(email!);
      try {
        final config = await server.getJson('/api/config');
        final key = config['animeon_api_key']?.toString() ?? '';
        if (key.isNotEmpty) {
          api.apiKey = key;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_apiKeyKey, key);
        }
      } catch (_) {}
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_signedOutKey);
      } catch (_) {}
    } catch (_) {
      server.token = prevToken;
      rethrow;
    }
  }

  Future<void> loginWithHandoff(
    Map<String, dynamic> data, {
    required String fallbackIdentifier,
  }) async {
    final token = data['token']?.toString() ?? '';
    if (token.isEmpty) {
      throw const MbnServerException('توکن ورود دریافت نشد.');
    }
    server.token = token;
    final animeon = (data['animeon'] as Map?)?.cast<String, dynamic>() ?? {};
    final animeEmail = animeon['email']?.toString() ?? '';
    final animePass = animeon['password']?.toString() ?? '';
    if (animeEmail.isNotEmpty && animePass.isNotEmpty) {
      try {
        if (!await api.login(email: animeEmail, password: animePass)) {
          api.clearSession();
        }
      } catch (_) {
        api.clearSession();
      }
    } else {
      api.clearSession();
    }
    final apiKeyFromData = data['animeon_api_key']?.toString() ?? '';
    if (apiKeyFromData.isNotEmpty) {
      api.apiKey = apiKeyFromData;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_apiKeyKey, apiKeyFromData);
      } catch (_) {}
    } else {
      try {
        final config = await server.getJson('/api/config');
        final key = config['animeon_api_key']?.toString() ?? '';
        if (key.isNotEmpty) {
          api.apiKey = key;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_apiKeyKey, key);
        }
      } catch (_) {}
    }
    final user = (data['user'] as Map?)?.cast<String, dynamic>() ?? {};
    userId = (user['id'] as num?)?.toInt();
    final accountEmail = user['email']?.toString() ?? '';
    final username = user['username']?.toString() ?? '';
    email = accountEmail.isNotEmpty
        ? accountEmail
        : username.isNotEmpty
        ? username
        : fallbackIdentifier.trim().toLowerCase();
    await server.persistToken(email!);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_signedOutKey);
    } catch (_) {}
  }

  /// Kept for a future public signup; the UI stays hidden for now.
  Future<void> register({
    required String name,
    required String email,
    required String mobile,
    required String password,
  }) async {
    final data = await server.postJson('/api/auth/register', {
      'name': name.trim(),
      'email': email.trim().toLowerCase(),
      'mobile': mobile.trim(),
      'password': password,
      'app': 'anime',
    });
    final user = (data['user'] as Map?)?.cast<String, dynamic>() ?? {};
    if ((user['email']?.toString() ?? '').isEmpty) {
      throw const MbnServerException('ثبت‌نام انجام نشد.');
    }
  }

  /// Signs out and wipes the stored session. Memory is always cleared, even
  /// if a storage delete fails. A durable signed-out marker is written first
  /// so a failed delete can never silently restore the previous account on
  /// the next launch.
  Future<void> logout() async {
    Object? failure;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_signedOutKey, true);
    } catch (e) {
      failure = e;
    }
    try {
      await server.clearToken();
    } catch (e) {
      failure ??= e;
    }
    try {
      await _secureStorage.delete(key: _emailKey);
    } catch (e) {
      failure ??= e;
    }
    api.clearSession();
    email = null;
    userId = null;
    if (failure != null) {
      final leftover = await server.readToken();
      if (leftover != null) {
        throw const MbnServerException(
          'خروج انجام شد اما پاک‌سازی کامل نشد؛ یک‌بار دیگر خروج را بزن.',
        );
      }
    }
  }
}
