import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App name shown in the D0 foundation shell. Real navigation/auth arrive in D1+.
const String kAppTitle = 'TagKin';

void main() {
  runApp(const ProviderScope(child: TagKinDesktopApp()));
}

class TagKinDesktopApp extends StatelessWidget {
  const TagKinDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B5BDB)),
        useMaterial3: true,
      ),
      home: const FoundationHomePage(),
    );
  }
}

/// D0 placeholder surface. Confirms the app boots on macOS + Windows and that
/// Riverpod + the generated contract are wired. Replaced by the auth shell in D1.
class FoundationHomePage extends StatelessWidget {
  const FoundationHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(kAppTitle)),
      body: const Center(
        child: Text(
          'TagKin Desktop — foundation ready',
          key: Key('foundation-ready'),
        ),
      ),
    );
  }
}
