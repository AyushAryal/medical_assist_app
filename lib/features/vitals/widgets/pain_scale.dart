import 'package:flutter/material.dart';

import '../../../core/design/design.dart';

/// 0–10 numeric pain scale as tappable targets rather than a slider — a slider
/// cannot be hit accurately with a gloved thumb.
class PainScale extends StatelessWidget {
  const PainScale({super.key, required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Pain score (0–10)', style: context.texts.labelMedium),
        SizedBox(height: m.spaceSm),
        Wrap(
          spacing: m.spaceXs,
          runSpacing: m.spaceXs,
          children: List<Widget>.generate(11, (index) {
            final isSelected = value == index;
            return SizedBox(
              width: 40,
              child: ChoiceChip(
                label: Center(child: Text('$index')),
                labelPadding: EdgeInsets.zero,
                selected: isSelected,
                onSelected: (selected) => onChanged(selected ? index : null),
              ),
            );
          }),
        ),
      ],
    );
  }
}
