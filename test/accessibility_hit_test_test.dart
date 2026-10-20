import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mbnime/app.dart';
import 'package:mbnime/services/accessibility_service.dart';
import 'package:mbnime/services/device_performance.dart';

void main() {
  testWidgets('scaled web UI keeps the visual button hit target aligned', (
    tester,
  ) async {
    DevicePerformance.appleMobileWeb = true;
    await AccessibilityService.instance.setUiScale(.80);
    var taps = 0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(200, 200)),
          child: AccessibilityAppWrapper(
            child: Stack(
              children: [
                Positioned(
                  left: 200,
                  top: 200,
                  width: 50,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () => taps++,
                    child: const Text('tap'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // The logical button starts at 200x200 and is painted at 160x160 after
    // the 0.8 scale. A tap on its visible centre must activate it.
    await tester.tapAt(const Offset(180, 180));
    expect(taps, 1);
  });
}
