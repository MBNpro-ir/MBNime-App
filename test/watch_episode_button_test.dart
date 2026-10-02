import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnime/core/theme.dart';
import 'package:mbnime/widgets/watch_episode_button.dart';

void main() {
  for (final adult in [false, true]) {
    testWidgets('watch accent persists during route transition adult=$adult', (
      tester,
    ) async {
      final rootTheme = ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(primary: Colors.orange),
      );
      final expected = adult ? AnimeColors.playerAccent : Colors.orange;
      await tester.pumpWidget(
        MaterialApp(
          theme: rootTheme,
          home: Scaffold(
            body: WatchEpisodeButton(
              loading: false,
              hasPlayable: true,
              desktop: false,
              adult: adult,
              pickerBuilder: (context) => Scaffold(
                body: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('close picker'),
                ),
              ),
            ),
          ),
        ),
      );
      void checkColors() {
        for (final element in find.byType(FilledButton).evaluate()) {
          expect(Theme.of(element).colorScheme.primary, expected);
        }
        expect(tester.takeException(), isNull);
      }

      checkColors();
      await tester.tap(find.text('شروع تماشا'));
      for (var frame = 0; frame < 22; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        checkColors();
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('close picker'));
      for (var frame = 0; frame < 22; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        checkColors();
      }
      await tester.pumpAndSettle();
    });
  }
}
