import 'package:flutter/material.dart';

import '../theme/app_theme.dart'
    show kPillNavBarHeight, pillNavBottomMargin;
import '../theme/theme_scope.dart';

/// How much horizontal room the window actually has.
///
/// Named by available space rather than by device, because a device is not a
/// width: a phone in landscape, a small tablet in portrait and a split-screen
/// tablet can all land in [medium], and asking "is this a tablet?" gives the
/// wrong answer for every one of them.
enum Breakpoint {
  /// Phone portrait. One column, bottom navigation, detail opens as a page.
  compact,

  /// Phone landscape, small tablet portrait. Two content columns fit; a
  /// master–detail split does not.
  medium,

  /// Tablet landscape and desktop. A list and a full detail pane fit side by
  /// side with room to spare.
  expanded;

  bool get isCompact => this == Breakpoint.compact;

  /// True where a persistent detail pane is worth showing. This is the single
  /// question the navigation layer asks.
  bool get hasDetailPane => this == Breakpoint.expanded;

  /// Sensible column count for a flow of independent cards.
  int get contentColumns => switch (this) {
    Breakpoint.compact => 1,
    Breakpoint.medium => 2,
    Breakpoint.expanded => 2,
  };
}

extension BreakpointX on BuildContext {
  Breakpoint get breakpoint {
    final width = MediaQuery.sizeOf(this).width;
    final m = metrics;
    if (width >= m.wideBreakpoint) return Breakpoint.expanded;
    if (width >= m.tabletBreakpoint) return Breakpoint.medium;
    return Breakpoint.compact;
  }

  /// True when vertical space is the scarce dimension — phone and tablet
  /// landscape. A form that stacks fine in portrait becomes a scroll-fest
  /// here, which is the whole reason side-by-side layouts exist.
  bool get isLandscape =>
      MediaQuery.orientationOf(this) == Orientation.landscape;

  /// Short landscape: a tablet on its side has usable width but so little
  /// height that a vertically stacked header plus a scrolling body wastes
  /// most of the screen.
  bool get isShortLandscape =>
      isLandscape && MediaQuery.sizeOf(this).height < 620;

  /// How much vertical space [AppShell]'s compact bottom navigation bar
  /// actually occupies, for content that runs underneath it.
  ///
  /// The compact shell uses `Scaffold(extendBody: true)` so its glass-blur
  /// bar has body content to sample through — which means the [Scaffold]
  /// does *not* auto-inset the body, and every scrollable behind the bar
  /// must reserve this space itself rather than relying on the framework.
  ///
  /// The figure is the bar's themed content height ([kAppNavigationBarHeight])
  /// plus the device's own bottom inset, because [NavigationBar] wraps
  /// itself in a [SafeArea] and grows to clear the home indicator or gesture
  /// bar on top of that configured height. That inset is 0 on some Android
  /// devices, ~34 on an iPhone with a home indicator, and something else
  /// again on a foldable or an iPad — hence reading it from [MediaQuery]
  /// rather than hardcoding it.
  ///
  /// Zero on medium/expanded breakpoints: those use a side rail instead of a
  /// bottom bar, so content never sits underneath anything there.
  double get bottomBarClearance {
    if (!breakpoint.isCompact) return 0;
    // The floating pill: its height, the margin it floats above the edge,
    // and a breath of space so content never kisses the pill.
    final inset = MediaQuery.paddingOf(this).bottom;
    return kPillNavBarHeight + pillNavBottomMargin(inset) + 8;
  }
}

/// A list beside the thing it opens.
///
/// On [Breakpoint.expanded] both panes are live: tapping a row swaps the detail
/// pane and the list keeps its scroll position and selection, which is what
/// makes working through a clinic list on a tablet fast. Below that the detail
/// is not rendered at all and the caller navigates to it as a page — the same
/// widget tree, reached a different way, so there is one implementation of the
/// detail screen rather than two.
class TwoPane extends StatelessWidget {
  const TwoPane({
    super.key,
    required this.master,
    required this.detail,
    this.masterFlex = 2,
    this.detailFlex = 3,
    this.minMasterWidth = 300,
    this.maxMasterWidth = 420,
  });

  final Widget master;

  /// Built only when a detail pane is actually shown, so the caller can pass
  /// an expensive screen without paying for it on a phone.
  final WidgetBuilder detail;

  final int masterFlex;
  final int detailFlex;
  final double minMasterWidth;
  final double maxMasterWidth;

  @override
  Widget build(BuildContext context) {
    if (!context.breakpoint.hasDetailPane) return master;

    final palette = context.palette;
    final m = context.metrics;
    final width = MediaQuery.sizeOf(context).width;

    // Flex first, then clamped: a 2:3 split of a very wide window gives the
    // list more room than a list needs, and a narrow expanded window would
    // otherwise squeeze it below usability.
    final masterWidth = (width * masterFlex / (masterFlex + detailFlex)).clamp(
      minMasterWidth,
      maxMasterWidth,
    );

    return Row(
      children: <Widget>[
        SizedBox(width: masterWidth, child: master),
        Container(width: m.hairline, color: palette.outline),
        Expanded(child: Builder(builder: detail)),
      ],
    );
  }
}

/// The empty state of a detail pane — shown when nothing is selected yet.
///
/// A blank half-screen reads as a bug. This says what the pane is for.
class DetailPanePlaceholder extends StatelessWidget {
  const DetailPanePlaceholder({
    super.key,
    required this.icon,
    required this.title,
    this.message,
  });

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(m.space2xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 40, color: palette.onSurfaceMuted),
            SizedBox(height: m.spaceMd),
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.texts.titleMedium,
            ),
            if (message != null) ...<Widget>[
              SizedBox(height: m.spaceXs),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: context.texts.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Two editorial columns: what the reader came for, and what supports it.
///
/// Unlike a masonry flow this does **not** reorder content by height. On a
/// clinical chart, which section a clinician's eye lands on first is a safety
/// property — allergies must not migrate to the bottom-right because a column
/// balanced better that way. The caller decides what is primary; on a narrow
/// screen the two lists concatenate in that same order.
class SplitColumns extends StatelessWidget {
  const SplitColumns({
    super.key,
    required this.primary,
    required this.secondary,
    this.spacing,
    this.primaryFlex = 3,
    this.secondaryFlex = 2,
    this.force = false,
  });

  final List<Widget> primary;
  final List<Widget> secondary;
  final double? spacing;
  final int primaryFlex;
  final int secondaryFlex;

  /// Split even on [Breakpoint.medium]. Worth it for reference material that
  /// reads fine in a narrow column; wrong for anything with a wide table.
  final bool force;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final gap = spacing ?? m.spaceLg;
    final breakpoint = context.breakpoint;
    final split =
        breakpoint == Breakpoint.expanded ||
        (force && breakpoint == Breakpoint.medium);

    if (!split) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _interleave(<Widget>[...primary, ...secondary], gap),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          flex: primaryFlex,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _interleave(primary, gap),
          ),
        ),
        SizedBox(width: gap),
        Expanded(
          flex: secondaryFlex,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _interleave(secondary, gap),
          ),
        ),
      ],
    );
  }

  static List<Widget> _interleave(List<Widget> children, double gap) {
    final out = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) out.add(SizedBox(height: gap));
      out.add(children[i]);
    }
    return out;
  }
}

/// Flows independent, interchangeable cards into as many columns as fit.
///
/// Use only where order genuinely does not matter — a grid of counts, a set of
/// action tiles. For anything a clinician reads in sequence, use
/// [SplitColumns] and choose the order deliberately.
class AdaptiveColumns extends StatelessWidget {
  const AdaptiveColumns({
    super.key,
    required this.children,
    this.minColumnWidth = 320,
    this.spacing,
    this.maxColumns = 3,
  });

  final List<Widget> children;
  final double minColumnWidth;
  final double? spacing;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    final gap = spacing ?? context.metrics.spaceLg;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = ((constraints.maxWidth + gap) / (minColumnWidth + gap))
            .floor()
            .clamp(1, maxColumns);

        if (columns == 1 || children.length == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: SplitColumns._interleave(children, gap),
          );
        }

        // Round-robin rather than sequential chunks: chunking puts every short
        // card in one column and every tall one in the other, and the page
        // ends with a column of dead space as long as the content itself.
        final buckets = List<List<Widget>>.generate(columns, (_) => <Widget>[]);
        for (var i = 0; i < children.length; i++) {
          buckets[i % columns].add(children[i]);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (var i = 0; i < buckets.length; i++) ...<Widget>[
              if (i > 0) SizedBox(width: gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: SplitColumns._interleave(buckets[i], gap),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
