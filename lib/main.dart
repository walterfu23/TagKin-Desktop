import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/auth/clerk_theme.dart';
import 'package:tagkin_desktop/library/items_list_page.dart';

/// App name shown in the shell.
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
        colorScheme: ColorScheme.fromSeed(seedColor: kTagKinClerkAccent),
        useMaterial3: true,
        extensions: <ThemeExtension<dynamic>>[tagKinClerkTheme()],
      ),
      // SelectionArea: all Text in the window is selectable/copyable (desktop rule).
      home: const SelectionArea(
        child: AuthShell(signedInHome: ItemsListPage()),
      ),
    );
  }
}
