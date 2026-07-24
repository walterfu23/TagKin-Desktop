import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/prefs/settings_navigation.dart';

/// macOS system menu bar: TagKin → Settings… (Cmd+,).
///
/// On non-macOS this is a pass-through so Windows keeps the in-app gear only.
class TagKinPlatformMenu extends ConsumerWidget {
  const TagKinPlatformMenu({
    super.key,
    required this.child,
  });

  final Widget child;

  static bool _has(PlatformProvidedMenuItemType type) =>
      PlatformProvidedMenuItem.hasMenu(type);

  static PlatformProvidedMenuItem? _provided(PlatformProvidedMenuItemType type) {
    if (!_has(type)) return null;
    return PlatformProvidedMenuItem(type: type);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Platform.isMacOS) return child;

    final about = _provided(PlatformProvidedMenuItemType.about);
    final services = _provided(PlatformProvidedMenuItemType.servicesSubmenu);
    final hide = _provided(PlatformProvidedMenuItemType.hide);
    final hideOthers =
        _provided(PlatformProvidedMenuItemType.hideOtherApplications);
    final showAll = _provided(PlatformProvidedMenuItemType.showAllApplications);
    final quit = _provided(PlatformProvidedMenuItemType.quit);
    final minimize = _provided(PlatformProvidedMenuItemType.minimizeWindow);
    final zoom = _provided(PlatformProvidedMenuItemType.zoomWindow);
    final fullScreen = _provided(PlatformProvidedMenuItemType.toggleFullScreen);

    final appMenus = <PlatformMenuItem>[
      if (about != null) PlatformMenuItemGroup(members: [about]),
      PlatformMenuItemGroup(
        members: [
          PlatformMenuItem(
            label: 'Settings…',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.comma,
              meta: true,
            ),
            onSelected: () => requestOpenSettings(ref),
          ),
        ],
      ),
      if (services != null) PlatformMenuItemGroup(members: [services]),
      PlatformMenuItemGroup(
        members: [
          ?hide,
          ?hideOthers,
          ?showAll,
        ],
      ),
      if (quit != null) PlatformMenuItemGroup(members: [quit]),
    ];

    final appMenusNonEmpty = appMenus.where((item) {
      if (item is PlatformMenuItemGroup) return item.members.isNotEmpty;
      return true;
    }).toList();

    final windowMenus = <PlatformMenuItem>[
      ?minimize,
      ?zoom,
      ?fullScreen,
    ];

    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'TagKin',
          menus: appMenusNonEmpty,
        ),
        if (windowMenus.isNotEmpty)
          PlatformMenu(
            label: 'Window',
            menus: windowMenus,
          ),
      ],
      child: child,
    );
  }
}
