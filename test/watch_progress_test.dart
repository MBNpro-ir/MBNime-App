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

  test('finished episodes are forgotten automatically', () async {
    final store = WatchProgressStore();
    await store.save(
      contentId: 'c1',
      episodeId: 'e9',
      position: const Duration(minutes: 23, seconds: 55),
      duration: const Duration(minutes: 24),
    );
    expect(await store.load(contentId: 'c1', episodeId: 'e9'), isNull);
  });

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
}
