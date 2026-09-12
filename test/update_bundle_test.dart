import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnime/services/app_updater.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('mbnime-zip-test-');
  });
  tearDown(() {
    sandbox.deleteSync(recursive: true);
  });
  String bundle(List<String> names) {
    final archive = Archive();
    for (final name in names) {
      archive.addFile(ArchiveFile(name, 3, [1, 2, 3]));
    }
    final file = File(p.join(sandbox.path, 'bundle.zip'));
    file.writeAsBytesSync(ZipEncoder().encode(archive));
    return file.path;
  }

  const required = [
    'MBNime/mbnime.exe',
    'MBNime/updater.exe',
    'MBNime/flutter_windows.dll',
    'MBNime/data/icudtl.dat',
    'MBNime/data/app.so',
  ];
  test('complete Windows bundle extracts exactly under staging', () {
    AppUpdater.extractBundle((bundle(required), p.join(sandbox.path, 'stage')));
    expect(
      File(
        p.join(sandbox.path, 'stage', 'MBNime', 'data', 'app.so'),
      ).readAsBytesSync(),
      [1, 2, 3],
    );
  });
  test(
    'incomplete Windows bundle is rejected before native updater starts',
    () {
      expect(
        () => AppUpdater.extractBundle((
          bundle(required.take(2).toList()),
          p.join(sandbox.path, 'stage'),
        )),
        throwsFormatException,
      );
    },
  );
  test('ZIP traversal cannot write outside staging', () {
    expect(
      () => AppUpdater.extractBundle((
        bundle(['MBNime/../../escaped.txt']),
        p.join(sandbox.path, 'stage'),
      )),
      throwsFormatException,
    );
    expect(File(p.join(sandbox.path, 'escaped.txt')).existsSync(), isFalse);
  });
  test('case-colliding Windows filenames are rejected', () {
    expect(
      () => AppUpdater.extractBundle((
        bundle([...required, 'MBNime/MBNIME.EXE']),
        p.join(sandbox.path, 'stage'),
      )),
      throwsFormatException,
    );
  });
}
