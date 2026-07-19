// D0 foundation smoke test: the app boots and renders the foundation shell.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tagkin_desktop/main.dart';

void main() {
  testWidgets('app boots to the foundation shell', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: TagKinDesktopApp()));

    expect(find.byKey(const Key('foundation-ready')), findsOneWidget);
    expect(find.text(kAppTitle), findsWidgets);
  });
}
