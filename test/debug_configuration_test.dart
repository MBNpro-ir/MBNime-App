import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android debug uses the ignored API config and a separate package', () {
    final runner = File('Run-MBNime-Android-Debug.ps1').readAsStringSync();
    final sharedRunner = File('Run-MBNime-Debug.ps1').readAsStringSync();
    final gitignore = File('.gitignore').readAsStringSync();
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(runner, contains("'.signing/api-config.json'"));
    expect(runner, contains("'Run-MBNime-Debug.ps1'"));
    expect(sharedRunner, contains('--dart-define-from-file='));
    expect(gitignore, contains('/.signing/'));
    expect(gradle, contains('applicationIdSuffix = ".debug"'));
    expect(gradle, contains('manifestPlaceholders["appLabel"]'));
    expect(manifest, contains(r'android:label="${appLabel}"'));
  });
}
