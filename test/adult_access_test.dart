import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mbnime/services/adult_access.dart';
import 'package:mbnime/services/hentai_iran_api.dart';
import 'package:mbnime/services/network_gate.dart';
import 'package:mbnime/widgets/adult_access_gate.dart';

void main() {
  tearDown(() {
    AdultAccess.instance.bind(null, '');
    OfflineMode.leave();
  });

  test(
    'default deny; boolean grant, revoke, outage and account change',
    () async {
      Object allowed = false;
      final service = AdultAccess(
        client: MockClient((r) async {
          if (allowed == 'offline') throw http.ClientException('offline');
          return http.Response(jsonEncode({'allowed': allowed}), 200);
        }),
      );
      addTearDown(service.dispose);
      expect(service.allowed, isFalse);
      service.bind('a', 'https://account.test');
      await Future<void>.delayed(Duration.zero);
      expect(service.allowed, isFalse);
      allowed = true;
      await service.refresh();
      expect(service.allowed, isTrue);
      allowed = 'true';
      await service.refresh();
      expect(service.allowed, isFalse);
      allowed = true;
      await service.refresh();
      allowed = 'offline';
      await service.refresh();
      expect(service.allowed, isFalse);
      service.observe('a', true);
      OfflineMode.enter();
      expect(service.allowed, isFalse);
      OfflineMode.leave();
      service.bind('b', 'https://account.test');
      expect(service.allowed, isFalse);
      service.observe('a', true);
      expect(service.allowed, isFalse);
    },
  );

  test(
    'a delayed grant cannot undo SSE revocation or cross account boundaries',
    () async {
      var pending = Completer<http.Response>();
      final service = AdultAccess(client: MockClient((_) => pending.future));
      addTearDown(service.dispose);
      service.bind('a', 'https://account.test');
      service.observe('a', false);
      pending.complete(http.Response('{"allowed":true}', 200));
      await Future<void>.delayed(Duration.zero);
      expect(service.allowed, isFalse);
      pending = Completer<http.Response>();
      unawaited(service.refresh());
      service.bind('b', 'https://account.test');
      service.observe('b', false);
      pending.complete(http.Response('{"allowed":true}', 200));
      await Future<void>.delayed(Duration.zero);
      expect(service.allowed, isFalse);
    },
  );

  test('permission expires without a fresh confirmation', () async {
    final service = AdultAccess(
      client: MockClient((_) async => http.Response('{"allowed":true}', 200)),
      lease: const Duration(milliseconds: 20),
      interval: const Duration(seconds: 10),
    );
    addTearDown(service.dispose);
    service.bind('a', 'https://account.test');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(service.allowed, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(service.allowed, isFalse);
  });

  test(
    'unauthorized catalogue calls fail before network or local fallback',
    () async {
      var calls = 0;
      final api = HentaiIranApi(
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      expect(api.latest(), throwsStateError);
      expect(calls, 0);
    },
  );

  testWidgets(
    'revoke unmounts sensitive content and closes an overlaid sheet',
    (tester) async {
      AdultAccess.instance.bind('test', 'https://account.test');
      AdultAccess.instance.observe('test', true);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => AdultAccessGate(
                      builder: (context) => Scaffold(
                        body: TextButton(
                          onPressed: () => showModalBottomSheet<void>(
                            context: context,
                            builder: (_) => const Text('private episode'),
                          ),
                          child: const Text('private catalogue'),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('private catalogue'));
      await tester.pumpAndSettle();
      expect(find.text('private episode'), findsOneWidget);
      AdultAccess.instance.observe('test', false);
      await tester.pumpAndSettle();
      expect(find.text('private episode'), findsNothing);
      expect(find.text('private catalogue'), findsNothing);
      expect(find.text('open'), findsOneWidget);
      AdultAccess.instance.bind(null, '');
    },
  );
}
