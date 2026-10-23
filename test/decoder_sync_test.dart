import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mbnime/services/mbn_server.dart';
import 'package:mbnime/services/mbn_sync.dart';
import 'package:mbnime/core/video_decode_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => MbnSync.instance.clear());
  for (final remote in ['software', 'hardware', 'invalid', true, 1]) {
    test('decoder remote preference validates $remote', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(VideoDecodeMode.preferenceKey, 'software');
      final server = MbnServerClient(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'preferences': {
                'payload': {
                  'windows': {'player_decoder_mode': remote},
                },
                'updated_at': 5000,
              },
            }),
            200,
          ),
        ),
      )..token = 'tok';
      MbnSync.instance.configure(server: server);
      expect(
        await MbnSync.instance.pullAndApplyPreferences(force: true),
        isTrue,
      );
      expect(
        prefs.getString(VideoDecodeMode.preferenceKey),
        remote == 'hardware' ? 'hardware' : 'software',
      );
    });
  }
}
