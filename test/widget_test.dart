import 'package:mbnime/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('MBNime starts with its branded launch experience', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const MbnimeApp());
    // On Windows hosts the custom title bar renders an extra 'MBNime'
    // next to the splash brand mark, so accept one or more matches.
    expect(find.text('MBNime'), findsWidgets);
    expect(find.text('دنیای تماشا، دوباره روشن شد'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('خوش برگشتی'), findsOneWidget);
  });
}
