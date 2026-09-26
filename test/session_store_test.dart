import 'package:mbnime/core/session_store.dart';
import 'package:mbnime/services/animeon_api.dart';
import 'package:mbnime/services/mbn_server.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

AnimeOnApi _authenticatedApi() {
  var requestNumber = 0;
  return AnimeOnApi(
    client: MockClient((request) async {
      requestNumber++;
      if (requestNumber == 1) {
        return http.Response(
          '',
          200,
          headers: {'set-cookie': 'ci_session=first; Path=/'},
        );
      }
      if (requestNumber == 2) {
        return http.Response(
          '',
          200,
          headers: {'set-cookie': 'ci_session=active; Path=/'},
        );
      }
      return http.Response('', 200);
    }),
  );
}

MbnServerClient _server() {
  return MbnServerClient(
    baseUrl: 'https://login.test',
    client: MockClient((request) async {
      http.Response json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
      final path = request.url.path;
      if (path == '/api/auth/login') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['identifier'] == 'member@example.com' &&
            body['password'] == 'secret') {
          return json({
            'token': 'tok123',
            'user': {
              'id': 1,
              'name': '',
              'email': 'member@example.com',
              'mobile': '',
              'role': 'user',
              'is_active': true,
              'subscription_expires_at': 9999999999,
              'has_animeon_link': true,
            },
            'animeon': {'email': 'anime@example.com', 'password': 'apass'},
          });
        }
        return json({'error': 'ایمیل یا رمز عبور درست نیست.'}, 401);
      }
      final authorized = request.headers['authorization'] == 'Bearer tok123';
      if (!authorized) {
        return json({'error': 'وارد شو.'}, 401);
      }
      if (path == '/api/me') {
        return json({
          'user': {
            'id': 1,
            'name': '',
            'email': 'member@example.com',
            'mobile': '',
            'role': 'user',
            'is_active': true,
            'subscription_expires_at': 9999999999,
            'has_animeon_link': true,
          },
        });
      }
      if (path == '/api/auth/animeon-session') {
        return json({'email': 'anime@example.com', 'password': 'apass'});
      }
      if (path == '/api/config') {
        return json({'animeon_api_key': 'test-key'});
      }
      return json({'error': 'not found'}, 404);
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('login persists across restarts until explicit logout', () async {
    final firstLaunch = SessionStore(_authenticatedApi(), server: _server());
    await firstLaunch.restore();
    expect(firstLaunch.isLoggedIn, isFalse);

    await firstLaunch.login(email: 'Member@Example.com', password: 'secret');
    expect(firstLaunch.isLoggedIn, isTrue);
    expect(firstLaunch.email, 'member@example.com');

    // Simulate an app restart: a brand-new store must restore the session.
    final secondLaunch = SessionStore(_authenticatedApi(), server: _server());
    await secondLaunch.restore();
    expect(secondLaunch.isLoggedIn, isTrue);
    expect(secondLaunch.email, 'member@example.com');

    // Explicit logout wipes the session for the next launch too.
    await secondLaunch.logout();
    expect(secondLaunch.isLoggedIn, isFalse);
    final thirdLaunch = SessionStore(AnimeOnApi(), server: _server());
    await thirdLaunch.restore();
    expect(thirdLaunch.isLoggedIn, isFalse);
  });

  test('wrong server password is rejected', () async {
    final store = SessionStore(_authenticatedApi(), server: _server());
    expect(
      () => store.login(email: 'member@example.com', password: 'nope'),
      throwsA(isA<MbnServerException>()),
    );
    expect(store.isLoggedIn, isFalse);
  });

  test(
    'server-only username account logs in and restores without AnimeOn',
    () async {
      MbnServerClient server() => MbnServerClient(
        baseUrl: 'https://login.test',
        client: MockClient((request) async {
          http.Response json(Object body, [int status = 200]) => http.Response(
            jsonEncode(body),
            status,
            headers: {'content-type': 'application/json'},
          );
          switch (request.url.path) {
            case '/api/auth/login':
              expect(jsonDecode(request.body)['identifier'], 'adminuser');
              return json({
                'token': 'server-only',
                'user': {
                  'username': 'adminuser',
                  'email': '',
                  'has_animeon_link': false,
                },
              });
            case '/api/auth/status':
              return json({'state': 'active', 'message': ''});
            case '/api/me':
              return json({
                'user': {
                  'username': 'adminuser',
                  'email': '',
                  'has_animeon_link': false,
                },
              });
            case '/api/config':
              return json({'animeon_api_key': 'test-key'});
            case '/api/auth/animeon-session':
              fail('Unlinked account must not request AnimeOn credentials');
            default:
              return json({'error': 'not found'}, 404);
          }
        }),
      );
      final api = AnimeOnApi(
        client: MockClient((_) async {
          fail('Server-only login must not contact AnimeOn');
        }),
      );
      final first = SessionStore(api, server: server());
      await first.login(email: 'ADMINUSER', password: 'secret');
      expect(first.isLoggedIn, isTrue);
      expect(first.email, 'adminuser');
      expect(api.apiKey, 'test-key');

      final restoredApi = AnimeOnApi(
        client: MockClient((_) async {
          fail('Restoring an unlinked account must not contact AnimeOn');
        }),
      );
      final restored = SessionStore(restoredApi, server: server());
      await restored.restore();
      expect(restored.isLoggedIn, isTrue);
      expect(restored.email, 'adminuser');
      expect(restoredApi.apiKey, 'test-key');
    },
  );

  test('expired token logs out instead of restoring', () async {
    final authed = SessionStore(_authenticatedApi(), server: _server());
    await authed.login(email: 'member@example.com', password: 'secret');
    expect(authed.isLoggedIn, isTrue);

    final expired = MbnServerClient(
      baseUrl: 'https://login.test',
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({'error': 'وارد شو.'}),
          401,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    final relaunched = SessionStore(AnimeOnApi(), server: expired);
    await relaunched.restore();
    expect(relaunched.isLoggedIn, isFalse);
  });
}
