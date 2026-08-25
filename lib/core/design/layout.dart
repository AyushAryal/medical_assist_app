import 'package:flutter/material.dart';

import '../theme/theme_scope.dart';
import 'adaptive.dart';

/// Caps body width on large screens.
///
/// Full-bleed text on a tablet is hard to read, and a clinical note especially
/// needs a bounded measure — roughly 90 characters, which is what
/// `contentMaxWidth` encodes.
///
/// The cap is a *measure* for running text, not a page width. Applying it to a
/// screen whose content is panels rather than prose is what leaves a landscape
/// tablet showing a narrow strip between two empty margins, so screens that
/// lay out in columns use [ContentWidth.columns] and let the layout, not this
/// widget, decide the measure.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth})
      : _mode = _WidthMode.measure;

  /// For bodies that arrange themselves into columns. The cap widens with the
  /// window so two full-measure columns fit side by side, instead of squeezing
  /// them into the width of one.
  const ContentWidth.columns({super.key, required this.child, this.maxWidth})
      : _mode = _WidthMode.columns;

  /// No cap at all — for a body that manages its own margins, such as a
  /// calendar grid or a pane that is already width-constrained by its parent.
  const ContentWidth.fill({super.key, required this.child})
      : maxWidth = null,
        _mode = _WidthMode.fill;

  final Widget child;
  final double? maxWidth;
  final _WidthMode _mode;

  @override
  Widget build(BuildContext context) {
    if (_mode == _WidthMode.fill) return child;

    final base = maxWidth ?? context.metrics.contentMaxWidth;
    final cap = _mode == _WidthMode.columns
        ? switch (context.breakpoint) {
            // Two columns plus the gutter between them.
            Breakpoint.expanded => base * 2 + context.metrics.spaceLg,
            Breakpoint.medium => base * 1.35,
            Breakpoint.compact => base,
          }
        : base;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: cap),
        child: child,
      ),
    );
  }
}

enum _WidthMode { measure, columns, fill }

/// Standard vertical rhythm between stacked panels.
///
/// Screens use these rather than literal `SizedBox(height: 12)` so spacing
/// stays consistent and stays editable from the token file.
class Gap extends StatelessWidget {
  const Gap.xs({super.key}) : _scale = _Scale.xs;
  const Gap.sm({super.key}) : _scale = _Scale.sm;
  const Gap.md({super.key}) : _scale = _Scale.md;
  const Gap.lg({super.key}) : _scale = _Scale.lg;
  const Gap.xl({super.key}) : _scale = _Scale.xl;

  final _Scale _scale;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    return SizedBox(
      height: switch (_scale) {
        _Scale.xs => m.spaceXs,
        _Scale.sm => m.spaceSm,
        _Scale.md => m.spaceMd,
        _Scale.lg => m.spaceLg,
        _Scale.xl => m.spaceXl,
      },
    );
  }
}

/// Horizontal counterpart to [Gap].
class HGap extends StatelessWidget {
  const HGap.xs({super.key}) : _scale = _Scale.xs;
  const HGap.sm({super.key}) : _scale = _Scale.sm;
  const HGap.md({super.key}) : _scale = _Scale.md;
  const HGap.lg({super.key}) : _scale = _Scale.lg;

  final _Scale _scale;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    return SizedBox(
      width: switch (_scale) {
        _Scale.xs => m.spaceXs,
        _Scale.sm => m.spaceSm,
        _Scale.md => m.spaceMd,
        _Scale.lg => m.spaceLg,
        _Scale.xl => m.spaceXl,
      },
    );
  }
}

enum _Scale { xs, sm, md, lg, xl }

/// Page padding for a scrolling body, including room for the floating nav bar.
EdgeInsets pagePadding(BuildContext context, {bool floatingBar = true}) {
  final m = context.metrics;
  return EdgeInsets.fromLTRB(
    m.spaceLg,
    m.spaceSm,
    m.spaceLg,
    floatingBar ? m.space2xl * 3 : m.spaceXl,
  );
}
