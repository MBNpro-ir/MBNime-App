import 'package:flutter_test/flutter_test.dart';
import 'package:mbnime/services/app_links.dart';

void main() {
  test('registry key is namespaced per app', () {
    expect(AppLinks.registryKey('MBNMovie'), r'HKCU\Software\MBN\Apps\MBNMovie');
    expect(AppLinks.registryKey('MBNime'), r'HKCU\Software\MBN\Apps\MBNime');
  });

  test('reg query output parses REG_SZ values', () {
    const output = '\r\nHKEY_CURRENT_USER\\Software\\MBN\\Apps\\MBNMovie\r\n'
        '    InstallDir    REG_SZ    D:\\Apps\\MBNMovie\r\n'
        '    Exe    REG_SZ    mbnmovie.exe\r\n';
    expect(
      AppLinks.parseRegQueryValue(output, 'InstallDir'),
      r'D:\Apps\MBNMovie',
    );
    expect(AppLinks.parseRegQueryValue(output, 'Missing'), isNull);
    expect(AppLinks.parseRegQueryValue('not-a-registry-dump', 'InstallDir'), isNull);
  });

  test('sibling metadata points at the movie app', () {
    expect(siblingMovie.androidPackage, 'com.mbn.movie');
    expect(siblingMovie.windowsExe, 'mbnmovie.exe');
    expect(
      siblingMovie.githubReleasesUrl,
      'https://github.com/MBNpro-ir/MBNMovie-App/releases/latest',
    );
  });
}
