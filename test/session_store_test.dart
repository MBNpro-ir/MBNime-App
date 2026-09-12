import 'package:mbnime/core/session_store.dart';
import 'package:mbnime/services/animeon_api.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('login persists across restarts until explicit logout', () async {
    final firstLaunch = SessionStore(_authenticatedApi());
    await firstLaunch.restore();
    expect(firstLaunch.isLoggedIn, isFalse);

    await firstLaunch.login(email: 'Member@Example.com', password: 'secret');
    expect(firstLaunch.isLoggedIn, isTrue);
    expect(firstLaunch.email, 'member@example.com');

    // Simulate an app restart: a brand-new store must restore the session.
    final secondLaunch = SessionStore(AnimeOnApi());
    await secondLaunch.restore();
    expect(secondLaunch.isLoggedIn, isTrue);
    expect(secondLaunch.email, 'member@example.com');

    // Explicit logout wipes the session for the next launch too.
    await secondLaunch.logout();
    expect(secondLaunch.isLoggedIn, isFalse);
    final thirdLaunch = SessionStore(AnimeOnApi());
    await thirdLaunch.restore();
    expect(thirdLaunch.isLoggedIn, isFalse);
  });

  test(
    'login code imports only after server-side session validation',
    () async {
      final source = SessionStore(_authenticatedApi());
      await source.login(email: 'member@example.com', password: 'secret');
      final code = source.createLoginCode();
      expect(code, startsWith('MBN1.'));
      await source.logout();

      final targetApi = AnimeOnApi(
        client: MockClient((request) async {
          expect(request.headers['cookie'], 'ci_session=active');
          return http.Response('', 200);
        }),
      );
      final target = SessionStore(targetApi);
      await target.loginWithCode(code);

      expect(target.isLoggedIn, isTrue);
      expect(target.email, 'member@example.com');
    },
  );

  test('malformed login code is rejected before a network request', () async {
    final store = SessionStore(AnimeOnApi());
    expect(
      () => store.loginWithCode('not-a-login-code'),
      throwsA(isA<AnimeOnApiException>()),
    );
  });
}
