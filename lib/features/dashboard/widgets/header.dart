import 'package:flutter/material.dart';

import '../../../core/design/design.dart';
import '../../../core/utils/formatters.dart';

class Header extends StatelessWidget {
  const Header({
    super.key,
    required this.greeting,
    required this.name,
    required this.clinicName,
    required this.onSwitchClinic,
  });

  final String greeting;
  final String name;
  final String? clinicName;
  final VoidCallback onSwitchClinic;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;
    final trimmed = name.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          Fmt.weekday(DateTime.now()).toUpperCase(),
          style: context.texts.labelSmall?.copyWith(letterSpacing: 1.1),
        ),
        SizedBox(height: m.spaceXs),
        Text(
          trimmed.isEmpty ? greeting : '$greeting, $trimmed',
          style: context.texts.headlineMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: m.spaceMd),
        // Always visible and always one tap away: filing an encounter against
        // the wrong site produces a record nobody can find.
        Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: palette.surface,
            borderRadius: BorderRadius.circular(m.radiusLg),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onSwitchClinic,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: m.spaceMd,
                  vertical: m.spaceSm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: palette.primary,
                    ),
                    SizedBox(width: m.spaceXs + 2),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(
                        clinicName ?? 'No clinic selected',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.labelMedium,
                      ),
                    ),
                    SizedBox(width: m.spaceXs),
                    Icon(
                      Icons.unfold_more,
                      size: 15,
                      color: palette.onSurfaceMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
