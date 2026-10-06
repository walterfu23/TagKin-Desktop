import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/auth/login_hero.dart';
import 'package:tagkin_desktop/branding.g.dart';

void main() {
  testWidgets('login hero shows the branded poster, app name, and tagline', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 480, height: 640, child: LoginHero()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('login-hero')), findsOneWidget);
    expect(find.text(kAppName), findsOneWidget);
    expect(find.text(kLoginHeroTagline), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('a wide signed-out page shows the poster beside the form', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: SignedOutFrame(child: Text('Form'))),
    );
    expect(find.byKey(const Key('login-hero')), findsOneWidget);
    expect(find.text('Form'), findsOneWidget);
  });

  testWidgets('a narrow signed-out page shows only the form', (tester) async {
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: SignedOutFrame(child: Text('Form'))),
    );
    expect(find.byKey(const Key('login-hero')), findsNothing);
    expect(find.text('Form'), findsOneWidget);
  });
}
