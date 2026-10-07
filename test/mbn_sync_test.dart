import 'dart:convert';
import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mbnime/core/library_store.dart';
import 'package:mbnime/services/mbn_server.dart';
import 'package:mbnime/services/mbn_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'rapid sync changes coalesce and the last write contains the latest preferences',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final bodies = <String>[];
      final server = MbnServerClient(
        client: MockClient((request) async {
          bodies.add(request.body);
          if (bodies.length == 1) {
            started.complete();
            await release.future;
          }
          final data = jsonDecode(request.body)['data'] as Map;
          return http.Response(
            jsonEncode({
              for (final entry in data.entries)
                entry.key: {'payload': entry.value, 'updated_at': 2000},
            }),
            200,
          );
        }),
      )..token = 'tok';
      MbnSync.instance.configure(server: server);
      try {
        final first = MbnSync.instance.pushAll();
        await started.future;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('player_rate', 1.75);
        final pending = List.generate(20, (_) => MbnSync.instance.pushAll());
        release.complete();
        await Future.wait([first, ...pending]);
        expect(bodies.length, 2);
        expect(bodies.last, contains('"player_rate":1.75'));
      } finally {
        if (!release.isCompleted) release.complete();
        MbnSync.instance.clear();
      }
    },
  );

  test('sync pulls newer server rows into the local library', () async {
    var serverState = {
      'favorites': {'payload': [], 'updated_at': 0},
      'playlists': {'payload': [], 'updated_at': 0},
      'history': {'payload': [], 'updated_at': 0},
      'progress': {'payload': {}, 'updated_at': 0},
    };
    final server = MbnServerClient(
      baseUrl: 'https://login.test',
      client: MockClient((request) async {
        http.Response json(Object body, [int status = 200]) => http.Response(
          jsonEncode(body),
          status,
          headers: {'content-type': 'application/json'},
        );
        if (request.url.path == '/api/sync') {
          return json(serverState);
        }
        return json({'error': 'x'}, 404);
      }),
    );
    server.token = 'tok';
    MbnSync.instance.configure(server: server);

    serverState = {
      'favorites': {
        'payload': [
          {
            'id': 'srv-1',
            'title': 'سروری',
            'subtitle': '',
            'description': '',
            'year': 2024,
            'rating': 7.0,
            'kind': 'anime',
            'colors': [4278190080, 4278190080],
            'genres': [],
          },
        ],
        'updated_at': 2000,
      },
      'playlists': {'payload': [], 'updated_at': 0},
      'history': {'payload': [], 'updated_at': 0},
      'progress': {'payload': {}, 'updated_at': 0},
    };
    await MbnSync.instance.syncAll();
    final favorites = await LibraryStore().favorites();
    expect(favorites.map((item) => item.id), contains('srv-1'));
    MbnSync.instance.clear();
  });

  test(
    'pullAndApplyPreferences restores cross-platform preferences with correct types',
    () async {
      final serverState = {
        'preferences': {
          'payload': {
            'windows': {
              'player_volume': 90,
              'player_rate': 1.5,
              'sub_font': 'Vazirmatn',
              'sub_size': 26,
              'sub_color': 4294967295,
              'access_text_scale': 1.1,
              'access_reduce_motion': true,
            },
          },
          'updated_at': 5000,
        },
      };
      final server = MbnServerClient(
        baseUrl: 'https://login.test',
        client: MockClient((request) async {
          http.Response json(Object body, [int status = 200]) => http.Response(
            jsonEncode(body),
            status,
            headers: {'content-type': 'application/json'},
          );
          if (request.url.path == '/api/sync') {
            return json(serverState);
          }
          return json({'error': 'x'}, 404);
        }),
      );
      server.token = 'tok';
      MbnSync.instance.configure(server: server);

      final success = await MbnSync.instance.pullAndApplyPreferences(
        force: true,
      );
      expect(success, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('player_volume'), 90.0);
      expect(prefs.getDouble('player_rate'), 1.5);
      expect(prefs.getDouble('sub_size'), 26.0);
      expect(prefs.getString('sub_font'), 'Vazirmatn');
      expect(prefs.getInt('sub_color'), 4294967295);
      expect(prefs.getBool('access_reduce_motion'), isTrue);

      MbnSync.instance.clear();
    },
  );
}
