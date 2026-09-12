import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mbnime/screens/main_shell.dart';
import 'package:mbnime/services/animeon_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ReloadApi extends AnimeOnApi {
  final requests = <Completer<HomeCatalog>>[];
  @override
  Future<HomeCatalog> home() {
    final request = Completer<HomeCatalog>();
    requests.add(request);
    return request.future;
  }
}

void main() {
  testWidgets('home retry handles consecutive failures and then recovers', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final api = _ReloadApi();
    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          email: 'test@example.com',
          onLogout: () async {},
          api: api,
        ),
      ),
    );
    api.requests.single.completeError(
      const AnimeOnApiException('خطای آزمایشی'),
    );
    await tester.pumpAndSettle();
    expect(find.text('خطای آزمایشی'), findsOneWidget);
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(find.text('تلاش دوباره'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      api.requests.last.completeError(
        const AnimeOnApiException('خطای آزمایشی'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('تلاش دوباره'), findsOneWidget);
    }
    await tester.tap(find.text('تلاش دوباره'));
    await tester.pump();
    api.requests.last.complete(
      const HomeCatalog(featured: [], movies: [], series: [], sections: []),
    );
    await tester.pumpAndSettle();
    expect(find.text('آخرین سریال‌ها'), findsOneWidget);
    expect(find.text('تلاش دوباره'), findsNothing);
    expect(tester.takeException(), isNull);
    final refresh = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pump();
    api.requests.last.completeError(const AnimeOnApiException('قطع اتصال'));
    await refresh;
    await tester.pumpAndSettle();
    expect(find.text('قطع اتصال'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'missing API key is explicit and never sends an anonymous request',
    () async {
      var requests = 0;
      final api = AnimeOnApi(
        apiKey: '',
        client: MockClient((_) async {
          requests++;
          return http.Response('[]', 200);
        }),
      );
      await expectLater(
        api.home(),
        throwsA(
          isA<AnimeOnApiException>().having(
            (error) => error.message,
            'configuration hint',
            contains('Run-MBNime-Debug.ps1'),
          ),
        ),
      );
      expect(requests, 0);
    },
  );
}
