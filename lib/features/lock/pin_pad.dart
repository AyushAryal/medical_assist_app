import 'package:flutter/material.dart';

import '../../core/design/design.dart';


/// A fixed on-screen keypad rather than the system keyboard.
///
/// The layout never shifts, so entry becomes muscle memory, and the digits
/// cannot be captured by a third-party keyboard — which on a medical device is
/// a real concern, not a theoretical one.
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.onBiometric,
    this.enabled = true,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final row in const <List<String>>[
            <String>['1', '2', '3'],
            <String>['4', '5', '6'],
            <String>['7', '8', '9'],
          ])
            Padding(
              padding: EdgeInsets.only(bottom: m.spaceMd),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: row
                    .map((digit) => _PinKey(
                          label: digit,
                          enabled: enabled,
                          onTap: () => onDigit(digit),
                        ))
                    .toList(),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              _PinKey(
                icon: onBiometric == null ? null : Icons.fingerprint,
                enabled: enabled && onBiometric != null,
                onTap: onBiometric ?? () {},
              ),
              _PinKey(
                label: '0',
                enabled: enabled,
                onTap: () => onDigit('0'),
              ),
              _PinKey(
                icon: Icons.backspace_outlined,
                enabled: enabled,
                onTap: onBackspace,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PinKey extends StatelessWidget {
  const _PinKey({
    this.label,
    this.icon,
    required this.onTap,
    required this.enabled,
  });

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    const double size = 76;

    if (label == null && icon == null) {
      return const SizedBox(width: size, height: size);
    }

    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: palette.surface,
        shape: CircleBorder(
          side: BorderSide(color: palette.outline, width: context.metrics.borderWidth),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Center(
            child: label != null
                ? Text(
                    label!,
                    style: context.texts.headlineSmall?.copyWith(
                      color: enabled ? palette.onSurface : palette.onSurfaceMuted,
                    ),
                  )
                : Icon(
                    icon,
                    color: enabled ? palette.onSurface : palette.onSurfaceMuted,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Filled/empty dots showing entry progress without revealing the digits.
class PinDots extends StatelessWidget {
  const PinDots({
    super.key,
    required this.length,
    required this.filled,
    this.hasError = false,
  });

  final int length;
  final int filled;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(length, (index) {
        final isFilled = index < filled;
        return Container(
          margin: EdgeInsets.symmetric(horizontal: m.spaceSm),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled
                ? (hasError ? palette.critical : palette.primary)
                : Colors.transparent,
            border: Border.all(
              color: hasError ? palette.critical : palette.outlineStrong,
              width: 1.5,
            ),
          ),
        );
      }),
    );
  }
}
