import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnime/core/theme.dart';
import 'package:mbnime/widgets/player_keyboard.dart';
import 'package:mbnime/widgets/player_timeline.dart';

void main() {
  testWidgets(
    'Persian player: right advances ten seconds and timeline increases to right',
    (tester) async {
      var position = const Duration(seconds: 30);
      const duration = Duration(seconds: 100);
      await tester.pumpWidget(
        MaterialApp(
          theme: AnimeTheme.dark,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: StatefulBuilder(
                builder: (context, update) => PlayerKeyboard(
                  onCommand: (command) => update(() {
                    if (command == PlayerCommand.forward ||
                        command == PlayerCommand.back) {
                      position = playerSeekTarget(
                        position,
                        duration,
                        command == PlayerCommand.forward ? 10 : -10,
                      );
                    }
                  }),
                  onFocus: () {},
                  onSeekFraction: (_) {},
                  child: Center(
                    child: SizedBox(
                      width: 340,
                      child: PlayerTimeline(
                        position: position,
                        duration: duration,
                        buffer: const Duration(seconds: 80),
                        onSeek: (value) => update(() => position = value),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final slider = find.byType(Slider);
      expect(Directionality.of(tester.element(slider)), TextDirection.ltr);
      expect(SliderTheme.of(tester.element(slider)).trackGap, 6);
      expect(
        tester.getCenter(find.text('00:30')).dx,
        lessThan(tester.getCenter(find.text('01:40')).dx),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(position, const Duration(seconds: 40));
      expect(tester.widget<Slider>(slider).value, .4);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(position, const Duration(seconds: 30));
      final rect = tester.getRect(slider);
      await tester.tapAt(Offset(rect.left + rect.width * .8, rect.center.dy));
      await tester.pumpAndSettle();
      expect(position.inSeconds, greaterThan(65));
      final before = position;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(position, before + const Duration(seconds: 10));
      expect(tester.takeException(), isNull);
    },
  );
  test('seek clamps at start and end without reversing direction', () {
    expect(
      playerSeekTarget(
        const Duration(seconds: 5),
        const Duration(seconds: 100),
        -10,
      ),
      Duration.zero,
    );
    expect(
      playerSeekTarget(
        const Duration(seconds: 95),
        const Duration(seconds: 100),
        10,
      ),
      const Duration(seconds: 100),
    );
  });
}
