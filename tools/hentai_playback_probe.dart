// Separate QA entry point: production source adapter and production player.
// No test credentials are stored in the app or compiled into this target.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mbnime/core/theme.dart';
import 'package:mbnime/models/anime_content.dart';
import 'package:mbnime/screens/detail_screen.dart';
import 'package:mbnime/services/hentai_iran_api.dart';
import 'package:mbnime/services/device_performance.dart';

final state = ValueNotifier('idle');
AnimeContent? content;
AnimeEpisode? selected;

Future<void> load(int id) async {
  try {
    content = await HentaiIranApi().details(
      AnimeContent(
        id: '$id',
        title: 'Playback QA',
        subtitle: '',
        description: '',
        year: 0,
        rating: 0,
        kind: ContentKind.anime,
        colors: const [Colors.red, Colors.black],
        genres: const [],
        isHentai: true,
      ),
    );
    state.value = 'loaded';
  } catch (_) {
    state.value = 'source-error';
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  globalContext.setProperty('mbnProbeStage'.toJS, 'preferences'.toJS);
  await (await SharedPreferences.getInstance()).setBool(
    'player_gestures_introduced',
    true,
  );
  MediaKit.ensureInitialized();
  globalContext.setProperty('mbnProbeStage'.toJS, 'media'.toJS);
  DevicePerformance.configureWeb();
  globalContext.setProperty('mbnProbeStage'.toJS, 'hooks'.toJS);
  globalContext.setProperty(
    'mbnSourceLoad'.toJS,
    ((JSNumber id) {
      unawaited(load(id.toDartInt));
    }).toJS,
  );
  globalContext.setProperty(
    'mbnSourceOpen'.toJS,
    ((JSString quality) {
      selected = content!.seasons
          .expand((s) => s.episodes)
          .firstWhere((e) => e.name.contains(quality.toDart));
      state.value = 'playing-${quality.toDart}';
    }).toJS,
  );
  globalContext.setProperty(
    'mbnSourceState'.toJS,
    (() => jsonEncode({
      'state': state.value,
      'episodes': content?.seasons.expand((s) => s.episodes).length ?? 0,
      'media': selected?.fileUrl,
    }).toJS).toJS,
  );
  runApp(
    MaterialApp(
      theme: hentaiTheme(AnimeTheme.dark),
      home: ValueListenableBuilder(
        valueListenable: state,
        builder: (context, value, _) => selected == null
            ? Scaffold(body: Center(child: Text(value)))
            : PlayerScreen(
                key: ValueKey(value),
                content: content!,
                episode: selected!,
              ),
      ),
    ),
  );
}
