import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Top-level signed-in destinations (Folders / Faces / Persons).
enum TopLevelTab { folders, faces, persons }

/// Which top-level tab is visible in the signed-in shell.
final activeTopLevelTabProvider = StateProvider<TopLevelTab>(
  (ref) => TopLevelTab.folders,
);

/// Folders / Faces / Persons AppBar icons.
///
/// Default tap: switch [activeTopLevelTabProvider] and pop to the first route
/// (the signed-in shell). Pass [onSelected] from the shell itself so tabs
/// switch without popping. [onBeforeNavigate] gates leave (item dirty edits).
class AppNavTabButtons extends ConsumerWidget {
  const AppNavTabButtons({
    super.key,
    this.onSelected,
    this.onBeforeNavigate,
  });

  /// When set, called instead of pop-to-root after the tab is chosen.
  final void Function(TopLevelTab)? onSelected;

  /// Awaited first; navigation is skipped when this returns false.
  final Future<bool> Function()? onBeforeNavigate;

  Future<void> _go(
    BuildContext context,
    WidgetRef ref,
    TopLevelTab tab,
  ) async {
    if (onBeforeNavigate != null) {
      final ok = await onBeforeNavigate!();
      if (!ok) return;
    }
    final selected = onSelected;
    if (selected != null) {
      selected(tab);
      return;
    }
    ref.read(activeTopLevelTabProvider.notifier).state = tab;
    if (!context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTab = ref.watch(activeTopLevelTabProvider);
    return SelectionContainer.disabled(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const Key('nav-folders'),
            tooltip: 'Folders',
            onPressed: () => unawaited(_go(context, ref, TopLevelTab.folders)),
            icon: Icon(
              activeTab == TopLevelTab.folders
                  ? Icons.folder
                  : Icons.folder_outlined,
            ),
          ),
          IconButton(
            key: const Key('nav-face-crops'),
            tooltip: 'Faces',
            onPressed: () => unawaited(_go(context, ref, TopLevelTab.faces)),
            icon: Icon(
              activeTab == TopLevelTab.faces
                  ? Icons.face_retouching_natural
                  : Icons.face_retouching_natural_outlined,
            ),
          ),
          IconButton(
            key: const Key('nav-persons'),
            tooltip: 'Persons',
            onPressed: () => unawaited(_go(context, ref, TopLevelTab.persons)),
            icon: Icon(
              activeTab == TopLevelTab.persons
                  ? Icons.people
                  : Icons.people_outline,
            ),
          ),
        ],
      ),
    );
  }
}
