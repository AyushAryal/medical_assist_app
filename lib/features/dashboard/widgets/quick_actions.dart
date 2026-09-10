import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/design.dart';
import '../../../core/routing/app_router.dart';
import '../dashboard_controller.dart';

class QuickActions extends StatelessWidget {
  const QuickActions({
    super.key,
    required this.dashboard,
    required this.onBook,
    required this.onChanged,
  });

  final DashboardController dashboard;
  final Future<void> Function() onBook;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;

    final actions = <Widget>[
      QuickAction(
        icon: Icons.person_add_alt,
        label: 'New patient',
        tone: palette.primary,
        onTap: () async {
          await context.push(Routes.patientNew);
          await onChanged();
        },
      ),
      QuickAction(
        icon: Icons.event_available_outlined,
        label: 'Book visit',
        tone: palette.accent,
        onTap: onBook,
      ),
      QuickAction(
        icon: Icons.chair_outlined,
        label: 'Waiting room',
        tone: palette.caution,
        badgeCount: dashboard.waitingCount,
        onTap: () => context.go(Routes.schedule),
      ),
      QuickAction(
        icon: Icons.search,
        label: 'Find patient',
        tone: palette.info,
        onTap: () => context.go(Routes.patients),
      ),
    ];

    // Tile width decides this, not device class. A four-across row is too
    // cramped below roughly a 400dp phone, so the grid drops to two columns
    // rather than letting the labels clip; a wide window fits more than four
    // without stretching each tile into a banner.
    final columns = switch (context.breakpoint) {
      Breakpoint.expanded => 6,
      Breakpoint.medium => 4,
      Breakpoint.compact => MediaQuery.sizeOf(context).width < 400 ? 2 : 4,
    };

    return GridView.count(
      shrinkWrap: true,
      // Explicitly zero: a scrollable with no padding of its own inherits the
      // ambient safe-area insets, which here showed up as a ~60px dead band
      // above and below the grid, mid-page.
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: columns,
      mainAxisSpacing: m.spaceSm,
      crossAxisSpacing: m.spaceSm,
      // Fixed height rather than an aspect ratio: the tile content is a fixed
      // stack of icon and label, so tying height to width overflows on narrow
      // screens and leaves dead space on wide ones. 46px icon + spacing +
      // up to 2 lines of label (labels like "Waiting room" wrap at these
      // column widths) plus the tile's own vertical padding needs ~128px;
      // 116 was too tight and clipped the second label line.
      mainAxisExtent: 128,
      children: actions,
    );
  }
}
