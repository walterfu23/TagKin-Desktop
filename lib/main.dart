import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/auth/clerk_theme.dart';
import 'package:tagkin_desktop/library/items_list_page.dart';
import 'package:tagkin_desktop/shell/app_navigator.dart';
import 'package:tagkin_desktop/shell/tagkin_platform_menu.dart';
import 'package:tagkin_desktop/undo/undo_shortcuts.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';
import 'package:window_manager/window_manager.dart';

/// App name shown in the shell.
const String kAppTitle = 'TagKin';

bool get _isDesktopOs =>
    !kIsWeb && (Platform.isMacOS || Platform.isWindows);

bool get _runningInFlutterTest =>
    Platform.environment.containsKey('FLUTTER_TEST');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_isDesktopOs && !_runningInFlutterTest) {
    await windowManager.ensureInitialized();
  }
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
        navigatorKey: tagkinRootNavigatorKey,
        title: kAppTitle,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: kTagKinClerkAccent),
          useMaterial3: true,
          extensions: <ThemeExtension<dynamic>>[tagKinClerkTheme()],
        ),
        // Shortcuts must wrap the Navigator (builder), not only `home`.
        // A pushed route's FocusScope sits above that page's widgets; if
        // Cmd/Ctrl+Z is only registered on `home`, item detail beeps and
        // the stack never moves. SelectionArea stays per-route (needs Overlay).
        builder: (context, child) {
          return ActiveUndoShortcuts(
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const SelectableScope(
          child: AuthShell(signedInHome: ItemsListPage()),
        ),
      ),
    );
  }
}
