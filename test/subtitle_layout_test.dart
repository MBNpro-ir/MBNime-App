import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnime/core/subtitle_layout.dart';

void main() {
  test('normal player keeps the exact subtitle preferences', () {
    final layout = SubtitleLayout.resolve(
      viewport: const Size(1280, 720),
      isPictureInPicture: false,
      preferredFontSize: 52,
      preferredBottomPadding: 180,
      preferredCornerRadius: 24,
    );

    expect(layout.fontSize, 52);
    expect(layout.bottomPadding, 180);
    expect(layout.cornerRadius, 24);
  });

  test(
    'small PiP bounds keep extreme subtitle settings readable and bounded',
    () {
      final layout = SubtitleLayout.resolve(
        viewport: const Size(240, 135),
        isPictureInPicture: true,
        preferredFontSize: 52,
        preferredBottomPadding: 180,
        preferredCornerRadius: 24,
      );

      expect(layout.fontSize, inInclusiveRange(9, 22));
      expect(layout.bottomPadding, lessThanOrEqualTo(135 * .24));
      expect(layout.horizontalInset, lessThan(28));
    },
  );

  test('resizing PiP scales subtitles without changing saved preference', () {
    SubtitleLayout at(Size size) => SubtitleLayout.resolve(
      viewport: size,
      isPictureInPicture: true,
      preferredFontSize: 28,
      preferredBottomPadding: 54,
      preferredCornerRadius: 10,
    );

    final compact = at(const Size(240, 135));
    final expanded = at(const Size(480, 270));

    expect(expanded.fontSize, greaterThan(compact.fontSize));
    expect(expanded.bottomPadding, greaterThan(compact.bottomPadding));
    expect(expanded.fontSize, lessThanOrEqualTo(28));
  });
}
