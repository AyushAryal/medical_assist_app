import 'package:flutter/material.dart';

import '../theme/theme_scope.dart';
import 'glass.dart';

/// A titled block of content. The whole app is built from these so that a
/// chart reads as a sequence of labelled sections rather than a wall of fields.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.padding,
    this.onTap,
    required this.child,
  });

  final String? title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (title != null) ...<Widget>[
          Row(
            children: <Widget>[
              if (leading != null) ...<Widget>[
                leading!,
                SizedBox(width: m.spaceSm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title!, style: context.texts.titleMedium),
                    if (subtitle != null)
                      Text(subtitle!, style: context.texts.bodySmall),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          SizedBox(height: m.spaceMd),
        ],
        child,
      ],
    );

    return GlassPanel(
      onTap: onTap,
      padding: padding ?? EdgeInsets.all(m.spaceLg),
      child: content,
    );
  }

  static Widget divider(BuildContext context) => Divider(
        height: context.metrics.spaceLg,
        thickness: context.metrics.hairline,
        color: context.palette.outline,
      );
}
