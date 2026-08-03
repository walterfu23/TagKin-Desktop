import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/persons/collection_navigation.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/prefs/settings_navigation.dart';
import 'package:tagkin_desktop/shell/quit_navigation.dart';

/// macOS system menu bar: TagKin / File / Window.
///
/// Under development — collection File menu is WIP, not shipped.
/// On non-macOS this is a pass-through (Windows uses in-app File menu).
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
      // Custom Quit owns dirty-collection confirm via window_manager; do not use
      // PlatformProvidedMenuItemType.quit (routes through didRequestAppExit).
      PlatformMenuItemGroup(
        members: [
          PlatformMenuItem(
            label: 'Quit TagKin',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyQ,
              meta: true,
            ),
            onSelected: () {
              requestQuitAppOrExitNow(ref);
            },
          ),
        ],
      ),
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

    final cols = ref.watch(collectionsControllerProvider);
    final sessionReady = cols.sessionReady;
    final recents = cols.recentCollections;

    final fileMenus = <PlatformMenuItem>[
      PlatformMenuItemGroup(
        members: [
          PlatformMenuItem(
            label: 'New Collection…',
            onSelected: sessionReady
                ? () => requestCollectionMenu(
                      ref,
                      CollectionMenuCommand.newCollection,
                    )
                : null,
          ),
          PlatformMenuItem(
            label: 'Open Collection…',
            onSelected: sessionReady
                ? () => requestCollectionMenu(
                      ref,
                      CollectionMenuCommand.open,
                    )
                : null,
          ),
          if (recents.isNotEmpty)
            PlatformMenu(
              label: 'Open Recent',
              menus: [
                for (final c in recents)
                  PlatformMenuItem(
                    label: c.name,
                    onSelected: sessionReady
                        ? () => requestCollectionMenu(
                              ref,
                              CollectionMenuCommand.openRecent,
                              recentCollectionId: c.id,
                            )
                        : null,
                  ),
              ],
            ),
        ],
      ),
      PlatformMenuItemGroup(
        members: [
          PlatformMenuItem(
            label: 'Save Collection',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyS,
              meta: true,
            ),
            onSelected: sessionReady && cols.dirty
                ? () => requestCollectionMenu(
                      ref,
                      CollectionMenuCommand.save,
                    )
                : null,
          ),
          PlatformMenuItem(
            label: 'Save Collection as…',
            onSelected: sessionReady
                ? () => requestCollectionMenu(
                      ref,
                      CollectionMenuCommand.saveAs,
                    )
                : null,
          ),
          PlatformMenuItem(
            label: 'Rename Collection…',
            onSelected: sessionReady
                ? () => requestCollectionMenu(
                      ref,
                      CollectionMenuCommand.rename,
                    )
                : null,
          ),
          PlatformMenuItem(
            label: 'Delete Collection…',
            onSelected: sessionReady
                ? () => requestCollectionMenu(
                      ref,
                      CollectionMenuCommand.delete,
                    )
                : null,
          ),
        ],
      ),
      PlatformMenuItemGroup(
        members: [
          PlatformMenuItem(
            label: 'Add Folder to Collection…',
            onSelected: sessionReady
                ? () => requestCollectionMenu(
                      ref,
                      CollectionMenuCommand.addFolder,
                    )
                : null,
          ),
          PlatformMenuItem(
            label: 'Remove Folder from Collection…',
            onSelected: sessionReady
                ? () => requestCollectionMenu(
                      ref,
                      CollectionMenuCommand.removeFolder,
                    )
                : null,
          ),
        ],
      ),
    ];

    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'TagKin',
          menus: appMenusNonEmpty,
        ),
        PlatformMenu(
          label: 'File',
          menus: fileMenus,
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
