import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnime/models/anime_content.dart';
import 'package:mbnime/screens/episode_picker_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mbnime/widgets/smart_cast_sheet.dart';

const content = AnimeContent(
  id: 'test',
  title: 'عنوان آزمایشی',
  subtitle: '',
  description: '',
  year: 2026,
  rating: 8,
  kind: ContentKind.series,
  colors: [Colors.blue],
  genres: [],
  seasons: [
    AnimeSeason(
      id: 'season1',
      name: 'فصل اول 720p',
      episodes: [
        AnimeEpisode(
          id: '1',
          name: 'قسمت اول',
          fileUrl: 'https://example.com/1.mkv',
          fileType: 'mkv',
          fileSize: '345',
        ),
        AnimeEpisode(
          id: '2',
          name: 'قسمت دوم',
          fileUrl: 'https://example.com/2.mkv',
          fileType: 'mkv',
          fileSize: '345',
        ),
      ],
    ),
  ],
);

void main() {
  testWidgets('first TV destination page has working visible back control', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showSmartCastSheet(
                context,
                content: content,
                episode: content.seasons.first.episodes.first,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('بازگشت'), findsOneWidget);
    await tester.tap(find.text('بازگشت'));
    await tester.pumpAndSettle();
    expect(find.text('نوع تلویزیون را انتخاب کن'), findsNothing);
  });
  for (final size in [const Size(390, 844), const Size(1024, 768)]) {
    testWidgets('episode grid and destination menu at $size', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: EpisodePickerScreen(
              content: content,
              onPlay: (_, _) async {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(find.byType(GridView), findsOneWidget);
      expect(find.text('پخش'), findsNWidgets(2));
      expect(find.text('دانلود'), findsNWidgets(2));
      final first = tester.getCenter(find.text('قسمت اول'));
      final second = tester.getCenter(find.text('قسمت دوم'));
      expect(first.dy, second.dy);
      await tester.tap(find.text('پخش').first);
      await tester.pumpAndSettle();
      expect(find.text('پلیر داخلی (پیشنهادی)'), findsOneWidget);
      expect(find.text('پلیرهای خارجی'), findsOneWidget);
      expect(find.text('تلویزیون یا مانیتور بدون سیم'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('large text falls back to readable single-column cards', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: EpisodePickerScreen(content: content, onPlay: (_, _) async {}),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
