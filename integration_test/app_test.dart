// D0 integration smoke: boot the real app on the host desktop (macOS/Windows)
// and confirm the foundation shell renders. Run with:
//   flutter test integration_test/app_test.dart -d macos   (or -d windows)

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tagkin_desktop/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('foundation shell boots on the desktop host',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: TagKinDesktopApp()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('foundation-ready')), findsOneWidget);
  });
}
