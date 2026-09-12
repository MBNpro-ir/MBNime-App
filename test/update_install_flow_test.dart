import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnime/services/app_updater.dart';
import 'package:mbnime/screens/update_screen.dart';

void main() {
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
