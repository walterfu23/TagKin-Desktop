import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/app_shell.dart';

/// App name shown in the shell. Auth arrives in D1; library UI in D2+.
const String kAppTitle = 'TagKin';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      home: const AuthShell(signedInHome: FoundationHomePage()),
    );
  }
}

/// Post-auth placeholder until D2 Library. Confirms the signed-in shell boots.
class FoundationHomePage extends StatelessWidget {
  const FoundationHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'TagKin Desktop — foundation ready',
        key: Key('foundation-ready'),
      ),
    );
  }
}
