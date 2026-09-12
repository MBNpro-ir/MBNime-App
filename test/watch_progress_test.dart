import 'package:mbnime/core/watch_progress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('watch progress round-trips and is resumable mid-episode', () async {
    final store = WatchProgressStore();
    expect(await store.load(contentId: 'c1', episodeId: 'e1'), isNull);

    await store.save(
      contentId: 'c1',
      episodeId: 'e1',
      position: const Duration(minutes: 12, seconds: 30),
      duration: const Duration(minutes: 24),
    );
    final saved = await store.load(contentId: 'c1', episodeId: 'e1');
    expect(saved, isNotNull);
    expect(saved!.position, const Duration(minutes: 12, seconds: 30));
    expect(saved.isResumable, isTrue);

    await store.clear(contentId: 'c1', episodeId: 'e1');
    expect(await store.load(contentId: 'c1', episodeId: 'e1'), isNull);
  });

  test(
    'finished episodes keep their final position and watched marker',
    () async {
      final store = WatchProgressStore();
      await store.save(
        contentId: 'c1',
        episodeId: 'e9',
        position: const Duration(minutes: 23, seconds: 55),
        duration: const Duration(minutes: 24),
      );
      final saved = await store.load(contentId: 'c1', episodeId: 'e9');
      expect(saved, isNotNull);
      expect(saved!.position, const Duration(minutes: 23, seconds: 55));
      expect(saved.watched, isTrue);
      expect(saved.isResumable, isFalse);
    },
  );

  test(
    'next episode action marks watched without losing resume time',
    () async {
      final store = WatchProgressStore();
      await store.save(
        contentId: 'c1',
        episodeId: 'e3',
        position: const Duration(minutes: 22),
        duration: const Duration(minutes: 24),
        markWatched: true,
      );
      final saved = await store.load(contentId: 'c1', episodeId: 'e3');
      expect(saved, isNotNull);
      expect(saved!.position, const Duration(minutes: 22));
      expect(saved.watched, isTrue);
      expect(saved.isResumable, isTrue);
    },
  );

  test('first seconds are not offered as resumable', () async {
    final store = WatchProgressStore();
    await store.save(
      contentId: 'c1',
      episodeId: 'e2',
      position: const Duration(seconds: 5),
      duration: const Duration(minutes: 24),
    );
    final saved = await store.load(contentId: 'c1', episodeId: 'e2');
    expect(saved, isNotNull);
    expect(saved!.isResumable, isFalse);
  });

  test('stopping in the last five minutes is almost watched', () async {
    final store = WatchProgressStore();
    await store.save(
      contentId: 'c1',
      episodeId: 'e4',
      position: const Duration(minutes: 19),
      duration: const Duration(minutes: 24),
    );
    final saved = await store.load(contentId: 'c1', episodeId: 'e4');
    expect(saved, isNotNull);
    expect(saved!.almostWatched, isTrue);
    expect(saved.watched, isFalse);
  });
}
