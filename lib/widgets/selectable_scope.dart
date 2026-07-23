import 'package:flutter/material.dart';

/// Makes descendant [Text] selectable/copyable.
///
/// Must sit **under** the app [Overlay] (i.e. inside a route), not in
/// [MaterialApp.builder] — [SelectionArea] requires an Overlay ancestor.
class SelectableScope extends StatelessWidget {
  const SelectableScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SelectionArea(child: child);
}
