import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/design.dart';

/// Top-level navigation frame.
///
/// Five destinations, which is the ceiling for a bottom bar: beyond that the
/// labels truncate and the targets get too narrow for a gloved thumb.
///
/// Three shapes, chosen by available width rather than by device:
///
/// * **Compact** — bottom bar. Thumb-reachable, which is what a phone held in
///   one hand while the other holds a stethoscope needs.
/// * **Medium** — collapsed rail. Vertical space is what a chart needs, and a
///   bottom bar spends 80 logical pixels of it on four labels.
/// * **Expanded** — extended rail with labels always visible. A tablet in
///   landscape has width to spare and, critically, *no* vertical space to
///   spare, so the labels cost nothing here and remove the icon guessing game.
///
/// The rail also gains the app title on an expanded screen, because a
/// landscape tablet has room for the product to identify itself and a phone
/// does not.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;
  static const List<_Destination> _destinations = <_Destination>[
    _Destination(
      label: 'Today',
      icon: Icons.today_outlined,
      selectedIcon: Icons.today,
    ),
    _Destination(
      label: 'Schedule',
      icon: Icons.event_outlined,
      selectedIcon: Icons.event,
    ),
    _Destination(
      label: 'Patients',
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
    ),
    _Destination(
      label: 'Ask',
      icon: Icons.travel_explore_outlined,
      selectedIcon: Icons.travel_explore,
    ),
    _Destination(
      label: 'Settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
    ),
  ];

  void _onSelect(int index) {
    if (index == navigationShell.currentIndex) return;
    navigationShell.goBranch(index);
  }

  @override
  Widget build(BuildContext context) {
    final breakpoint = context.breakpoint;

    if (!breakpoint.isCompact) {
      final extended = breakpoint == Breakpoint.expanded;
      final m = context.metrics;

      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Row(
          children: <Widget>[
            GlassChrome(
              child: NavigationRail(
                backgroundColor: Colors.transparent,
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: _onSelect,
                // An extended rail shows its own labels, and asking for
                // `all` as well throws.
                extended: extended,
                labelType: extended ? null : NavigationRailLabelType.all,
                leading: extended
                    ? Padding(
                        padding: EdgeInsets.only(
                          top: m.spaceLg,
                          bottom: m.spaceMd,
                          left: m.spaceSm,
                          right: m.spaceLg,
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              Icons.local_hospital_outlined,
                              size: 20,
                              color: context.palette.primary,
                            ),
                            SizedBox(width: m.spaceSm),
                            Text(
                              'Clinical Records',
                              style: context.texts.titleSmall,
                            ),
                          ],
                        ),
                      )
                    : null,
                destinations: _destinations
                    .map(
                      (d) => NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: Text(d.label),
                      ),
                    )
                    .toList(),
              ),
            ),
            Expanded(child: navigationShell),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      // Content runs under the bar so the blur has something to sample —
      // the bar reads as a material rather than an opaque strip.
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: GlassChrome(
        topBorder: true,
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: _onSelect,
          destinations: _destinations
              .map(
                (d) => NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: d.label,
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _Destination {
  const _Destination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
