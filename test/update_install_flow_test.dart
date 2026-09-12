import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnime/services/app_updater.dart';
import 'package:mbnime/screens/update_screen.dart';

void main() {
  for (final size in const [Size(320, 568), Size(390, 844), Size(1440, 900)]) {
    testWidgets('update screen is responsive at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: UpdateScreen()));
      await tester.pumpAndSettle();
      expect(find.text('به‌روزرسانی برنامه'), findsOneWidget);
      expect(find.text('وضعیت به‌روزرسانی'), findsOneWidget);
      expect(find.text('بررسی دوباره'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test(
    'fresh Windows cache reproduces old failure and creates unique stages',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mbnime-stage-regression-',
      );
      try {
        await expectLater(
          Directory('${root.path}/stage-').createTemp(),
          throwsA(isA<FileSystemException>()),
        );
        final first = await AppUpdater.createInstallStage(root);
        final second = await AppUpdater.createInstallStage(root);
        expect(await first.exists(), isTrue);
        expect(first.parent.path, root.path);
        expect(first.path, isNot(second.path));
        await first.delete();
        await second.delete();
      } finally {
        await root.delete();
      }
    },
  );

  for (final choice in ['درخواست دوباره', 'دانلود از گیت‌هاب', 'بعداً']) {
    testWidgets('denied install permission offers $choice', (tester) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showInstallPermissionPrompt(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('اجازهٔ نصب لازم است'), findsOneWidget);
      await tester.tap(find.text(choice));
      await tester.pumpAndSettle();
      expect(
        selected,
        choice == 'درخواست دوباره'
            ? 'retry'
            : choice == 'دانلود از گیت‌هاب'
            ? 'github'
            : null,
      );
    });
  }
}
