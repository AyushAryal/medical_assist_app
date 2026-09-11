import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/design/design.dart';

/// One tab in the pill bar.
class PillNavDestination {
  const PillNavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// The floating pill tab bar.
///
/// A rounded capsule that floats above the bottom edge instead of a full-width
/// strip: content scrolls behind and beneath it, the glass fill samples that
/// content, and the selected tab is marked with a soft tint rather than a
/// second shape. One bar for both platforms — the pill *is* the design, so
/// handing Android a Material strip and iOS a Cupertino strip would give the
/// app two identities.
class PillNavBar extends StatelessWidget {
  const PillNavBar({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onTap,
  });

  final List<PillNavDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const double _radius = 28;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;

    final inset = MediaQuery.viewPaddingOf(context).bottom;
    final bottomMargin = pillNavBottomMargin(inset);
    final sideMargin = inset > 0 ? 16.0 : 12.0;

    return Padding(
      padding: EdgeInsets.only(
        left: sideMargin,
        right: sideMargin,
        bottom: bottomMargin,
      ),
      child: DecoratedBox(
        // Float the pill above the content behind it.
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: palette.shadow.withValues(
                alpha: context.isDark ? 0.5 : 0.18,
              ),
              blurRadius: 34,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: m.chromeBlur,
              sigmaY: m.chromeBlur,
            ),
            child: Container(
              height: kPillNavBarHeight,
              decoration: BoxDecoration(
                color: palette.surface.withValues(
                  alpha: context.chromeOpacity,
                ),
                borderRadius: BorderRadius.circular(_radius),
                border: Border.all(color: palette.outline, width: m.hairline),
              ),
              child: Row(
                children: <Widget>[
                  for (var i = 0; i < destinations.length; i++)
                    Expanded(
                      child: _PillTab(
                        destination: destinations[i],
                        selected: i == currentIndex,
                        onTap: () => onTap(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PillTab extends StatelessWidget {
  const _PillTab({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final PillNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;
    final tint = selected ? palette.primary : palette.onSurfaceMuted;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PillNavBar._radius),
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          // Narrow: five tabs share a phone-width pill, and "Schedule" at
          // 10pt needs the room more than the tint needs wings.
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            // The flat tint the rest of the app uses for "selected" — no
            // pill-in-pill shape competing with the bar's own silhouette.
            color: selected
                ? palette.primary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(m.radiusLg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                selected ? destination.selectedIcon : destination.icon,
                size: 22,
                color: tint,
              ),
              const SizedBox(height: 1),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: context.texts.labelSmall?.copyWith(
                  fontSize: 10,
                  height: 1.1,
                  color: tint,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
