import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnime/core/download_bundles.dart';
import 'package:mbnime/screens/download_manager_screen.dart';
import 'package:mbnime/services/download_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

TaskRecord record(
  String taskId,
  String displayName, {
  Map<String, String> meta = const {},
  TaskStatus status = TaskStatus.enqueued,
  double progress = 0,
}) {
  final task = DownloadTask(
    url: 'https://example.org/$taskId.mkv',
    filename: '$taskId.mkv',
    directory: '/tmp',
    baseDirectory: BaseDirectory.root,
    displayName: displayName,
    metaData: jsonEncode(meta),
  );
  return TaskRecord(task, status, progress, 1000);
}

void main() {
  test('tasks with the same bundleId form one bundle', () {
    final bundles = groupDownloadRecords([
      record('a1', 'فیلم · 1080p', meta: {
        'title': 'فیلم',
        'season': 'کیفیت‌های پخش · 1080p',
        'bundleId': 'b1',
      }, status: TaskStatus.complete, progress: 1),
      record('a2', 'فیلم · 720p', meta: {
        'title': 'فیلم',
        'season': 'کیفیت‌های پخش · 720p',
        'bundleId': 'b1',
      }, progress: .5),
      record('solo', 'سریال · قسمت 1', meta: {'title': 'سریال'}),
    ]);

    expect(bundles, hasLength(2));
    final bundle = bundles.firstWhere((item) => !item.isSingle);
    expect(bundle.records, hasLength(2));
    expect(bundle.completeCount, 1);
    expect(bundle.progress, closeTo(.75, .001));
    expect(bundle.subtitle, contains('2 فایل'));
    expect(
      bundles.where((item) => item.isSingle).single.records.single.task
          .displayName,
      'سریال · قسمت 1',
    );
  });

  testWidgets('bundle of two files shows as one expandable group', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final manager = DownloadManager.instance;
    manager.records['x1'] = record('x1', 'فیلم · 1080p', meta: {
      'title': 'فیلم',
      'season': 'کیفیت‌های پخش',
      'bundleId': 'bundle-x',
    });
    manager.records['x2'] = record('x2', 'فیلم · 720p', meta: {
      'title': 'فیلم',
      'season': 'کیفیت‌های پخش',
      'bundleId': 'bundle-x',
    });
    addTearDown(manager.records.clear);
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: DownloadManagerScreen(initializeDownloads: _noop),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('1 باندل · 2 فایل'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byType(ExpansionTile),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(ExpansionTile), findsOneWidget);
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('فیلم · 720p'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('فیلم · 1080p'), findsWidgets);
    expect(find.text('فیلم · 720p'), findsWidgets);
    // یکی در پنل کنترل کلی، یکی در اکشن‌های باندل.
    expect(find.text('ادامه همه'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _noop() async {}
