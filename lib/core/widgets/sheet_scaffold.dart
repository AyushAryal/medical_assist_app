import 'package:flutter/material.dart';

import '../theme/theme_scope.dart';

/// The shared shell for a modal bottom sheet that holds a short form.
///
/// Every such sheet needs the same three things right and had been getting
/// them right by copy: a `SafeArea`, bottom padding that grows with the
/// keyboard (`viewInsets`), and a scroll so a small screen with the keyboard
/// up can still reach the save button. Getting any of those wrong strands the
/// button under the keyboard. Centralising the shell means it is right once.
///
/// The body is [children]; the footer is a single `FilledButton` driven by
/// [onSave] (disabled when null, so a `_busy` guard is just `busy ? null :
/// _save`). A sheet that needs a different footer — two actions, an icon that
/// is not `FilledButton.icon`, a destructive button — passes [footer] and
/// owns it entirely. Genuinely bespoke sheets (a generated-text review with
/// its own header and layout) do not use this at all, and should not be
/// forced to.
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.onSave,
    this.saveLabel = 'Save',
    this.saveIcon,
    this.footer,
    this.formKey,
    this.dragHandle = false,
    this.maxHeightFraction,
  });

  /// The heading, shown as `titleMedium`.
  final String title;

  /// An optional line under the title, shown as `bodySmall`.
  final String? subtitle;

  /// The form fields, stretched to the sheet width.
  final List<Widget> children;

  /// The default footer button's action. Null disables the button.
  final VoidCallback? onSave;

  /// The default footer button's label.
  final String saveLabel;

  /// When set, the footer button is a `FilledButton.icon` with this icon.
  final IconData? saveIcon;

  /// Replaces the default footer button entirely.
  final Widget? footer;

  /// When set, the body is wrapped in a `Form` with this key.
  final GlobalKey<FormState>? formKey;

  /// Show a Material drag handle at the top of the sheet.
  final bool dragHandle;

  /// Caps the sheet height to this fraction of the screen (for tall bodies).
  final double? maxHeightFraction;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    Widget footerWidget;
    if (footer != null) {
      footerWidget = footer!;
    } else if (saveIcon != null) {
      footerWidget = FilledButton.icon(
        onPressed: onSave,
        icon: Icon(saveIcon),
        label: Text(saveLabel),
      );
    } else {
      footerWidget = FilledButton(
        onPressed: onSave,
        child: Text(saveLabel),
      );
    }

    Widget body = SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: context.texts.titleMedium),
          if (subtitle != null) ...<Widget>[
            SizedBox(height: m.spaceXs),
            Text(subtitle!, style: context.texts.bodySmall),
          ],
          SizedBox(height: m.spaceLg),
          ...children,
          SizedBox(height: m.spaceXl),
          footerWidget,
        ],
      ),
    );

    if (formKey != null) {
      body = Form(key: formKey, child: body);
    }
    if (maxHeightFraction != null) {
      body = ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * maxHeightFraction!,
        ),
        child: body,
      );
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: m.spaceLg,
          right: m.spaceLg,
          top: dragHandle ? 0 : m.spaceLg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + m.spaceLg,
        ),
        child: dragHandle
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _DragHandle(color: context.palette.outline),
                  SizedBox(height: m.spaceSm),
                  Flexible(child: body),
                ],
              )
            : body,
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 4,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
