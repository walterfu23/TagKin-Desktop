import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/auth/clerk_theme.dart';
import 'package:tagkin_desktop/library/items_list_page.dart';
import 'package:tagkin_desktop/shell/tagkin_platform_menu.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

/// App name shown in the shell.
const String kAppTitle = 'TagKin';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // D8 local video key-period scrubber (media_kit / libmpv).
  MediaKit.ensureInitialized();
  runApp(const ProviderScope(child: TagKinDesktopApp()));
}

class TagKinDesktopApp extends StatelessWidget {
  const TagKinDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return TagKinPlatformMenu(
      child: MaterialApp(
        title: kAppTitle,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: kTagKinClerkAccent),
          useMaterial3: true,
          extensions: <ThemeExtension<dynamic>>[tagKinClerkTheme()],
        ),
        // SelectionArea must be under Overlay (per route), not MaterialApp.builder.
        home: const SelectableScope(
          child: AuthShell(signedInHome: ItemsListPage()),
        ),
      ),
    );
  }
}
