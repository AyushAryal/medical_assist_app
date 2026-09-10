import 'package:flutter/material.dart';

import '../../core/design/design.dart';

/// Full-height arrangement shared by the lock and PIN-setup screens.
///
/// Instead of one centred blob with dead bands above and below it, the
/// screen's height is put to work: identity at the top, entry progress in
/// the middle, and the keypad anchored to the bottom where thumbs already
/// are. On a short window (landscape, split view) it degrades to scrolling.
class LockLayout extends StatelessWidget {
  const LockLayout({
    super.key,
    required this.header,
    required this.progress,
    required this.keypad,
  });

  /// Icon, title and subtitle block shown near the top.
  final Widget header;

  /// Entry-progress block (dots plus the message slot).
  final Widget progress;

  /// The keypad, anchored to the bottom edge.
  final Widget keypad;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: m.spaceXl),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.only(top: m.space2xl),
                  child: header,
                ),
                progress,
                Padding(
                  padding: EdgeInsets.only(bottom: m.spaceLg),
                  child: keypad,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
