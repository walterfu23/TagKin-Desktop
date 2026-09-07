import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/auth/login_hero.dart';
import 'package:tagkin_desktop/branding.g.dart';

void main() {
  testWidgets('login hero shows the TagFam poster, app name, and tagline', (
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
}
