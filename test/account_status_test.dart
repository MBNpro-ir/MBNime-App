import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mbnime/core/session_store.dart';
import 'package:mbnime/services/animeon_api.dart';
import 'package:mbnime/services/mbn_server.dart';

void main() {
  test('trashed account status carries a forced logout reason', () async {
    final server = MbnServerClient(client: MockClient((request) async {
      expect(request.url.path, '/api/auth/status');
      expect(request.headers['Authorization'], 'Bearer example');
      return http.Response.bytes(
        utf8.encode('{"state":"deleted","message":"حساب حذف شده است."}'),
        200,
      );
    }), baseUrl: 'https://example.test')..token = 'example';
    final session = SessionStore(AnimeOnApi(), server: server);
    expect(await session.accountRestriction(), 'حساب حذف شده است.');
  });

  test('active status keeps the anime session', () async {
    final server = MbnServerClient(client: MockClient((_) async =>
      http.Response('{"state":"active","message":""}', 200)),
      baseUrl: 'https://example.test');
    final session = SessionStore(AnimeOnApi(), server: server);
    expect(await session.accountRestriction(), isNull);
  });
}
